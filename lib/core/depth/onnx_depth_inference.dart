// lib/core/depth/onnx_depth_inference.dart
// 编号：S-31 深度推理服务（ONNX Runtime 实现）
//
// ★ 本文件是**主项目独有**：依赖 flutter_onnxruntime，而该包不支持 OpenHarmony
//   （实测其平台声明只有 android/ios/macos/windows/linux/web）。
//   鸿蒙侧需另写实现（@ohos/onnxruntime + MethodChannel 插件），
//   经 DepthInferenceRegistry.register() 注入，本文件不进镜像。
//
// 模型（实测规格，见 PLAN_wallpaper_v1.52.md §6.6）：
//   输入  ['batch', 3, 'height', 'width']  float32，归一化到 [0,1]
//   输出  ['batch', 1, 'height', 'width']  float32，**米制绝对深度**
//   已验证输入边长 384 / 512 / 640 / 768 全部可跑（dynamic shape 导出）
//
// 预处理必须与训练严格一致：letterbox（保持宽高比 + 114 灰填充）→ /255 → NCHW。
// 这里刻意用 Skia 的 drawImageRect 做 letterbox，而不是手写双线性 ——
// 让 GPU 做缩放，质量更好且更快。
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

  /// 打包进 App 的模型（FP16 dynamic，约 10 MB）。
  static const String defaultAssetKey =
      'assets/models/yolo26n-depth_fp16.onnx';

  final String assetKey;

  static final OnnxDepthInference instance = OnnxDepthInference();

  OrtSession? _session;
  String _inputName = 'images';
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
      _inputName = s.inputNames.isNotEmpty ? s.inputNames.first : 'images';
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
    int inputSize = 640,
  }) async {
    final OrtSession? session = await _ensureSession();
    if (session == null) return null;

    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      final (ui.Image letterboxed, int vx, int vy, int vw, int vh) =
          await _letterbox(imageBytes, inputSize);
      final ByteData? bd =
          await letterboxed.toByteData(format: ui.ImageByteFormat.rawRgba);
      letterboxed.dispose();
      if (bd == null) return null;

      final Uint8List rgba =
          bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      final Float32List nchw = _toNchw(rgba, inputSize);

      input = await OrtValue.fromList(
        nchw,
        <int>[1, 3, inputSize, inputSize],
      );
      outputs = await session.run(<String, OrtValue>{_inputName: input});

      final OrtValue out = outputs.values.first;
      final List<dynamic> raw = await out.asFlattenedList();
      return _normalize(raw, inputSize, inputSize, vx, vy, vw, vh);
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

  /// letterbox：保持宽高比缩放到 size×size，四周补 114 灰。
  /// 与 ultralytics 的 LetterBox 默认行为一致。
  ///
  /// 返回 (图, 有效区 x / y / w / h) —— **有效区必须传出去**：手机竖图的
  /// padding 面积可达 40%~45%，若把 pad 也纳入归一化的分位数统计，
  /// 真实内容的深度会被压进极窄区间（详见 _normalize 注释）。
  Future<(ui.Image, int, int, int, int)> _letterbox(
    Uint8List bytes,
    int size,
  ) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;
    try {
      final int w = src.width;
      final int h = src.height;
      if (w <= 0 || h <= 0) {
        throw StateError('图片尺寸非法: ${w}x$h');
      }
      final double r = math.min(size / w, size / h);
      final int nw = math.max(1, (w * r).round());
      final int nh = math.max(1, (h * r).round());
      final int left = (size - nw) ~/ 2;
      final int top = (size - nh) ~/ 2;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..color = const Color(0xFF727272), // 114 灰
      );
      canvas.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Rect.fromLTWH(
          left.toDouble(),
          top.toDouble(),
          nw.toDouble(),
          nh.toDouble(),
        ),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final ui.Picture picture = recorder.endRecording();
      try {
        final ui.Image out = await picture.toImage(size, size);
        return (out, left, top, nw, nh);
      } finally {
        picture.dispose();
      }
    } finally {
      src.dispose();
      codec.dispose();
    }
  }

  /// RGBA8888 → NCHW float32，除以 255 归一化到 [0,1]。
  static Float32List _toNchw(Uint8List rgba, int size) {
    final int area = size * size;
    final Float32List out = Float32List(3 * area);
    const double inv = 1.0 / 255.0;
    for (int i = 0; i < area; i++) {
      final int p = i * 4;
      out[i] = rgba[p] * inv;
      out[area + i] = rgba[p + 1] * inv;
      out[2 * area + i] = rgba[p + 2] * inv;
    }
    return out;
  }

  /// 米制深度 → [0,1] 归一化。
  ///
  /// 用**百分位裁剪**（2% ~ 98%）而不是固定范围：不同照片的绝对深度跨度差异很大
  /// （实测 small 版理论值域可达 0.1~825 m），固定范围会让大多数图挤在很窄的
  /// 一段里、失去层次。采样 4096 个点估分位，避免对 40 万像素排序。
  static DepthResult? _normalize(
    List<dynamic> raw,
    int w,
    int h,
    int vx,
    int vy,
    int vw,
    int vh,
  ) {
    final int n = w * h;
    if (raw.length < n) return null;

    // ★ 只用 letterbox **有效区域内**的像素统计分位数。
    //   padding 区域的深度值是模型对 114 灰填充的预测，毫无意义；而手机竖图
    //   的 padding 面积可达 40%~45%，一旦参与统计就会把 2%/98% 分位数整个带偏，
    //   把真实内容的深度压进极窄区间 —— 表现为"主体与背景区分不清"。
    final int stepX = math.max(1, vw ~/ 64);
    final int stepY = math.max(1, vh ~/ 64);
    final List<double> samples = <double>[];
    for (int y = vy; y < vy + vh; y += stepY) {
      final int rowBase = y * w;
      for (int x = vx; x < vx + vw; x += stepX) {
        final double v = (raw[rowBase + x] as num).toDouble();
        if (v.isFinite && v > 0) samples.add(v);
      }
    }
    if (samples.isEmpty) return null;
    samples.sort();

    final double lo = samples[(samples.length * 0.02).floor().clamp(
          0,
          samples.length - 1,
        )];
    final double hi = samples[(samples.length * 0.98).floor().clamp(
          0,
          samples.length - 1,
        )];
    final double span = math.max(hi - lo, 1e-6);

    // ★ 只输出【有效区域】，并翻转深度方向：
    //   1) 裁掉 padding —— 深度图必须与原图**同宽高比**。否则 shader 用同一套 uv
    //      采样 uTexture（原图，1440×2626）与 uDepth（含 pad 的 640×640 方图）会
    //      **整体错位**：深度图里人物的位置其实对应到了原图的其他位置。实测表现
    //      正是用户报告的"人物背后的背景无法与人物区分"。
    //   2) 翻转深度方向 —— 模型输出"米数越大 = 越远"，而 shader 的约定是
    //      0 = 最远、1 = 最近。不翻转则天空（远）被当成最近、人物（近）被当成最远。
    final Float32List out = Float32List(vw * vh);
    for (int y = 0; y < vh; y++) {
      final int srcBase = (vy + y) * w + vx;
      final int dstBase = y * vw;
      for (int x = 0; x < vw; x++) {
        final double v = (raw[srcBase + x] as num).toDouble();
        final double n = v.isFinite ? ((v - lo) / span).clamp(0.0, 1.0) : 0.0;
        out[dstBase + x] = 1.0 - n;
      }
    }
    return DepthResult(
      width: vw,
      height: vh,
      data: out,
      minMeters: lo,
      maxMeters: hi,
    );
  }
}
