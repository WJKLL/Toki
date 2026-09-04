// lib/kernel/dual_peak_highlight.dart
// dualPeak 双峰高光组件：基于 flutter_miuix 官方 MiuixHighlight 结构（画法验证正确），
// 换用 bloom_dual_peak.frag（dualPeak：dot(N.xy, L.xy)² → 180° 对峰）。
// 覆盖参考项目 iosIndicatorSpecular（dualPeak=true）的标志性双峰高光。
import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 双峰高光：参数与 [MiuixHighlight] 同构（Highlight + ShapeBorder）。
class DualPeakHighlight extends StatefulWidget {
  const DualPeakHighlight({
    super.key,
    required this.highlight,
    this.shape,
    this.child,
  });

  final Highlight highlight;
  final ShapeBorder? shape;
  final Widget? child;

  @override
  State<DualPeakHighlight> createState() => _DualPeakHighlightState();
}

class _DualPeakHighlightState extends State<DualPeakHighlight> {
  static ui.FragmentProgram? _program;
  static bool _loading = false;

  void _ensureLoaded() {
    if (_program != null || _loading) return;
    _loading = true;
    unawaited(
      ui.FragmentProgram.fromAsset('shaders/bloom_dual_peak.frag')
          .then((p) {
            _program = p;
            _loading = false;
            if (mounted) setState(() {});
          })
          .catchError((Object e) {
            _loading = false;
            debugPrint('🔴 dualPeak shader load error: $e');
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
    final Widget child = widget.child ?? const SizedBox.expand();
    final ui.FragmentProgram? program = _program;
    if (program == null ||
        widget.highlight.width <= 0 ||
        widget.highlight.alpha <= 0) {
      return child;
    }
    return _DualPeakRenderWidget(
      highlight: widget.highlight,
      shape: widget.shape,
      program: program,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: child,
    );
  }
}

class _DualPeakRenderWidget extends SingleChildRenderObjectWidget {
  const _DualPeakRenderWidget({
    required this.highlight,
    required this.shape,
    required this.program,
    required this.devicePixelRatio,
    required super.child,
  });

  final Highlight highlight;
  final ShapeBorder? shape;
  final ui.FragmentProgram program;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDualPeak(
    highlight: highlight,
    shape: shape,
    shader: program.fragmentShader(),
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDualPeak)
      ..highlight = highlight
      ..shape = shape
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderDualPeak extends RenderProxyBox {
  _RenderDualPeak({
    required this._highlight,
    required this._shape,
    required this._shader,
    required this._devicePixelRatio,
  });

  final ui.FragmentShader _shader;

  Highlight _highlight;
  set highlight(Highlight v) {
    if (_highlight == v) return;
    _highlight = v;
    markNeedsPaint();
  }

  ShapeBorder? _shape;
  set shape(ShapeBorder? v) {
    if (_shape == v) return;
    _shape = v;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double v) {
    if (_devicePixelRatio == v) return;
    _devicePixelRatio = v;
    markNeedsPaint();
  }

  @override
  void dispose() {
    _shader.dispose();
    super.dispose();
  }

  // 光源参考原点（与 flutter_miuix miuix_highlight.dart 一致）。
  static const double _lightRefX = 0.5;
  static const double _lightRefY = 0.7;

  List<double> _cornerRadiiPx(double wPx, double hPx) {
    final double maxR = math.min(wPx, hPx) / 2.0;
    double all = maxR;
    if (_shape is RoundedRectangleBorder) {
      final BorderRadius br = (_shape as RoundedRectangleBorder).borderRadius
          .resolve(TextDirection.ltr);
      return [
        math.min(br.topLeft.x * _devicePixelRatio, maxR),
        math.min(br.topRight.x * _devicePixelRatio, maxR),
        math.min(br.bottomLeft.x * _devicePixelRatio, maxR),
        math.min(br.bottomRight.x * _devicePixelRatio, maxR),
      ];
    }
    return [all, all, all, all];
  }

  /// 方向光 dir/color/intensity uniform（dualPeak 无 axis，返回 7 项）。
  List<double> _lightUniforms(LightSource light) {
    final double dx = light.position.x - _lightRefX;
    final double dy = light.position.y - _lightRefY;
    final double dz = light.position.z;
    final double len = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 1e-6);
    final double nx = dx / len, ny = dy / len, nz = dz / len;
    final Color c = light.color;
    final double intensity = c.a * light.intensity;
    return [nx, ny, nz, c.r, c.g, c.b, intensity];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset); // 先画子内容
    if (size.isEmpty) return;

    final double dpr = _devicePixelRatio;
    final double wPx = size.width * dpr;
    final double hPx = size.height * dpr;
    final double strokeWidthPx = math.min(
      _highlight.width * dpr,
      math.min(wPx, hPx) / 2.0,
    );
    final double innerPx = _highlight.style.innerBlurRadius * dpr;
    final List<double> radii = _cornerRadiiPx(wPx, hPx);
    final List<double> l1 = _lightUniforms(_highlight.style.primaryLight);
    final List<double> l2 = _lightUniforms(_highlight.style.secondaryLight);
    final Color sc = _highlight.style.color;

    // uniform 下标与 bloom_dual_peak.frag 声明一致（0-30，无 axis）。
    _shader
      ..setFloat(0, wPx * 0.5)
      ..setFloat(1, hPx * 0.5)
      ..setFloat(2, (wPx * 0.5).floorToDouble())
      ..setFloat(3, (hPx * 0.5).floorToDouble())
      ..setFloat(4, radii[0])
      ..setFloat(5, radii[1])
      ..setFloat(6, radii[2])
      ..setFloat(7, radii[3])
      ..setFloat(8, strokeWidthPx)
      ..setFloat(9, innerPx)
      ..setFloat(10, innerPx * innerPx)
      ..setFloat(11, _highlight.alpha)
      ..setFloat(12, sc.r)
      ..setFloat(13, sc.g)
      ..setFloat(14, sc.b)
      ..setFloat(15, 1.0)
      ..setFloat(16, sc.a)
      ..setFloat(17, l1[0])
      ..setFloat(18, l1[1])
      ..setFloat(19, l1[2])
      ..setFloat(20, l1[3])
      ..setFloat(21, l1[4])
      ..setFloat(22, l1[5])
      ..setFloat(23, l1[6])
      ..setFloat(24, l2[0])
      ..setFloat(25, l2[1])
      ..setFloat(26, l2[2])
      ..setFloat(27, l2[3])
      ..setFloat(28, l2[4])
      ..setFloat(29, l2[5])
      ..setFloat(30, l2[6]);

    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(1.0 / dpr, 1.0 / dpr);
    final Paint paint = Paint()
      ..shader = _shader
      ..blendMode = _highlight.style.blendMode;
    canvas.drawRect(Offset.zero & Size(wPx, hPx), paint);
    canvas.restore();
  }
}
