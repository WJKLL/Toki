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
    this.depthImage,
    this.shift = Offset.zero,
    this.amount = 12,
    this.subjectRatio = 0.25,
    this.relief = 0,
  });

  final DepthLayerSet layerSet;

  /// 深度图（0 = 最远，1 = 最近），用于给【最近层】叠加立体起伏。
  ///
  /// 为 null 时最近层退化为整层刚性平移（内部无起伏）。
  final ui.Image? depthImage;

  /// 立体起伏系数：最近层的位移在常量系数之上再叠加 `relief×(depth−0.5)`。
  ///
  /// 单位与 [amount] 相同（逻辑像素）。取 6 左右 → 主体内部起伏约 ±3px：
  /// 够看出体积，又不会把遮挡空洞撑大（空洞由背景层兜底）。
  ///
  /// ★ 为什么"以前不敢、现在敢"
  ///   主体若只做整层平移，内部像素位移完全相同 —— 看上去是一块硬邦邦的
  ///   平板。逐像素位移能带来体积感，但会产生遮挡空洞，这正是当初改成
  ///   "整层平移"的原因。现在主体层之下有背景层兜底、空洞会被填上，
  ///   而起伏只有几个像素、远小于主体自身尺寸，所以可以安全启用。
  final double relief;

  /// 单位位移方向（各分量 -1..1）。
  final Offset shift;

  /// 最大位移（逻辑像素）—— 作用在【最远层】上。
  final double amount;

  /// 主体（最近层）的位移占 [amount] 的比例。
  ///
  /// 0 = 主体完全钉住（旧的反向模型），1 = 与背景同幅。
  /// 取 0.25：主体仍有可见位移（"晃动时主体还有一点立体感"，对齐苹果空间
  /// 照片的观感），但层间差只有 amount 的 0.75 倍 —— 穿帮带明显变窄。
  final double subjectRatio;

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
        depthImage: widget.depthImage,
        shift: widget.shift,
        amount: widget.amount,
        subjectRatio: widget.subjectRatio,
        relief: widget.relief,
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
    required this.depthImage,
    required this.shift,
    required this.amount,
    required this.subjectRatio,
    required this.relief,
    required this.devicePixelRatio,
  });

  final ui.FragmentShader shader;
  final DepthLayerSet layerSet;
  final ui.Image? depthImage;
  final Offset shift;
  final double amount;
  final double subjectRatio;
  final double relief;
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

    // ★ 位移系数：同向递减（对齐仿真验证过的观感，也是苹果空间照片的做法）。
    //
    //   层已按 centerDepth 升序排好 —— i = 0 最远、i = n−1 最近（主体）。
    //   最远层位移最大，最近层位移最小，但【方向一致】。
    //
    //   为什么不用"焦点层钉住 + 前后景反向"：
    //     穿帮带宽 = 相邻层的位移差。
    //       反向模型：主体纹丝不动、背景整体滑走 → 层间差 = uAmount，
    //                 主体轮廓外会露出一条 uAmount 宽的错位内容（实测：
    //                 "会露出被扣掉的部分"）；
    //       同向模型：层间差 = uAmount × (1 − subjectRatio) ≈ 0.75×uAmount，
    //                 而且主体自己也动 —— 观感是整片一起位移，"抠图边"不显眼，
    //                 同时主体仍保住"晃动时有一点立体感"。
    double coefOf(int i) {
      final int n = layers.length;
      if (n <= 1) return subjectRatio;
      final int idx = i < n ? i : n - 1;
      return subjectRatio + (1.0 - subjectRatio) * (n - 1 - idx) / (n - 1);
    }

    // ★ 视野放大倍率：位移会让层边缘取到纹理之外 —— 不处理就直接露出页面
    //   底色（实测反馈"空间图还是会露出底图"）。放大后等效于给每层补了
    //   margin：位移时画面边缘仍落在层图内部，既不露底、也没有边缘像素被
    //   拉伸的糊边。代价是四周各裁掉一点视野，裁多少随位移自动增大。
    //   （shader 侧是【除以】uZoom 才是收窄采样范围 —— 写成乘法会越界被 clamp，
    //     反而拉出一圈糊边，这一点极易写反。）
    final double amountPx = amount * devicePixelRatio;
    final double minSide = math.min(wPx, hPx);
    final double zoom = minSide <= 1.0
        ? 1.0
        : 1.0 + 2.0 * amountPx / minSide;

    // ★ 立体起伏只给【最近层】（主体）：其余层保持整层刚性平移。
    //   主体内部的深度差 → 位移差 → 起伏（浮雕感）；空洞由背景层兜底。
    final int last = layers.length - 1;
    final double reliefPx = relief * devicePixelRatio;
    double reliefOf(int i) => i == last ? reliefPx / math.max(amountPx, 1e-6) : 0.0;

    shader
      ..setFloat(0, wPx) // uSize.x
      ..setFloat(1, hPx) // uSize.y
      ..setFloat(2, shift.dx) // uShift.x
      ..setFloat(3, shift.dy) // uShift.y
      ..setFloat(4, amountPx) // uAmount
      ..setFloat(5, coefOf(0)) // uCoefs.x
      ..setFloat(6, coefOf(1)) // uCoefs.y
      ..setFloat(7, coefOf(2)) // uCoefs.z
      ..setFloat(8, coefOf(3)) // uCoefs.w
      ..setFloat(9, count.toDouble()) // uCount
      ..setFloat(10, zoom) // uZoom（视野放大，替代 margin）
      // uReliefs：只有最近层非 0（已归一到 uAmount 的倍数，见 reliefOf）
      ..setFloat(11, reliefOf(0))
      ..setFloat(12, reliefOf(1))
      ..setFloat(13, reliefOf(2))
      ..setFloat(14, reliefOf(3))
      // 所有 sampler 恒绑定（层数不足时用相邻层占位），
      // 否则 Skia 会因缺 sampler 判定整个 shader 失效。
      ..setImageSampler(0, imageOf(0))
      ..setImageSampler(1, imageOf(1))
      ..setImageSampler(2, imageOf(2))
      ..setImageSampler(3, imageOf(3))
      // uDepth：没有深度图时用第 0 层占位（此时 relief 系数为 0，不生效）
      ..setImageSampler(4, depthImage ?? imageOf(0));

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
        old.subjectRatio != subjectRatio ||
        old.relief != relief ||
        !identical(old.depthImage, depthImage) ||
        old.devicePixelRatio != devicePixelRatio ||
        !identical(old.layerSet, layerSet);
  }
}
