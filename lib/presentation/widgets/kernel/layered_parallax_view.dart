// lib/presentation/widgets/kernel/layered_parallax_view.dart
// 编号：C-64 焦点控制器（渲染侧）—— 分层版 / GPU 合成
//
// ★ 为什么从 Canvas 改成 shader
//   原实现用「多次 canvas.drawImage + alpha 合成」，真机上出现"背景大范围泛白"。
//   连续调整 FilterQuality（medium/low/high）、margin 边缘复制、drawImageRect→
//   translate+drawImage、工作尺寸（1024→1440）**全部无效** —— 说明该路径不适合
//   承担分层合成，继续在它上面试错没有意义。
//
//   而 shader 路径在本项目里已被验证可靠：几何模板（spatial_parallax.frag）
//   从一开始就正常，从未出现过泛白。且 uv 归一化采样让缩放交给 GPU 双线性完成，
//   质量与性能都优于 CPU 侧反复缩放。
//
// 合成公式即标准 source-over，从最远层开始：
//     acc = mix(acc, layerColor, layerAlpha)
import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/depth/depth_layer_splitter.dart';

/// 分层视差渲染组件（GPU 合成）。
class LayeredParallaxView extends StatefulWidget {
  const LayeredParallaxView({
    super.key,
    required this.layerSet,
    this.shift = Offset.zero,
    this.amount = 26,
    this.focus = 0.5,
  });

  final DepthLayerSet layerSet;

  /// 单位位移方向（各分量 -1..1）。
  final Offset shift;

  /// 最大位移（逻辑像素）。
  final double amount;

  /// 焦点深度 0..1（该层完全钉住）。
  final double focus;

  @override
  State<LayeredParallaxView> createState() => _LayeredParallaxViewState();
}

class _LayeredParallaxViewState extends State<LayeredParallaxView> {
  static ui.FragmentProgram? _program;
  static bool _loading = false;

  ui.FragmentShader? _shader;

  void _ensure() {
    final ui.FragmentProgram? p = _program;
    if (p != null) {
      if (_shader == null && mounted) {
        setState(() => _shader = p.fragmentShader());
      }
      return;
    }
    if (_loading) return;
    _loading = true;
    unawaited(
      ui.FragmentProgram.fromAsset('shaders/layer_compose.frag')
          .then((ui.FragmentProgram prog) {
            _program = prog;
            _loading = false;
            if (mounted) setState(() => _shader = prog.fragmentShader());
          })
          .catchError((Object e) {
            _loading = false;
            debugPrint('🔴 layer_compose shader load error: $e');
          }),
    );
  }

  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<DepthLayer> layers = widget.layerSet.layers;
    if (layers.isEmpty) return const SizedBox.expand();

    final ui.FragmentShader? shader = _shader;
    if (shader == null) {
      // 着色器未就绪：退化为直接显示最远层（不位移），保证不空白。
      return RawImage(image: layers.first.image, fit: BoxFit.fill);
    }
    return CustomPaint(
      painter: _ComposePainter(
        shader: shader,
        layerSet: widget.layerSet,
        shift: widget.shift,
        amount: widget.amount,
        focus: widget.focus,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ComposePainter extends CustomPainter {
  _ComposePainter({
    required this.shader,
    required this.layerSet,
    required this.shift,
    required this.amount,
    required this.focus,
    required this.devicePixelRatio,
  });

  final ui.FragmentShader shader;
  final DepthLayerSet layerSet;
  final Offset shift;
  final double amount;
  final double focus;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final List<DepthLayer> layers = layerSet.layers;
    if (layers.isEmpty) return;

    final double wPx = size.width * devicePixelRatio;
    final double hPx = size.height * devicePixelRatio;
    final int count = layers.length.clamp(1, 4);

    ui.Image imageOf(int i) =>
        i < layers.length ? layers[i].image : layers.last.image;

    // 位移系数：焦点所在层钉住（0），其余层按【层序距离】给有符号系数 ——
    // 比焦点层远的为负、近的为正，前后景反向移动才是立体感的来源。
    // span 只取"焦点层到最边缘层"的距离，于是【层间位移差 = uAmount】：
    // 10~12px 就能有清楚的空间感，不必把总位移拉到 20px+（那会让采样越界的
    // 边缘拉伸变得明显）。
    int focusLayer = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < layers.length; i++) {
      final double dd = (layers[i].centerDepth - focus).abs();
      if (dd < bestDist) {
        bestDist = dd;
        focusLayer = i;
      }
    }
    final int span = math.max(focusLayer, layers.length - 1 - focusLayer);
    double coefOf(int i) {
      if (span == 0) return 0.0;
      final int idx = i < layers.length ? i : layers.length - 1;
      return (idx - focusLayer) / span;
    }

    shader
      ..setFloat(0, wPx) // uSize.x
      ..setFloat(1, hPx) // uSize.y
      ..setFloat(2, shift.dx) // uShift.x
      ..setFloat(3, shift.dy) // uShift.y
      ..setFloat(4, amount * devicePixelRatio) // uAmount
      ..setFloat(5, coefOf(0)) // uCoefs.x
      ..setFloat(6, coefOf(1)) // uCoefs.y
      ..setFloat(7, coefOf(2)) // uCoefs.z
      ..setFloat(8, coefOf(3)) // uCoefs.w
      ..setFloat(9, count.toDouble()) // uCount
      // 四个 sampler 恒绑定（层数不足时用相邻层占位），
      // 否则 Skia 会因缺 sampler 判定整个 shader 失效。
      ..setImageSampler(0, imageOf(0))
      ..setImageSampler(1, imageOf(1))
      ..setImageSampler(2, imageOf(2))
      ..setImageSampler(3, imageOf(3));

    canvas.save();
    canvas.scale(1.0 / devicePixelRatio);
    canvas.drawRect(
      Offset.zero & Size(wPx, hPx),
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ComposePainter old) {
    return old.shift != shift ||
        old.amount != amount ||
        old.focus != focus ||
        old.devicePixelRatio != devicePixelRatio ||
        !identical(old.layerSet, layerSet);
  }
}
