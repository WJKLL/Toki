// lib/kernel/blur.dart
// 自研模糊组件：等价 MiuixTextureBlur，但像素映射用 backdrop.pixelRatio
// （支持降采样快照），采样偏移 = (组件全局 - 快照全局) × 快照 dpr。
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

class BackdropBlur extends StatelessWidget {
  const BackdropBlur({
    super.key,
    required this.backdrop,
    this.shape,
    this.blurRadius = MiuixBlurDefaults.blurRadius,
    this.colors = const BlurColors(),
    required this.child,
  });

  final MiuixLayerBackdrop backdrop;
  final ShapeBorder? shape;
  final double blurRadius;
  final BlurColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 对齐官方 MiuixTextureBlur（miuix_texture_blur.dart:57-60）：
    // 模糊绘制层必须按 shape 圆角裁剪，否则圆角外会露出直角的模糊页面背景
    // （demo 之前只 clipRect 直角矩形，Transform.scale 放大时尤其明显）。
    final Widget inner = _BackdropBlurRenderWidget(
      backdrop: backdrop,
      blurRadius: blurRadius,
      colors: colors,
      child: child,
    );
    if (shape == null) return inner;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape!),
      child: inner,
    );
  }
}

class _BackdropBlurRenderWidget extends SingleChildRenderObjectWidget {
  const _BackdropBlurRenderWidget({
    required this.backdrop,
    required this.blurRadius,
    required this.colors,
    required super.child,
  });

  final MiuixLayerBackdrop backdrop;
  final double blurRadius;
  final BlurColors colors;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderBackdropBlur(
      backdrop: backdrop,
      blurRadius: blurRadius,
      colors: colors,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBackdropBlur)
      ..backdrop = backdrop
      ..blurRadius = blurRadius
      ..colors = colors;
  }
}

class _RenderBackdropBlur extends RenderProxyBox {
  _RenderBackdropBlur({
    required this._backdrop,
    required this._blurRadius,
    required this._colors,
  }) {
    _backdrop.addListener(markNeedsPaint);
  }

  MiuixLayerBackdrop _backdrop;
  set backdrop(MiuixLayerBackdrop value) {
    if (identical(_backdrop, value)) return;
    _backdrop.removeListener(markNeedsPaint);
    _backdrop = value..addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _blurRadius;
  set blurRadius(double value) {
    if (_blurRadius == value) return;
    _blurRadius = value;
    markNeedsPaint();
  }

  BlurColors _colors;
  set colors(BlurColors value) {
    if (_colors == value) return;
    _colors = value;
    markNeedsPaint();
  }

  // ── P0 预模糊缓存（v1.18.x，对齐 C-27）：快照/采样区/半径未变时复用
  //    一次性生成的模糊纹理，每帧仅 drawImageRect —— 根治切页/按压动画中
  //    每帧重做高斯（底栏 blur 16dp sigma≈7.2 时离屏 pass 昂贵导致抖动）。
  ui.Image? _cache; // 模糊纹理
  ui.Image? _cacheSource; // 生成时的源快照
  Rect? _cacheSrc; // 生成时的采样区
  double _cacheRadius = -1;

  @override
  void detach() {
    _backdrop.removeListener(markNeedsPaint);
    _disposeCache();
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
      super.paint(context, offset);
      return;
    }

    // 关键：用快照 dpr（可能已降采样），而非组件 dpr。
    final double dpr = _backdrop.pixelRatio;
    final Offset selfGlobal = localToGlobal(Offset.zero);
    final double offX = (selfGlobal.dx - backdropGlobal.dx) * dpr;
    final double offY = (selfGlobal.dy - backdropGlobal.dy) * dpr;

    final double radius = _blurRadius.clamp(
      0.0,
      MiuixBlurDefaults.maxBlurRadius,
    );
    final double sigma = radius * MiuixBlurDefaults.blurRadiusToSigma;
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
    final Rect dst = Rect.fromLTRB(
      offset.dx + (srcL - offX) / dpr,
      offset.dy + (srcT - offY) / dpr,
      offset.dx + (srcR - offX) / dpr,
      offset.dy + (srcB - offY) / dpr,
    );

    final Canvas canvas = context.canvas;
    final ColorFilter? colorFilter = buildBlurColorFilter(_colors);
    final Rect selfRect = offset & size;

    canvas.save();
    canvas.clipRect(selfRect);
    if (colorFilter != null) {
      canvas.saveLayer(selfRect, Paint()..colorFilter = colorFilter);
    }

    // ── P0：缓存未命中才重新生成模糊纹理（快照变化/区域移动/半径变化）──
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
    // 每帧仅绘制缓存纹理（无 ImageFilter.blur）。
    final Paint drawPaint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      blurred,
      Rect.fromLTWH(0, 0, blurred.width.toDouble(), blurred.height.toDouble()),
      dst,
      drawPaint,
    );
    for (final BlendColorEntry entry in _colors.blendColors) {
      final BlendMode? bm = miuixStandardBlendMode(entry.mode);
      if (bm == null) continue;
      canvas.drawRect(
        selfRect,
        Paint()
          ..color = entry.color
          ..blendMode = bm,
      );
    }
    if (colorFilter != null) canvas.restore();
    canvas.restore();

    super.paint(context, offset);
  }

  /// 从快照采样区一次性生成模糊纹理（离屏高斯，仅在缓存未命中时执行）。
  ui.Image _buildBlurred(ui.Image image, Rect src, double sigma) {
    final int w = src.width.round();
    final int h = src.height.round();
    if (w <= 0 || h <= 0) {
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
