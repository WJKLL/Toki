// lib/presentation/router/miuix_route_transitions.dart
// 说明：二级页面切换过渡动画（复刻参考项目 KernelSU-Style-UI-Kit
//   的 miuix-navigation3-ui 0.9.2 NavDisplay 转场规格）：
//   - 进入：新页自屏幕右缘整宽滑入，转场期间左缘（与旧页交界缘）上下两角
//     带圆角（32px，参考项目取设备屏幕圆角，Flutter 无系统圆角 API，用常量近似）；
//   - **一级页面完全不动**（v1.31.0 用户定稿：去掉旧页让位 1/4 与压暗 0.5，
//     仅新页覆盖滑入；原「下层角色」代码已移除，secondaryAnimation 不消费）；
//   - 时长 500ms，曲线 = NavTransitionEasing(response=0.8, damping=0.75)
//     的 1:1 Dart 移植（快进、末端约 2.8% 过头再收回的克制回弹）；
//     v1.31.0：**回到最初验收版逻辑，仅改阻尼**（用户纠正：退场不再做方向
//     分流,与最初版一致由曲线反向遍历驱动）——damping 0.95 → 0.75；
//     若需更强/更弱回弹,改 damping 重算下方 r/w/c2 常量即可,
//     参考值:0.80→过冲 1.5%、0.70→过冲 4.6%；
//   - 返回（pop/系统返回键/浏览器后退）：自动反向播放（顶层右滑出）；
//   - 静止后零开销：opaque 下层不再构建。
// 动效开关（blurEnabled）关闭时由 pageBuilder 层直接使用 NoTransitionPage（本文件不参与）。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 二级页转场时长（与参考项目一致）。
const Duration kMiuixRouteTransitionDuration = Duration(milliseconds: 500);

/// 转场期间卡片圆角（px）。参考项目读取设备屏幕圆角，Flutter 无此 API，
/// 采用常量近似（32px 适中档，可调）。
const double kMiuixRouteTransitionCorner = 32;

/// MIUI 阻尼曲线：miuix-navigation3-ui 0.9.2 NavTransitionEasing
/// （response=0.8, damping=0.75，v1.29.0 用户定稿：调小阻尼获得回弹）同公式移植。
/// 数学：omega = 2π/response；k = omega²；c = damping·4π/response；
///   w = sqrt(4k − c²)/2；r = −c/2；c2 = r/w；
///   transform(t) = e^(r·t)·(−cos(w·t) + c2·sin(w·t)) + 1。
/// 预计算常量（damping=0.75）：r = −5.8904862255、w = 5.1949205513、
///   c2 = −1.1338934190；末端过冲约 +2.8%。
class MiuixNavCurve extends Curve {
  const MiuixNavCurve();

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    const double r = -5.8904862255;
    const double w = 5.1949205513;
    const double c2 = -1.1338934190;
    final double decay = math.exp(r * t);
    // 峰值约 1.028（t≈0.46），轻微过冲后收敛回 1，无需 clamp。
    return decay * (-math.cos(w * t) + c2 * math.sin(w * t)) + 1.0;
  }
}

/// 统一二级页路由过渡（进入/退出 + 作为下层被覆盖两种角色）。
///
/// 角色判定（Flutter 机制与参考项目 AnimatedContent 同构）：
/// - [animation]：本页作为顶层 push/pop 时的进度（push 0→1、pop 1→0）；
/// - [secondaryAnimation]：上层 route 在本页之上 push/pop 时的进度
///   （push 0→1、pop 1→0；无上层时恒 0 —— 静止零开销直通）。
Widget buildMiuixRouteTransitions(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // ── 顶层角色：右滑入/右滑出 + 转场期间左缘上下圆角 ──────────
  final Widget topLevel = AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (BuildContext context, Widget? c) {
      // 与最初验收版(阻尼 0.95)同一套逻辑,仅阻尼数值改为 0.75:
      // 位移统一 = 1 − curve(animation.value),进/退均由曲线反向遍历驱动
      // (用户要求:最初的样子,只改阻尼;不再做方向分流)。
      const MiuixNavCurve curve = MiuixNavCurve();
      final double t = curve.transform(animation.value);
      final bool animating =
          animation.status == AnimationStatus.forward ||
          animation.status == AnimationStatus.reverse;
      Widget content = c!;
      if (animating) {
        // 圆角跟随「与旧页的交界缘」（从右进出 → 左缘），静止后移除。
        content = ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(kMiuixRouteTransitionCorner),
            bottomLeft: Radius.circular(kMiuixRouteTransitionCorner),
          ),
          child: content,
        );
      }
      return FractionalTranslation(
        translation: Offset(1.0 - t, 0.0),
        child: content,
      );
    },
  );

  // ── v1.31.0（用户定稿）：一级页面完全不动 —— 旧页不再让位/压暗，
  //    仅新页右滑入覆盖；secondaryAnimation 不再消费。
  //    （原 0.95 版「让位 1/4 + 压暗 0.5」的下层角色已按用户要求移除，
  //      旧页保持原位，视觉 = 纯覆盖滑入。）
  return topLevel;
}
