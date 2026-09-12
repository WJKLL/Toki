// lib/core/depth/onnx_depth_inference.dart
// 编号：S-31 深度推理服务（ONNX Runtime 实现）
//
// ★ 本文件是**主项目独有**：依赖 flutter_onnxruntime，而该包不支持 OpenHarmony
//   （实测其平台声明只有 android/ios/macos/windows/linux/web）。
//   鸿蒙侧需另写实现（@ohos/onnxruntime + MethodChannel 插件），
//   经 DepthInferenceRegistry.register() 注入，本文件不进镜像。
//
// ★★ 模型已从 YOLO26-n depth 换成 Depth Anything V2 Small（int8）
//
//   为什么换（离线实测，脚本 D:\Projects\mode\yolo_work\diagD_dav2_vs_yolo.py）：
//     自然风景是 YOLO26-n 的短板。实测那张"富士山 + 樱花"：
//       画面【下方】的近景樱花树丛被判成【最远】，富士山与天空同层；
//       上下半均值差 = −0.120（方向反了）。
//     同一张图 DAV2 给出 +0.010（方向正确），且下方樱花是明确的近景。
//     8 张测试图上 DAV2 全部通过"下方比上方近"的常识性校验。
//   连带收益：DAV2 的深度边界比 YOLO26 清晰得多 —— 真人那张照片里两个人戴的
//     【纸箱头】在深度图上轮廓分明（而 modnet 分割完全不认识纸箱，导致头身
//     撕裂、只能手动涂刷补救）。这为将来"用深度补全 mask"留了路。
//
//   为什么用 int8 而不是 fp16（脚本 diagE_dav2_int8.py 实测）：
//     体积 99.1 MB → 27.1 MB；与 fp32 的相关系数 0.9960、Otsu 切点偏移均值
//     0.0078、6 张图的上下半方向全部一致 —— 精度几乎无损。
//     ⚠️ 与分割模型相反：本项目历史上有"深度模型 int8 会崩"的记录
//     （见 quant_seg.py 注释），所以 DAV2 的 int8 是【实测过】才敢用的。
//
// ★ DAV2 的输入/输出规格与 YOLO26 **完全不同**，照抄旧代码会静默出错：
//   输入  pixel_values     float32  [batch, 3, height, width]，**ImageNet 归一化**
//         尺寸必须是 14 的倍数（ViT patch = 14）
//   输出  predicted_depth  float32  [batch, H', W']  —— **三维**，不是四维
//         H' = 14*floor(height/14)、W' = 14*floor(width/14)
//   语义  输出是【相对视差】，越大越近 —— 与 shader 要的
//         "0 = 最远 / 1 = 最近"天然一致，**不需要 1/v 换算**（米制才需要）
//
//   预处理（对齐 DAV2 官方 get_resize + Resize(keep_aspect_ratio=True)）：
//     保持长宽比、使【总面积】对齐 size²，再把边长取整到 14 的倍数，
//     **不补边、不做 letterbox**。缩放仍交给 Skia 的 drawImageRect（GPU、质量好）。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'depth_inference.dart';

/// S-31 的 ONNX Runtime 实现。
class OnnxDepthInference implements DepthInference {
  OnnxDepthInference({this.assetKey = defaultAssetKey});

  /// 打包进 App 的模型：Depth Anything V2 Small（int8 动态量化，约 26 MB）。
  static const String defaultAssetKey = 'assets/models/dav2-small_int8.onnx';

  /// ViT patch 尺寸 —— 输入边长必须是它的整数倍，否则模型内部的
  /// `14*floor(h/14)` 会把我们喂进去的尺寸悄悄改掉，输出与预期对不上。
  static const int dav2Patch = 14;

  final String assetKey;

  static final OnnxDepthInference instance = OnnxDepthInference();

  OrtSession? _session;
  String _inputName = 'pixel_values';
  Future<OrtSession?>? _loading;
  bool _failed = false;

  @override
  Future<bool> isAvailable() async => await _ensureSession() != null;

  Future<OrtSession?> _ensureSession() {
    final OrtSession? s = _session;
    if (s != null) return Future<OrtSession?>.value(s);
    if (_failed) return Future<OrtSession?>.value(null);
    return _loading ??= _load();
  }

  Future<OrtSession?> _load() async {
    try {
      final OrtSession s =
          await OnnxRuntime().createSessionFromAsset(assetKey);
      _inputName =
          s.inputNames.isNotEmpty ? s.inputNames.first : 'pixel_values';
      _session = s;
      debugPrint('🟢 S-31 深度模型就绪: $assetKey '
          '(input=$_inputName outputs=${s.outputNames})');
      return s;
    } catch (e) {
      _failed = true;
      debugPrint('🔴 S-31 深度模型加载失败，将降级到预设景深模板: $e');
      return null;
    }
  }

  @override
  Future<DepthResult?> infer(
    Uint8List imageBytes, {
    int inputSize = 518,
  }) async {
    final OrtSession? session = await _ensureSession();
    if (session == null) return null;

    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      final (ui.Image resized, int nw, int nh) =
          await _resizeDav2(imageBytes, inputSize);
      final ByteData? bd =
          await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
      resized.dispose();
      if (bd == null) return null;

      final Uint8List rgba =
          bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      final Float32List nchw = _toNchwImagenet(rgba, nw, nh);

      input = await OrtValue.fromList(nchw, <int>[1, 3, nh, nw]);
      outputs = await session.run(<String, OrtValue>{_inputName: input});

      final OrtValue out = outputs.values.first;
      final List<dynamic> raw = await out.asFlattenedList();
      return _normalizeDisp(raw, nw, nh);
    } catch (e) {
      debugPrint('🔴 S-31 推理失败: $e');
      return null;
    } finally {
      await input?.dispose();
      if (outputs != null) {
        for (final OrtValue t in outputs.values) {
          await t.dispose();
        }
      }
    }
  }

  /// DAV2 预处理：保持长宽比 → 总面积对齐 [size]² → 边长取整到 14 的倍数。
  ///
  /// ★ 不补边、不做 letterbox。
  ///   DAV2 官方就是不补边的直接 resize；若照抄 YOLO26 那套"补 114 灰的
  ///   letterbox"，灰边会被当成真实像素送进 ViT，整圈边缘的深度都会失真
  ///   （而且不会报错，只会安静地给出错的深度图）。
  ///
  /// 返回 (图, 宽, 高) —— 宽高都已是 14 的倍数，因此模型的
  /// `14*floor(x/14)` 不会再改动它们。
  Future<(ui.Image, int, int)> _resizeDav2(Uint8List bytes, int size) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;
    try {
      final int w = src.width;
      final int h = src.height;
      if (w <= 0 || h <= 0) {
        throw StateError('图片尺寸非法: ${w}x$h');
      }

      // 保持长宽比、让【面积】等于 size²（DAV2 官方 keep_aspect_ratio 的做法）。
      final double scale = math.sqrt((size * size) / (w * h));
      final int nw = math.max(
        dav2Patch,
        (w * scale / dav2Patch).round() * dav2Patch,
      );
      final int nh = math.max(
        dav2Patch,
        (h * scale / dav2Patch).round() * dav2Patch,
      );

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Rect.fromLTWH(0, 0, nw.toDouble(), nh.toDouble()),
        // high（双三次）：DAV2 官方用 bicubic 上采样，这里与之对齐。
        Paint()..filterQuality = FilterQuality.high,
      );
      final ui.Picture picture = recorder.endRecording();
      try {
        final ui.Image out = await picture.toImage(nw, nh);
        return (out, nw, nh);
      } finally {
        picture.dispose();
      }
    } finally {
      src.dispose();
      codec.dispose();
    }
  }

  /// RGBA8888 → NCHW float32，按 **ImageNet** 均值/标准差归一化。
  ///
  /// ★ 与 YOLO26 的区别：那个只做 `/255`，不做减均值除方差。
  ///   顺序或参数写错不会报错，只会安静地给出一张近乎全平的深度图。
  static Float32List _toNchwImagenet(Uint8List rgba, int w, int h) {
    const List<double> mean = <double>[0.485, 0.456, 0.406];
    const List<double> std = <double>[0.229, 0.224, 0.225];
    final int area = w * h;
    final Float32List out = Float32List(3 * area);
    for (int i = 0; i < area; i++) {
      final int p = i * 4;
      for (int ch = 0; ch < 3; ch++) {
        out[ch * area + i] = (rgba[p + ch] / 255.0 - mean[ch]) / std[ch];
      }
    }
    return out;
  }

  /// DAV2 的相对视差 → [0,1] 归一化（**0 = 最远，1 = 最近**）。
  ///
  /// ★ 与旧实现的根本区别：**不再做 `1/米` 的换算**。
  ///   YOLO26 输出的是米制绝对深度（越大越远），必须取倒数才能对上 shader 的
  ///   方向；DAV2 输出的本来就是视差（越大越近），再取一次倒数会把方向弄反
  ///   —— 那正是"人物和背景的远近整个颠倒"的成因。
  ///
  /// 用百分位裁剪（2% ~ 98%）而不是 min/max：单点极值会把整幅图压平
  /// （历史上踩过"主体与背景区分不清"）。每 1/64 采样估分位，
  /// 避免对几十万像素排序。
  static DepthResult? _normalizeDisp(List<dynamic> raw, int w, int h) {
    final int n = w * h;
    if (raw.length < n) return null;

    final int stepX = math.max(1, w ~/ 64);
    final int stepY = math.max(1, h ~/ 64);
    final List<double> samples = <double>[];
    for (int y = 0; y < h; y += stepY) {
      final int rowBase = y * w;
      for (int x = 0; x < w; x += stepX) {
        final double v = (raw[rowBase + x] as num).toDouble();
        if (v.isFinite) samples.add(v);
      }
    }
    if (samples.isEmpty) return null;
    samples.sort();

    // lo = 远端的视差，hi = 近端的视差（视差越大越近）。
    final double lo = samples[(samples.length * 0.02).floor().clamp(
          0,
          samples.length - 1,
        )];
    final double hi = samples[(samples.length * 0.98).floor().clamp(
          0,
          samples.length - 1,
        )];
    final double span = math.max(hi - lo, 1e-9);

    final Float32List out = Float32List(n);
    for (int i = 0; i < n; i++) {
      final double v = (raw[i] as num).toDouble();
      out[i] = v.isFinite ? ((v - lo) / span).clamp(0.0, 1.0) : 0.0;
    }
    // 深度图尺寸 = DAV2 的输入尺寸，与原图**同宽高比**（不是同尺寸）——
    // shader 用 uv 采样，只要宽高比一致就不会错位。
    return DepthResult(
      width: w,
      height: h,
      data: out,
      minMeters: lo,
      maxMeters: hi,
      // DAV2 是相对视差，没有米制含义 —— 界面据此改用相对刻度，不再显示 "m"。
      isMetric: false,
    );
  }
}
