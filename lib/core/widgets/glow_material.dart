// === 文件: lib/core/widgets/glow_material.dart ===
// 编号:GLOW-02 光感材质层(2026-09-09 一期静态光感 / P2-2 按压光圈)
// 说明:在子内容**之上**叠加一层纯 Canvas 光感(彩色柔光 + 边缘层次 + 顶高光线),
//   不改动子内容布局与命中测试;interactive=true 时额外响应按压(光圈从触点扩散)。
//
// 深浅两套参数(不可共用):
//   - 深色:白描边(顶亮底暗)+ 顶高光线 + 彩色柔光(BlendMode.plus, alpha ×0.11);
//   - 浅色:上缘白高光 / 下缘淡黑线 + 彩色柔光(BlendMode.srcOver, alpha ×0.04, 光池 2 个);
//     浅底上用 plus 会迅速推向过曝白;而 softLight 属**非分离式**混合(需读目标像素、
//     打断批处理) → 平板浅色实测掉帧,故一律用分离式混合。
//
// 形态自适应:卡片(三色沿上/右/下三边外侧渗入)/ 长条(两色沿短边渗入)。
//
// 性能约定(不可违背):
//   1. **零额外模糊 pass** —— 只用 gradient,不用 BackdropFilter / ImageFilter / MaskFilter.blur;
//   2. **静态零重绘** —— 无按压时 shouldRepaint 返回 false,不注册 Ticker;
//   3. **按压期 Ticker 仅在按下到松手之间运行**(forward 180ms / reverse 260ms),
//      松手后 controller 停止,回到静止零成本状态;
//   4. 档位「关」→ 完全透传,零绘制。
import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'glow_tokens.dart';

/// 光感档位作用域:由 App 顶层注入设置里的档位(GLOW-03)。
/// 未注入(单测/独立使用) → [GlowMaterial] 回退 gentle;注入且 level=null → 关闭。
class GlowScope extends InheritedWidget {
  const GlowScope({super.key, required this.level, required super.child});

  /// null = 用户关闭光感。
  final GlowLevel? level;

  static GlowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlowScope>();

  @override
  bool updateShouldNotify(GlowScope oldWidget) => oldWidget.level != level;
}

/// 光感材质层(overlay)。
class GlowMaterial extends StatefulWidget {
  const GlowMaterial({
    super.key,
    required this.child,
    this.level,
    this.enabled = true,
    this.radius = 18,
    this.interactive = false,
  });

  final Widget child;

  /// 显式档位(优先);null → 取 [GlowScope](未注入时回退 gentle)。
  final GlowLevel? level;

  /// false → 直接透传 child(零绘制)。
  final bool enabled;

  /// 圆角(必须与内层卡片/容器圆角一致,避免描边露角)。
  final double radius;

  /// P2-2:是否响应按压(光圈从触点扩散)。默认 false —— 仅可点击容器开启。
  final bool interactive;

  @override
  State<GlowMaterial> createState() => _GlowMaterialState();
}

class _GlowMaterialState extends State<GlowMaterial>
    with SingleTickerProviderStateMixin {
  /// 按压进度 0→1(按下 forward)/ 1→0(松手 reverse)。
  /// 仅在 interactive 时惰性创建,松手后自然停在 0(不再有帧回调)。
  AnimationController? _press;
  double _progress = 0;
  Offset? _point;

  @override
  void dispose() {
    _press?.dispose();
    super.dispose();
  }

  void _ensurePress() {
    _press ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 260),
    )..addListener(() {
      final double v = _press!.value;
      if (v == _progress) {
        return;
      }
      setState(() => _progress = v);
    });
  }

  void _onDown(PointerDownEvent event) {
    _ensurePress();
    _point = event.localPosition;
    unawaited(_press!.forward());
  }

  /// 松手/取消:光圈反向回收,并清掉触点(避免任何残留)。
  void _release() {
    _point = null;
    final AnimationController? c = _press;
    if (c != null) {
      unawaited(c.reverse());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final GlowScope? scope = GlowScope.maybeOf(context);
    final GlowLevel? eff =
        widget.level ?? (scope == null ? GlowLevel.gentle : scope.level);
    if (eff == null) {
      // 用户把光感档位设为「关」→ 完全透传(零绘制)。
      return widget.child;
    }
    // 深浅判定与 CardShadow / CardDarkGlow 同源(Miuix 实际取色 luminance)。
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool dark = colors.surface.computeLuminance() < 0.5;
    final Widget painted = CustomPaint(
      // 注:此处**不**套 RepaintBoundary —— 它会把图层尺寸限制为卡片本体,
      //   导致 CardShadow 的外扩阴影被裁切;浅色卡片已禁用光感,
      //   深色卡片数量有限,静态绘制成本可接受。
      // 用 foregroundPainter:光感需叠在卡片背景**之上**才可见
      // (卡片背景不透明,画在下方会被完全遮住,只剩边缘漏光 → 视觉上像色斑)。
      foregroundPainter: _GlowMaterialPainter(
        tokens: GlowTokens.of(eff),
        radius: widget.radius,
        dark: dark,
        // Monet 取色下背景色随壁纸变化,固定三色会显得跳 → 光色向主题表面色靠拢。
        pressPoint: _point,
        pressProgress: _progress,
      ),
      child: widget.child,
    );
    if (!widget.interactive) {
      return painted;
    }
    return Listener(
      // deferToChild:不拦截命中测试,点击/长按仍由子内容处理。
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onDown,
      // 不监听 move:光圈只在按下点扩散(监听 move 会每帧 setState 重建,
      //   实测会干扰子内容的按压态回收 → 卡片按压后残留灰色背景)。
      onPointerUp: (PointerUpEvent _) => _release(),
      onPointerCancel: (PointerCancelEvent _) => _release(),
      child: painted,
    );
  }
}

/// 指示框光感层(侧边栏选中项 / 底栏液态指示器共用)。
/// 形状由 [shape] 决定(侧边栏用 Squircle 16,底栏用 StadiumBorder),
/// 内容 = 三色柔光(沿长边两端渗入)+ 顶部细高光线。
/// 纯 Canvas、零 blur、shouldRepaint 仅参数变化 → 静止零重绘。
class GlowIndicatorPainter extends CustomPainter {
  const GlowIndicatorPainter({
    required this.dark,
    required this.level,
    required this.shape,
  });

  final bool dark;

  final GlowLevel level;

  /// 指示框形状(决定裁剪路径与圆角)。
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final Path clip = shape.getOuterPath(Offset.zero & size);
    canvas.save();
    canvas.clipPath(clip);

    // 彩色光源已按用户要求移除(指示框保留顶部细高光线)。
    final GlowTokens t = GlowTokens.of(level);

    // 顶部细高光线(柔和过渡;浅色底白线不可见 → 仅深色绘制)。
    if (dark) {
      final double specA = t.specularOpacity * 0.5;
      final Paint line = Paint()
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: <Color>[
            const Color(0x00FFFFFF),
            const Color(0xFFFFFFFF).withValues(alpha: specA),
            const Color(0x00FFFFFF),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
      canvas.drawLine(
        Offset(size.width * 0.18, 0.8),
        Offset(size.width * 0.82, 0.8),
        line,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GlowIndicatorPainter old) =>
      old.dark != dark ||
      old.level != level ||
      old.shape != shape;
}

class _GlowMaterialPainter extends CustomPainter {
  const _GlowMaterialPainter({
    required this.tokens,
    required this.radius,
    required this.dark,
    required this.pressPoint,
    required this.pressProgress,
  });

  final GlowTokens tokens;
  final double radius;
  final bool dark;



  /// P2-2:按压触点(容器内坐标)与进度(0 静止 / 1 完全按下)。
  final Offset? pressPoint;
  final double pressProgress;


  /// 按压光圈的峰值白 alpha(再乘档位系数)。
  static const double _pressPeakAlpha = 0.20;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final RRect rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rr);
    // 彩色光源已按用户要求移除(保留边缘层次 / 顶高光线 / 按压光圈)。
    // _paintGlow(canvas, size);
    _paintEdge(canvas, size, rr);
    if (dark) {
      _paintTopLine(canvas, size);
    }
    _paintPress(canvas, size);
    canvas.restore();
  }

  // ── 2) 边缘层次 ─────────────────────────────────────────────
  void _paintEdge(Canvas canvas, Size size, RRect rr) {
    final Paint edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    if (dark) {
      // 深色:白色渐变描边(顶 .9 → 中 .2 → 底 .26,官方参考比例 × 0.46)。
      edge.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0xFFFFFFFF).withValues(alpha: 0.9 * 0.46),
          const Color(0xFFFFFFFF).withValues(alpha: 0.2 * 0.46),
          const Color(0xFFFFFFFF).withValues(alpha: 0.26 * 0.46),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size);
    } else {
      // 浅色:上缘白高光 → 中段透明 → 下缘极淡黑线(内高光 / 外阴影层次)。
      edge.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0xFFFFFFFF).withValues(alpha: 0.55),
          const Color(0x00FFFFFF),
          const Color(0xFF000000).withValues(alpha: 0.06),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size);
    }
    canvas.drawRRect(rr.deflate(0.55), edge);
  }

  // ── 3) 顶高光线(仅深色;浅底白线不可见)──────────────────────
  void _paintTopLine(Canvas canvas, Size size) {
    final double specA = tokens.specularOpacity * 0.7;
    if (specA <= 0.01) {
      return;
    }
    // v1.50.4：原实现按固定 inset(12) + radius 内缩取端点 —— 在 FAB 这类
    //   窄容器(56px / radius 18)上起点(30) > 终点(26)，线长变负 → 退化成
    //   一个白色小点。改为按宽度比例取 18%~82%（与 GlowIndicatorPainter
    //   同写法）：宽卡片观感基本不变，窄容器自然缩短且永不反向。
    final double cx = size.width / 2;
    final double halfSpan = size.width * 0.32;
    final double x1 = cx - halfSpan;
    final double x2 = cx + halfSpan;
    if (x2 - x1 < 4) {
      return;
    }
    final Paint topLine = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: <Color>[
          const Color(0x00FFFFFF),
          const Color(0xFFFFFFFF).withValues(alpha: specA),
          const Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawLine(Offset(x1, 0.9), Offset(x2, 0.9), topLine);
  }

  // ── 4) 按压光圈(P2-2)──────────────────────────────────────
  // 白色柔光从触点向外扩散:半径随进度放大、alpha 先升后随半径摊薄,
  // 松手 reverse 自然回收。纯 gradient,无 blur、无 shader。
  void _paintPress(Canvas canvas, Size size) {
    final Offset? p = pressPoint;
    final double t = pressProgress;
    if (p == null || t <= 0.01) {
      return;
    }
    final double peak =
        _pressPeakAlpha * tokens.alphaMultiplier.clamp(0.6, 2.2);
    final double r = size.longestSide * (0.10 + 0.85 * t);
    final Paint paint = Paint()
      ..blendMode = dark ? BlendMode.plus : BlendMode.srcOver
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFFFFFFFF).withValues(alpha: peak * t),
          const Color(0xFFFFFFFF).withValues(alpha: peak * t * 0.30),
          const Color(0x00FFFFFF),
        ],
        stops: const <double>[0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: p, radius: r));
    canvas.drawCircle(p, r, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowMaterialPainter old) =>
      old.tokens != tokens ||
      old.radius != radius ||
      old.dark != dark ||
      old.pressPoint != pressPoint ||
      old.pressProgress != pressProgress;
}
