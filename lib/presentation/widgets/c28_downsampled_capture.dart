// lib/presentation/widgets/c28_downsampled_capture.dart
// 编号：C-28 降采样快照捕获（v1.17.3，顶栏模糊更新频率优化）
// 职责：MiuixLayerBackdropCapture 的降采样变体 —— 快照录制 pixelRatio =
//   dpr×downsample（默认 0.5），toImageSync 成本降为原 1/downsample²（1/4），
//   从而允许页面 CaptureHeartbeat 采样频率 6→3（顶栏模糊滚动更新 20→40Hz，
//   消除「反应迟钝/撕裂」），总快照成本不升反降（功耗友好）。
//   模糊观感不变：C-27 按 backdrop.pixelRatio 做像素映射，sigma 取逻辑像素。
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 降采样快照捕获：把子树渲染输出录制进 [backdrop]（低分辨率），供模糊组件取样。
class C28DownsampledCapture extends SingleChildRenderObjectWidget {
  const C28DownsampledCapture({
    super.key,
    required this.backdrop,
    this.downsample = 0.5,
    required super.child,
  });

  final MiuixLayerBackdrop backdrop;

  /// 快照降采样系数（0<d≤1；0.5 = 面积 1/4）。
  final double downsample;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDownsampledCapture(
      backdrop: backdrop,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      downsample: downsample,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDownsampledCapture)
      ..backdrop = backdrop
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..downsample = downsample;
  }
}

class _RenderDownsampledCapture extends RenderProxyBox {
  _RenderDownsampledCapture({
    required this._backdrop,
    required this._devicePixelRatio,
    required this._downsample,
  });

  MiuixLayerBackdrop _backdrop;
  MiuixLayerBackdrop get backdrop => _backdrop;
  set backdrop(MiuixLayerBackdrop value) {
    if (identical(_backdrop, value)) return;
    _backdrop = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  double _downsample;
  double get downsample => _downsample;
  set downsample(double value) {
    if (_downsample == value) return;
    _downsample = value;
    markNeedsPaint();
  }

  // 独立重绘边界：直接对真实 OffsetLayer 做 toImageSync 快照（避免重录图层重入）。
  @override
  bool get isRepaintBoundary => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _scheduleCapture();
  }

  bool _captureScheduled = false;

  void _scheduleCapture() {
    if (_captureScheduled || !hasSize || size.isEmpty) return;
    _captureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _captureScheduled = false;
      if (!attached || !hasSize || size.isEmpty) return;
      _capture();
    });
  }

  void _capture() {
    final offsetLayer = layer;
    if (offsetLayer is! OffsetLayer) return;
    // 降采样快照：pixelRatio = dpr×downsample（面积缩小 downsample²）。
    final double dpr = _devicePixelRatio * _downsample;
    final ui.Image image = offsetLayer.toImageSync(
      Offset.zero & size,
      pixelRatio: dpr,
    );
    final global = localToGlobal(Offset.zero);
    _backdrop.updateSnapshot(image, global, dpr);
  }
}
