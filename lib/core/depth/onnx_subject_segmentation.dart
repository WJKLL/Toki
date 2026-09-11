// lib/core/depth/onnx_subject_segmentation.dart
// 编号：S-39 主体分割服务（ONNX Runtime 实现）
//
// ★ 本文件是**主项目独有**：依赖 flutter_onnxruntime（不支持 OpenHarmony）。
//   镜像侧经 SubjectSegmentationRegistry.register() 注入自己的实现；
//   未注册 → Registry.instance 为 null → 调用方降级回纯深度分层。
//
// ★ 两个模型、自动调度（实测数据见 PLAN_components_v1.53.md）
//   两个模型互补，**不可互替**：
//     · isnet-anime（1024 输入，int8 量化 42MB）
//         插画：前景占比 ~50%，整个人完整抠出 ✅
//         真人：只有 1.5%，几乎全丢 ❌
//     · modnet（512 输入，fp32 25MB）
//         真人：35.6%，三个人都抠出 ✅
//         插画：只有 6%，基本失效 ❌
//   调度：先跑 MODNet（512，快）——
//     前景占比 ≥ 10% → 判定真人照，直接用，**只推理一次**；
//     < 10%          → 疑似插画，再跑 isnet-anime。
//
// ★ 为什么不把 isnet 降到 512 提速
//   它的 ONNX 图里 decoder 的 skip 连接尺寸被烘焙成 1024（改成动态输入后
//   Concat 节点报 16 vs 32 维度不匹配），只能保持 1024。
//   速度改由"只跑一次 + 真人照不碰它"来控。
//
// ★ 预处理与实测脚本严格一致
//   letterbox 到 size×size、**补 0 黑边**（注意深度模型用 114 灰，是 ultralytics
//   的约定，两者不同）→ /255 → 归一化：
//     isnet-anime: (v − ImageNet均值) / ImageNet标准差
//     modnet:      (v − 0.5) / 0.5
//   顺序错会静默输出一张近乎全黑或全白的 mask。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'subject_segmentation.dart';

/// S-39 的 ONNX Runtime 实现。
class OnnxSubjectSegmentation implements SubjectSegmentation {
  OnnxSubjectSegmentation({
    this.animeAsset = defaultAnimeAsset,
    this.portraitAsset = defaultPortraitAsset,
  });

  /// 插画人像分割（int8 量化，42 MB）。
  static const String defaultAnimeAsset =
      'assets/models/isnet-anime_int8.onnx';

  /// 真人抠像（fp32，25 MB；实测 int8 会明显退化，故不量化）。
  static const String defaultPortraitAsset = 'assets/models/modnet.onnx';

  /// 输入尺寸（模型硬性要求，见文件头说明）。
  static const int animeSize = 1024;
  static const int portraitSize = 512;

  /// 判"真人照"的前景占比阈值：低于它认为 MODNet 没抓住人，转投 isnet。
  static const double portraitCoverageMin = 0.10;

  final String animeAsset;
  final String portraitAsset;

  static final OnnxSubjectSegmentation instance = OnnxSubjectSegmentation();

  // ── 会话（各自独立懒加载 + 失败标记）──
  OrtSession? _animeSession;
  OrtSession? _portraitSession;
  Future<OrtSession?>? _animeLoading;
  Future<OrtSession?>? _portraitLoading;
  bool _animeFailed = false;
  bool _portraitFailed = false;
  String _animeInput = 'img';
  String _portraitInput = 'input';

  @override
  Future<bool> isAvailable() async {
    final OrtSession? p = await _ensurePortrait();
    return p != null || await _ensureAnime() != null;
  }

  @override
  Future<SubjectMask?> segment(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) return null;

    // ① 先跑 MODNet（512，快）—— 真人走这条就结束，只推理一次。
    final SubjectMask? portrait = await _run(
      imageBytes,
      portraitSize,
      imagenet: false,
    );
    if (portrait != null && portrait.coverage >= portraitCoverageMin) {
      return portrait;
    }

    // ② 疑似插画 → 再跑 isnet-anime。
    final SubjectMask? anime = await _run(
      imageBytes,
      animeSize,
      imagenet: true,
    );
    if (anime != null) return anime;

    // ③ isnet 不可用/失败 → 用 MODNet 的结果兜底（哪怕是低覆盖，也比没有强）。
    return portrait;
  }

  // ── 会话加载 ────────────────────────────────────────────
  Future<OrtSession?> _ensureAnime() {
    final OrtSession? s = _animeSession;
    if (s != null) return Future<OrtSession?>.value(s);
    if (_animeFailed) return Future<OrtSession?>.value(null);
    return _animeLoading ??= _load(animeAsset, anime: true);
  }

  Future<OrtSession?> _ensurePortrait() {
    final OrtSession? s = _portraitSession;
    if (s != null) return Future<OrtSession?>.value(s);
    if (_portraitFailed) return Future<OrtSession?>.value(null);
    return _portraitLoading ??= _load(portraitAsset, anime: false);
  }

  Future<OrtSession?> _load(String asset, {required bool anime}) async {
    try {
      final OrtSession s = await OnnxRuntime().createSessionFromAsset(asset);
      final String inputName =
          s.inputNames.isNotEmpty ? s.inputNames.first : (anime ? 'img' : 'input');
      if (anime) {
        _animeSession = s;
        _animeInput = inputName;
      } else {
        _portraitSession = s;
        _portraitInput = inputName;
      }
      debugPrint('🟢 S-39 分割模型就绪: $asset (input=$inputName '
          'outputs=${s.outputNames.length})');
      return s;
    } catch (e) {
      if (anime) {
        _animeFailed = true;
      } else {
        _portraitFailed = true;
      }
      debugPrint('🔴 S-39 分割模型加载失败 $asset（将降级回纯深度分层）: $e');
      return null;
    }
  }

  // ── 单次推理 ────────────────────────────────────────────
  Future<SubjectMask?> _run(
    Uint8List imageBytes,
    int size, {
    required bool imagenet,
  }) async {
    final OrtSession? session =
        imagenet ? await _ensureAnime() : await _ensurePortrait();
    if (session == null) return null;

    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      final (ui.Image boxed, int vx, int vy, int vw, int vh) =
          await _letterbox(imageBytes, size);
      final ByteData? bd =
          await boxed.toByteData(format: ui.ImageByteFormat.rawRgba);
      boxed.dispose();
      if (bd == null) return null;

      final Uint8List rgba =
          bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      input = await OrtValue.fromList(
        _toNchw(rgba, size, imagenet: imagenet),
        <int>[1, 3, size, size],
      );
      final String inputName =
          imagenet ? _animeInput : _portraitInput;
      outputs = await session.run(<String, OrtValue>{inputName: input});
      final OrtValue out = outputs.values.first;
      final List<dynamic> raw = await out.asFlattenedList();
      return _toMask(raw, size, vx, vy, vw, vh);
    } catch (e) {
      debugPrint('🔴 S-39 分割推理失败(size=$size): $e');
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

  /// letterbox：保持宽高比缩放到 size×size，四周补 **0 黑边**（与实测脚本一致）。
  ///
  /// 返回 (图, 有效区 x / y / w / h)。有效区必须传出去：手机竖图的 padding
  /// 占比可达 40%~45%，若把 pad 也纳入 mask 的 min-max 统计，前景概率会被压扁。
  Future<(ui.Image, int, int, int, int)> _letterbox(
    Uint8List bytes,
    int size,
  ) async {
    final ui.Image src = await decodeImageFromList(bytes);
    final int w = src.width;
    final int h = src.height;
    final double s = math.min(size / w, size / h);
    final int nw = math.max(1, (w * s).round());
    final int nh = math.max(1, (h * s).round());
    final int vx = (size - nw) ~/ 2;
    final int vy = (size - nh) ~/ 2;

    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
    c.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(
        vx.toDouble(),
        vy.toDouble(),
        nw.toDouble(),
        nh.toDouble(),
      ),
      // high（双三次）：medium 在"缩小"时会走 mipmap，细节先丢一半。
      Paint()..filterQuality = FilterQuality.high,
    );
    src.dispose();
    final ui.Picture pic = rec.endRecording();
    final ui.Image out = await pic.toImage(size, size);
    pic.dispose();
    return (out, vx, vy, nw, nh);
  }

  /// RGBA → NCHW float32，按模型要求归一化。
  static Float32List _toNchw(
    Uint8List rgba,
    int size, {
    required bool imagenet,
  }) {
    const List<double> mean = <double>[0.485, 0.456, 0.406];
    const List<double> std = <double>[0.229, 0.224, 0.225];
    final int area = size * size;
    final Float32List out = Float32List(3 * area);
    for (int i = 0; i < area; i++) {
      final int p = i * 4;
      for (int ch = 0; ch < 3; ch++) {
        final double v = rgba[p + ch] / 255.0;
        out[ch * area + i] =
            imagenet ? (v - mean[ch]) / std[ch] : (v - 0.5) / 0.5;
      }
    }
    return out;
  }

  /// 全图 min-max 归一化 → 裁掉 letterbox → 得到与原图同宽高比的 soft mask。
  ///
  /// 两个模型的输出值域都未定义（实测 isnet 的 raw 范围就是 0~1 但无保证），
  /// 统一做 min-max 与实测脚本保持一致。
  static SubjectMask? _toMask(
    List<dynamic> raw,
    int size,
    int vx,
    int vy,
    int vw,
    int vh,
  ) {
    final int n = size * size;
    if (raw.length < n || vw <= 0 || vh <= 0) return null;

    double lo = double.infinity;
    double hi = -double.infinity;
    for (int i = 0; i < n; i++) {
      final double v = (raw[i] as num).toDouble();
      if (!v.isFinite) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (!(hi > lo)) return null;
    final double span = hi - lo;

    final Float32List out = Float32List(vw * vh);
    for (int y = 0; y < vh; y++) {
      final int srcBase = (vy + y) * size + vx;
      final int dstBase = y * vw;
      for (int x = 0; x < vw; x++) {
        final double v = (raw[srcBase + x] as num).toDouble();
        out[dstBase + x] =
            v.isFinite ? ((v - lo) / span).clamp(0.0, 1.0) : 0.0;
      }
    }
    return SubjectMask(width: vw, height: vh, data: out);
  }
}
