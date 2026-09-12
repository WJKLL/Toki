// lib/core/depth/onnx_subject_segmentation.dart
// 编号：S-39 主体分割服务（ONNX Runtime 实现）
//
// ★ 本文件是**主项目独有**：依赖 flutter_onnxruntime（不支持 OpenHarmony）。
//   镜像侧经 SubjectSegmentationRegistry.register() 注入自己的实现；
//   未注册 → Registry.instance 为 null → 调用方降级回纯深度分层。
//
// ★ 两个模型、自动调度（实测数据见 PLAN_components_v1.53.md 与 diagB）
//   两个模型互补，**不可互替**：
//     · isnet-anime（1024 输入，int8 量化 42MB）
//         插画：前景占比 ~50%，整个人完整抠出 ✅
//         真人：只有 1.5%，几乎全丢 ❌
//     · modnet（512 输入，fp32 25MB）
//         真人：35.6%，三个人都抠出 ✅
//         插画：6% 起 —— 但**覆盖率高 ≠ 抠得准**：实测它会把地面一起抠进来
//   调度（本轮修正）：**两个都跑**，再用 isnet 的覆盖率仲裁 ——
//     isnet ≥ 8% → 用 isnet（输入 1024，是 modnet 的两倍分辨率）；
//     否则        → 退回 modnet（真人照）。
//   ★ 不能用 modnet 的覆盖率当"还要不要跑 isnet"的判据：它多抠背景时覆盖率
//     会【虚高】，反而骗过分流、跳过真正该用的 isnet。见 animeCoverageMin。
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

  /// ★ 仲裁阈值：isnet 认得出主体（覆盖率 ≥ 此值）就用它，否则退回 modnet。
  ///
  /// 【本轮根因修复】旧实现用 `portraitCoverageMin = 0.10` 判"真人照"，只看
  /// modnet 的覆盖率 —— 这个判据是错的，实测 5 张图（诊断脚本
  /// `D:\Projects\mode\yolo_work\diagB_two_models.py`，对比图在 seg_out/diagB）：
  ///
  ///   图          modnet cov   isnet cov   应该用    旧逻辑选了
  ///   二次元 1       6.02%      49.93%     isnet     isnet  ✅
  ///   二次元 2      35.41%      24.08%     isnet     modnet ❌
  ///   真人照        35.60%       1.54%     modnet    modnet ✅
  ///   风景 1/2       0%/0.2%    0%/0.02%   无主体     —      —
  ///
  /// ★ 旧判据为什么会被"骗"
  ///   modnet 在二次元图上会把**地面**一起抠进主体 —— 那张樱花街道图的实测
  ///   主体 mask 的 bbox 从画面左边缘 x=0 开始，左下方整片人行道都是前景。
  ///   覆盖率因此【虚高】到 35.41%，反而超过了 10% 的门槛，被判成"真人照"、
  ///   直接返回、**跳过了真正该用的 isnet**。
  ///   即：模型的错误让它自己骗过了以覆盖率为唯一判据的分流。
  ///
  /// ★ 为什么不能靠后处理补救
  ///   那块地面与人物在 mask 里是【连通】的，任何连通域筛选（含
  ///   `_keepMainComponents`）都剔不掉它 —— 只能靠选对模型。
  ///
  /// ★ 新判据只用 isnet
  ///   isnet 输入 1024、是 modnet 512 的两倍分辨率，认得出主体时边缘也细一倍。
  ///   只有它认不出（真人照仅 1.54%）才退回 modnet 兜底。
  ///
  /// ★ 代价
  ///   每张图都要跑 isnet（1024，比 modnet 慢）。真人照从"只推理一次"变成两次，
  ///   换来的是"不会再选错模型" —— 这笔交易划算。
  static const double animeCoverageMin = 0.08;

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

    // ① MODNet（512，快）：真人照的主力，同时兼作兜底。
    final SubjectMask? portrait = await _run(
      imageBytes,
      portraitSize,
      imagenet: false,
    );

    // ② isnet-anime（1024）：**必须跑** —— 不能靠 modnet 的覆盖率去猜。
    //    旧实现在 modnet 覆盖率高时直接 return，漏掉的正是这一步：二次元图
    //    被 modnet 多抠进地面、覆盖率虚高，于是选错了模型（实测表见
    //    animeCoverageMin 的注释）。
    final SubjectMask? anime = await _run(
      imageBytes,
      animeSize,
      imagenet: true,
    );

    // ③ 仲裁：isnet 认出了主体就用它（分辨率是 modnet 的两倍，边缘更细，
    //    插画上更准）；它认不出（真人照仅 1.54%）才退回 modnet。
    if (anime != null && anime.coverage >= animeCoverageMin) return anime;
    if (portrait != null && portrait.coverage > 0) return portrait;
    return anime ?? portrait;
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
