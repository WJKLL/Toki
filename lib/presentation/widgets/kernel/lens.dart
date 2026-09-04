// lib/kernel/lens.dart
// lens 边缘折射组件：用 FragmentShader 渲染背景快照的"边缘折射 + 彩虹 + 流动"。
//
// 几何重构（关键）：组件【不套 Transform.scale】——指示框布局尺寸即放大后
// W'×H'（调用方算好 Positioned left'/top' 与 SizedBox W'×H'），因此
// FlutterFragCoord 与 localToGlobal 始终同坐标系，映射不错位；
// shader 内把屏幕坐标逆缩放(uScale)回基础 stadium 做 SDF，支持 sx≠sy 非均匀形变。
//
// combined（对齐参考项目 rememberCombinedBackdrop）：可选 [overlayBackdrop]
// （底栏标签玻璃层 tabsBackdrop，dpr 未降采样）叠加在 [backdrop]（页面，降采样）
// 之上：标签非透明处【覆盖】页面 → 透过玻璃看到底栏图标且不双层。
//
// 采样 MiuixLayerBackdrop.snapshot（快照 dpr 可能降采样），
// 采样映射公式：snapPx = local × (snapDpr/deviceDpr) + (组件全局-快照全局)×snapDpr。
import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 透镜边缘折射组件：在 [child] 下层渲染折射背景。
class LensRefraction extends StatefulWidget {
  const LensRefraction({
    super.key,
    required this.backdrop,
    this.overlayBackdrop,
    required this.baseRadius,
    this.scaleX = 1,
    this.scaleY = 1,
    this.midRefraction = 0,
    this.edgeRefraction = -10,
    this.edgeWidth = 6,
    this.chromaticAberration = 0,
    this.flowAmount = 0,
    this.flowDir = 1,
    this.depthEffect = false,
    required this.child,
  });

  final MiuixLayerBackdrop backdrop;

  /// 可选叠加层（底栏标签玻璃层 tabsBackdrop），非透明处覆盖页面。
  final MiuixLayerBackdrop? overlayBackdrop;

  /// 基础圆角半径（未放大 stadium 的半径，dp；指示器 56 高 → 28）。
  final double baseRadius;

  /// 形变系数（sx, sy）：按压 78/56 放大 + velocity 形变，支持非均匀。
  final double scaleX;
  final double scaleY;

  /// 中间极轻折射量（dp，负=向内 → 轻微放大；0=完全直通）。
  final double midRefraction;

  /// 边缘带折射量（dp，负=向内）。
  final double edgeRefraction;

  /// 边缘带宽（dp）。
  final double edgeWidth;

  /// 彩虹强度（0=关闭）。
  final double chromaticAberration;

  /// 沿边缘流动幅度（dp）。
  final double flowAmount;

  /// 流动方向：+1 = 指示框右移（逆时针），-1 = 左移（顺时针）。
  final double flowDir;

  final bool depthEffect;
  final Widget child;

  @override
  State<LensRefraction> createState() => _LensRefractionState();
}

class _LensRefractionState extends State<LensRefraction> {
  static ui.FragmentProgram? _program;
  static bool _loading = false;

  void _ensureLoaded() {
    if (_program != null || _loading) return;
    _loading = true;
    unawaited(
      ui.FragmentProgram.fromAsset('shaders/lens_refraction.frag')
          .then((p) {
            _program = p;
            _loading = false;
            if (mounted) setState(() {});
          })
          .catchError((Object e) {
            _loading = false;
            debugPrint('🔴 lens shader load error: $e');
          }),
    );
  }

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentProgram? program = _program;
    if (program == null) {
      // 着色器未就绪：只画 child（无折射）。
      return widget.child;
    }
    return _LensRenderWidget(
      backdrop: widget.backdrop,
      overlayBackdrop: widget.overlayBackdrop,
      program: program,
      baseRadius: widget.baseRadius,
      scaleX: widget.scaleX,
      scaleY: widget.scaleY,
      midRefraction: widget.midRefraction,
      edgeRefraction: widget.edgeRefraction,
      edgeWidth: widget.edgeWidth,
      chromaticAberration: widget.chromaticAberration,
      flowAmount: widget.flowAmount,
      flowDir: widget.flowDir,
      depthEffect: widget.depthEffect ? 1.0 : 0.0,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: widget.child,
    );
  }
}

class _LensRenderWidget extends SingleChildRenderObjectWidget {
  const _LensRenderWidget({
    required this.backdrop,
    required this.overlayBackdrop,
    required this.program,
    required this.baseRadius,
    required this.scaleX,
    required this.scaleY,
    required this.midRefraction,
    required this.edgeRefraction,
    required this.edgeWidth,
    required this.chromaticAberration,
    required this.flowAmount,
    required this.flowDir,
    required this.depthEffect,
    required this.devicePixelRatio,
    required super.child,
  });

  final MiuixLayerBackdrop backdrop;
  final MiuixLayerBackdrop? overlayBackdrop;
  final ui.FragmentProgram program;
  final double baseRadius;
  final double scaleX;
  final double scaleY;
  final double midRefraction;
  final double edgeRefraction;
  final double edgeWidth;
  final double chromaticAberration;
  final double flowAmount;
  final double flowDir;
  final double depthEffect;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLens(
    backdrop: backdrop,
    overlayBackdrop: overlayBackdrop,
    shader: program.fragmentShader(),
    baseRadius: baseRadius,
    scaleX: scaleX,
    scaleY: scaleY,
    midRefraction: midRefraction,
    edgeRefraction: edgeRefraction,
    edgeWidth: edgeWidth,
    chromaticAberration: chromaticAberration,
    flowAmount: flowAmount,
    flowDir: flowDir,
    depthEffect: depthEffect,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLens)
      ..backdrop = backdrop
      ..overlayBackdrop = overlayBackdrop
      ..baseRadius = baseRadius
      ..scaleX = scaleX
      ..scaleY = scaleY
      ..midRefraction = midRefraction
      ..edgeRefraction = edgeRefraction
      ..edgeWidth = edgeWidth
      ..chromaticAberration = chromaticAberration
      ..flowAmount = flowAmount
      ..flowDir = flowDir
      ..depthEffect = depthEffect
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderLens extends RenderProxyBox {
  _RenderLens({
    required this._backdrop,
    required this._overlayBackdrop,
    required this._shader,
    required this.baseRadius,
    required this.scaleX,
    required this.scaleY,
    required this.midRefraction,
    required this.edgeRefraction,
    required this.edgeWidth,
    required this.chromaticAberration,
    required this.flowAmount,
    required this.flowDir,
    required this.depthEffect,
    required this.devicePixelRatio,
  }) {
    _backdrop.addListener(markNeedsPaint);
    _overlayBackdrop?.addListener(markNeedsPaint);
  }

  MiuixLayerBackdrop _backdrop;
  set backdrop(MiuixLayerBackdrop value) {
    if (identical(_backdrop, value)) return;
    _backdrop.removeListener(markNeedsPaint);
    _backdrop = value..addListener(markNeedsPaint);
    markNeedsPaint();
  }

  MiuixLayerBackdrop? _overlayBackdrop;
  set overlayBackdrop(MiuixLayerBackdrop? value) {
    if (identical(_overlayBackdrop, value)) return;
    _overlayBackdrop?.removeListener(markNeedsPaint);
    _overlayBackdrop = value;
    _overlayBackdrop?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  final ui.FragmentShader _shader;

  double baseRadius;
  double scaleX;
  double scaleY;
  double midRefraction;
  double edgeRefraction;
  double edgeWidth;
  double chromaticAberration;
  double flowAmount;
  double flowDir;
  double depthEffect;
  double devicePixelRatio;

  @override
  void detach() {
    _backdrop.removeListener(markNeedsPaint);
    _overlayBackdrop?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _backdrop.addListener(markNeedsPaint);
    _overlayBackdrop?.addListener(markNeedsPaint);
  }

  @override
  void dispose() {
    _backdrop.removeListener(markNeedsPaint);
    _overlayBackdrop?.removeListener(markNeedsPaint);
    _shader.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final ui.Image? image = _backdrop.snapshot;
    final Offset? backdropGlobal = _backdrop.globalOffset;
    if (image == null || backdropGlobal == null || size.isEmpty) {
      super.paint(context, offset);
      return;
    }

    final double deviceDpr = devicePixelRatio;
    final double snapDpr = _backdrop.pixelRatio;
    final double dprScale = snapDpr / deviceDpr;
    final double wPx = size.width * deviceDpr;
    final double hPx = size.height * deviceDpr;
    final Offset selfGlobal = localToGlobal(Offset.zero);
    final double sampleOffX = (selfGlobal.dx - backdropGlobal.dx) * snapDpr;
    final double sampleOffY = (selfGlobal.dy - backdropGlobal.dy) * snapDpr;

    // overlay（tabsBackdrop，dpr 未降采样）采样参数。
    final ui.Image? overlayImage = _overlayBackdrop?.snapshot;
    final Offset? overlayGlobal = _overlayBackdrop?.globalOffset;
    final bool hasOverlay = overlayImage != null && overlayGlobal != null;

    final double overlayDpr = hasOverlay
        ? _overlayBackdrop!.pixelRatio
        : deviceDpr;
    final double overlayDprScale = overlayDpr / deviceDpr;
    final double overlayOffX = hasOverlay
        ? (selfGlobal.dx - overlayGlobal.dx) * overlayDpr
        : 0;
    final double overlayOffY = hasOverlay
        ? (selfGlobal.dy - overlayGlobal.dy) * overlayDpr
        : 0;

    _shader
      ..setFloat(0, wPx) // uSize.x
      ..setFloat(1, hPx) // uSize.y
      ..setFloat(2, baseRadius * deviceDpr) // uCornerRadius
      ..setFloat(3, scaleX) // uScale.x
      ..setFloat(4, scaleY) // uScale.y
      ..setFloat(5, midRefraction * deviceDpr) // uMidRefraction
      ..setFloat(6, edgeRefraction * deviceDpr) // uEdgeRefraction
      ..setFloat(7, edgeWidth * deviceDpr) // uEdgeWidth
      ..setFloat(8, chromaticAberration) // uChromaticAberration
      ..setFloat(9, flowAmount * deviceDpr) // uFlowAmount
      ..setFloat(10, flowDir) // uFlowDir
      ..setFloat(11, depthEffect) // uDepthEffect
      ..setFloat(12, sampleOffX) // uSampleOffset.x
      ..setFloat(13, sampleOffY) // uSampleOffset.y
      ..setFloat(14, image.width.toDouble()) // uImageSize.x
      ..setFloat(15, image.height.toDouble()) // uImageSize.y
      ..setFloat(16, dprScale) // uDprScale
      ..setFloat(17, overlayOffX) // uOverlayOffset.x
      ..setFloat(18, overlayOffY) // uOverlayOffset.y
      ..setFloat(
        19,
        hasOverlay ? overlayImage.width.toDouble() : image.width.toDouble(),
      )
      ..setFloat(
        20,
        hasOverlay ? overlayImage.height.toDouble() : image.height.toDouble(),
      )
      ..setFloat(21, overlayDprScale) // uOverlayDprScale
      ..setFloat(22, hasOverlay ? 1.0 : 0.0) // uHasOverlay
      ..setImageSampler(0, image)
      // 恒绑定两个 sampler：无 overlay 时 uOverlay 绑页面占位，
      // 否则 Impeller 报 "missing sampler" 使整个 shader 失效。
      ..setImageSampler(1, hasOverlay ? overlayImage : image);

    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(1.0 / deviceDpr, 1.0 / deviceDpr);
    canvas.clipRect(Offset.zero & Size(wPx, hPx));
    canvas.drawRect(Offset.zero & Size(wPx, hPx), Paint()..shader = _shader);
    canvas.restore();

    super.paint(context, offset);
  }
}
