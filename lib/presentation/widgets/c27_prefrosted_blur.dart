// lib/presentation/widgets/c27_prefrosted_blur.dart
// 编号：C-27 预模糊组件（v1.17.1，P0：Impeller 毛玻璃性能优化）
// 职责：MiuixTextureBlur 的视觉等价实现 + **预模糊缓存** —— 快照/采样区/
//   模糊半径未变时复用一次性生成的模糊纹理，每帧仅 drawImageRect，
//   免去每帧 ImageFilter.blur（Impeller 下高斯模糊离屏 pass 昂贵，
//   flutter/flutter#191207）。模糊频率从「每帧」降为「快照更新时」
//   （配合 CaptureHeartbeat 3 帧/次采样节流）。
// 与 MiuixTextureBlur 差异：
//   1. blurRadius→sigma 0.45、tileMode clamp、颜色控制（buildBlurColorFilter
//      + blendColors 色块）逐项保持一致（视觉等价）；
//   2. 采样区（含 3σ margin）先一次性模糊成纹理缓存，每帧直接绘制。
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/blur_degrade_provider.dart';

/// 预模糊组件：对 [backdrop] 提供的背景做一次模糊缓存后按区域绘制。
/// 参数与 [MiuixTextureBlur] 同构（可无缝替换）。
/// P3（v1.17.1）：快速滚动降级 —— 模糊半径 ×0.3（极限滚动保帧）。
class C27PrefrostedBlur extends ConsumerWidget {
  const C27PrefrostedBlur({
    super.key,
    required this.backdrop,
    this.shape,
    this.blurRadius = MiuixBlurDefaults.blurRadius,
    this.colors = const BlurColors(),
    this.enabled = true,
    this.child,
  });

  final MiuixBackdrop backdrop;
  final ShapeBorder? shape;
  final double blurRadius;
  final BlurColors colors;
  final bool enabled;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget child = this.child ?? const SizedBox.expand();
    // P3：快速滚动降级 → 模糊半径 ×0.3（视觉仍保留毛玻璃，开销大降）。
    final bool degraded = ref.watch(fastScrollDegradeProvider);
    final double effectiveBlur = degraded ? blurRadius * 0.3 : blurRadius;
    if (!enabled) return _maybeClip(child);
    return _maybeClip(
      _PrefrostedRenderWidget(
        backdrop: backdrop,
        blurRadius: effectiveBlur,
        colors: colors,
        child: child,
      ),
    );
  }

  Widget _maybeClip(Widget inner) {
    if (shape == null) return inner;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape!),
      child: inner,
    );
  }
}

class _PrefrostedRenderWidget extends SingleChildRenderObjectWidget {
  const _PrefrostedRenderWidget({
    required this.backdrop,
    required this.blurRadius,
    required this.colors,
    required Widget super.child,
  });

  final MiuixBackdrop backdrop;
  final double blurRadius;
  final BlurColors colors;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPrefrostedBlur(
      backdrop: backdrop,
      blurRadius: blurRadius,
      colors: colors,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPrefrostedBlur)
      ..backdrop = backdrop
      ..blurRadius = blurRadius
      ..colors = colors;
  }
}

class _RenderPrefrostedBlur extends RenderProxyBox {
  _RenderPrefrostedBlur({
    required this._backdrop,
    required this._blurRadius,
    required this._colors,
  }) {
    _backdrop.addListener(markNeedsPaint);
  }

  MiuixBackdrop _backdrop;
  MiuixBackdrop get backdrop => _backdrop;
  set backdrop(MiuixBackdrop value) {
    if (identical(_backdrop, value)) return;
    _backdrop.removeListener(markNeedsPaint);
    _backdrop = value..addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _blurRadius;
  set blurRadius(double v) {
    if (_blurRadius == v) return;
    _blurRadius = v;
    markNeedsPaint();
  }

  BlurColors _colors;
  set colors(BlurColors v) {
    if (_colors == v) return;
    _colors = v;
    markNeedsPaint();
  }

  // ── P0 预模糊缓存 ──
  ui.Image? _cache; // 模糊纹理
  ui.Image? _cacheSource; // 生成时的源快照
  Rect? _cacheSrc; // 生成时的采样区
  double _cacheRadius = -1;

  @override
  void detach() {
    _backdrop.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _backdrop.addListener(markNeedsPaint);
  }

  @override
  void dispose() {
    _backdrop.removeListener(markNeedsPaint);
    _disposeCache();
    super.dispose();
  }

  void _disposeCache() {
    _cache?.dispose();
    _cache = null;
    _cacheSource = null;
    _cacheSrc = null;
    _cacheRadius = -1;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final ui.Image? image = _backdrop.snapshot;
    final Offset? backdropGlobal = _backdrop.globalOffset;
    if (image == null || backdropGlobal == null || size.isEmpty) {
      // 背景未就绪：只画子内容。
      super.paint(context, offset);
      return;
    }

    // v1.17.3：像素映射统一用快照录制 dpr（backdrop.pixelRatio，可能已降采样），
    //   保证与 C-28 降采样快照坐标一致（组件自身 dpr 不再假设等于快照 dpr）。
    final double dpr = _backdrop.pixelRatio;
    // 本区域左上角在快照像素坐标中的偏移。
    final Offset selfGlobal = localToGlobal(Offset.zero);
    final double offX = (selfGlobal.dx - backdropGlobal.dx) * dpr;
    final double offY = (selfGlobal.dy - backdropGlobal.dy) * dpr;

    final double radius = _blurRadius.clamp(
      0.0,
      MiuixBlurDefaults.maxBlurRadius,
    );
    final double sigma = radius * MiuixBlurDefaults.blurRadiusToSigma;

    // 采样背景快照时向外扩一圈（约 3σ），让模糊边缘有真实邻域内容。
    final double marginLogical = sigma <= 0
        ? 0.0
        : (sigma * 3.0).ceilToDouble();
    final double mPx = marginLogical * dpr;
    final double wPx = size.width * dpr;
    final double hPx = size.height * dpr;
    final double imgW = image.width.toDouble();
    final double imgH = image.height.toDouble();
    final double srcL = (offX - mPx).clamp(0.0, imgW);
    final double srcT = (offY - mPx).clamp(0.0, imgH);
    final double srcR = (offX + wPx + mPx).clamp(0.0, imgW);
    final double srcB = (offY + hPx + mPx).clamp(0.0, imgH);
    if (srcR <= srcL || srcB <= srcT) {
      super.paint(context, offset);
      return;
    }
    final Rect src = Rect.fromLTRB(srcL, srcT, srcR, srcB);
    // 目标区按同一像素→逻辑映射（1:1 不拉伸）。
    final Rect dst = Rect.fromLTRB(
      offset.dx + (srcL - offX) / dpr,
      offset.dy + (srcT - offY) / dpr,
      offset.dx + (srcR - offX) / dpr,
      offset.dy + (srcB - offY) / dpr,
    );

    // ── P0：缓存未命中才重新生成模糊纹理 ──
    ui.Image? blurred = _cache;
    if (blurred == null ||
        !identical(_cacheSource, image) ||
        _cacheSrc != src ||
        _cacheRadius != radius) {
      blurred = _buildBlurred(image, src, sigma);
      _cache?.dispose();
      _cache = blurred;
      _cacheSource = image;
      _cacheSrc = src;
      _cacheRadius = radius;
    }

    final Canvas canvas = context.canvas;
    final ColorFilter? colorFilter = buildBlurColorFilter(_colors);
    final Rect selfRect = offset & size;

    // 关键：把绘制裁进自身边界（模糊光晕只参与采样、不画到组件外）。
    canvas.save();
    canvas.clipRect(selfRect);

    if (colorFilter != null) {
      canvas.saveLayer(selfRect, Paint()..colorFilter = colorFilter);
    }

    // 每帧仅绘制缓存纹理（无 ImageFilter.blur）。
    final Paint drawPaint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      blurred,
      Rect.fromLTWH(0, 0, blurred.width.toDouble(), blurred.height.toDouble()),
      dst,
      drawPaint,
    );

    // blend 颜色层（与 MiuixTextureBlur 一致）。
    for (final BlendColorEntry entry in _colors.blendColors) {
      final BlendMode? bm = miuixStandardBlendMode(entry.mode);
      if (bm == null) continue; // 扩展模式暂跳过（需 shader）
      canvas.drawRect(
        selfRect,
        Paint()
          ..color = entry.color
          ..blendMode = bm,
      );
    }

    if (colorFilter != null) canvas.restore();
    canvas.restore(); // clipRect

    // 子内容画在模糊之上。
    super.paint(context, offset);
  }

  /// 从快照采样区一次性生成模糊纹理（离屏高斯，仅在缓存未命中时执行）。
  ui.Image _buildBlurred(ui.Image image, Rect src, double sigma) {
    final int w = src.width.round();
    final int h = src.height.round();
    if (w <= 0 || h <= 0) {
      // 空兜底：1×1 透明图（dart:ui Image 无公开构造，走空画布录制）。
      final ui.PictureRecorder empty = ui.PictureRecorder();
      Canvas(empty);
      return empty.endRecording().toImageSync(1, 1);
    }
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Paint paint = Paint()..filterQuality = FilterQuality.medium;
    if (sigma > 0) {
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      );
    }
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      paint,
    );
    return recorder.endRecording().toImageSync(w, h);
  }
}
