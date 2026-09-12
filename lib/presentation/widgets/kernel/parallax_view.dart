// lib/presentation/widgets/kernel/parallax_view.dart
// 编号：C-64 焦点控制器（渲染侧）/ U-08 空间输入源（位移输入）
//
// 用 FragmentShader 把【原图 + 深度图 + 焦点深度 + 位移向量】合成为视差画面。
// 与 lens.dart 的差异：这里用 CustomPainter 而非 RenderProxyBox —— 不需要背景
// 快照/layer backdrop，只需一张已解码的 ui.Image 作纹理，实现更轻。
//
// 性能：位移/焦点变化只改 uniform，不重建纹理；纹理由调用方持有并复用。
// 未就绪或加载失败时降级为直接显示原图（不阻塞页面）。
//
// ★ 谁走这条路（P-24 的两条渲染路径，不可互换）
//   · **无主体**（风景图 / 分割没抓到人）→ 走这里：位移随深度【连续】变化，
//     没有块间错位，适合深度连续分布的自然风景；
//   · 有主体（人像）→ 走 LayeredParallaxView：按 mask 切层、层内刚体平移，
//     近层移开由下层内容兜底，不会露出被抠掉的空洞。
//   反过来用会出问题：把风景图交给分层，等深线会横穿山脊与树丛，
//   在画面上切出可见的撕裂线（实测反馈："富士山等等都不太行"）。
import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 空间壁纸视差渲染组件。
class ParallaxView extends StatefulWidget {
  const ParallaxView({
    super.key,
    required this.image,
    required this.depth,
    this.shift = Offset.zero,
    this.amount = 24,
    this.focus = 0.5,
    this.showDepth = false,
    this.depthGamma = 1.0,
    this.layers = 4,
    this.focusBand = 0.12,
  });

  /// 原图（已解码）。
  final ui.Image image;

  /// 深度图（灰度 RGBA；0 = 最远，1 = 最近）。
  final ui.Image depth;

  /// 位移向量：方向 × 幅度，各分量 -1..1。焦点处不动，前后景反向。
  final Offset shift;

  /// 最大位移（逻辑像素）。
  final double amount;

  /// 焦点深度 0..1（该层像素完全钉住）。
  final double focus;

  /// 显示深度图而非成片（调试用）。
  final bool showDepth;

  /// 深度曲线：1 = 线性；>1 拉开前景差异。
  final double depthGamma;

  /// 深度分层数：<=1 = 连续；>1 = 量化成 N 层。
  ///
  /// ⚠️ 分层是**为几何模板设计的补丁**（几何模板的深度是光滑斜坡，连续位移
  /// 必然拉伸成"橡胶膜"，量化成层才能得到层叠平移）。对**真实 AI 深度图反而
  /// 有害**：等深线是不规则曲线，全局按深度值切层会在人物身上切出可见的斜向
  /// 分割线（实测反馈）。AI 模式应置 1。
  final double layers;

  /// 焦点带宽度：|深度 − 焦点| < 本值的区域**整片不动**，向外 smoothstep
  /// 平滑过渡到全位移。比"只有一条等深线不动"更符合"主体钉住、背景滑动"
  /// 的直觉，且不会产生硬边界。0 = 关闭。
  final double focusBand;

  @override
  State<ParallaxView> createState() => _ParallaxViewState();
}

class _ParallaxViewState extends State<ParallaxView> {
  static ui.FragmentProgram? _program;
  static bool _loading = false;

  ui.FragmentShader? _shader;

  void _ensureProgram() {
    if (_program != null || _loading) {
      if (_program != null && _shader == null) _attach();
      return;
    }
    _loading = true;
    unawaited(
      ui.FragmentProgram.fromAsset('shaders/spatial_parallax.frag')
          .then((ui.FragmentProgram p) {
            _program = p;
            _loading = false;
            if (mounted) _attach();
          })
          .catchError((Object e) {
            _loading = false;
            debugPrint('🔴 spatial_parallax shader load error: $e');
          }),
    );
  }

  void _attach() {
    setState(() => _shader = _program?.fragmentShader());
  }

  @override
  void initState() {
    super.initState();
    _ensureProgram();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentShader? shader = _shader;
    if (shader == null) {
      // 着色器未就绪 / 不支持（如部分 Web 环境）：降级显示原图。
      return RawImage(image: widget.image, fit: BoxFit.contain);
    }
    return CustomPaint(
      painter: _ParallaxPainter(
        shader: shader,
        image: widget.image,
        depth: widget.depth,
        shift: widget.shift,
        amount: widget.amount,
        focus: widget.focus,
        showDepth: widget.showDepth,
        depthGamma: widget.depthGamma,
        layers: widget.layers,
        focusBand: widget.focusBand,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ParallaxPainter extends CustomPainter {
  _ParallaxPainter({
    required this.shader,
    required this.image,
    required this.depth,
    required this.shift,
    required this.amount,
    required this.focus,
    required this.showDepth,
    required this.depthGamma,
    required this.layers,
    required this.focusBand,
    required this.devicePixelRatio,
  });

  final ui.FragmentShader shader;
  final ui.Image image;
  final ui.Image depth;
  final Offset shift;
  final double amount;
  final double focus;
  final bool showDepth;
  final double depthGamma;
  final double layers;
  final double focusBand;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final double wPx = size.width * devicePixelRatio;
    final double hPx = size.height * devicePixelRatio;
    if (wPx <= 0 || hPx <= 0) return;

    // ★ 视野放大倍率：逐像素位移会让画面边缘取到纹理之外，不处理就直接露出
    //   页面底色。与 LayeredParallaxView 用同一套办法 —— 把采样范围从 [0,1]
    //   收窄到 [c, 1-c]，等效于给画面补了 margin。
    //   逐像素模式下位移最大可达 amount（rel 取到 ±1），故按 2×amount 留余量。
    final double amountPx = amount * devicePixelRatio;
    final double minSide = math.min(wPx, hPx);
    final double zoom =
        minSide <= 1.0 ? 1.0 : 1.0 + 2.0 * amountPx / minSide;

    shader
      ..setFloat(0, wPx) // uSize.x
      ..setFloat(1, hPx) // uSize.y
      ..setFloat(2, shift.dx) // uShift.x
      ..setFloat(3, shift.dy) // uShift.y
      ..setFloat(4, amountPx) // uAmount（逻辑 px → 物理 px）
      ..setFloat(5, focus) // uFocus
      ..setFloat(6, showDepth ? 1.0 : 0.0) // uShowDepth
      ..setFloat(7, depthGamma) // uDepthGamma
      ..setFloat(8, layers) // uLayers
      ..setFloat(9, focusBand) // uFocusBand
      ..setFloat(10, zoom) // uZoom（视野放大，替代 margin）
      // 两个 sampler 恒绑定：即使 uShowDepth=1（不用原图）也必须绑原图，
      // 否则 shader 可能被整体判定失效。
      ..setImageSampler(0, image)
      ..setImageSampler(1, depth);

    canvas.save();
    canvas.scale(1.0 / devicePixelRatio);
    canvas.drawRect(
      Offset.zero & Size(wPx, hPx),
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ParallaxPainter old) {
    return old.shift != shift ||
        old.amount != amount ||
        old.focus != focus ||
        old.showDepth != showDepth ||
        old.depthGamma != depthGamma ||
        old.layers != layers ||
        old.focusBand != focusBand ||
        old.devicePixelRatio != devicePixelRatio ||
        !identical(old.image, image) ||
        !identical(old.depth, depth);
  }
}
