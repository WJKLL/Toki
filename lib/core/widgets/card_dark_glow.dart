// === 文件: lib/core/widgets/card_dark_glow.dart ===
// 编号：P-01-01 内部件(深色卡片描边光晕, v1.35.1 UI 优化)
// 说明：深色模式下卡片可读性增强 —— 卡片边缘 1px 微亮描边 + 极弱白色
//   环境光晕(静态、低对比、过渡自然),让深色卡片与深底分离;
//   **浅色模式零开销**(直接透传 child,无 DecoratedBox)。
//   - 深色判定与 CardShadow 同源(Miuix 实际取色 luminance);
//   - [radius] 必须与内层卡片圆角一致(避免描边露角),如 MiuixCard 默认 16;
//   - 与 CardShadow(黑系投影)分层叠加:外层投影 + 内层描边光晕。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 深色卡片描边光晕壳。
class CardDarkGlow extends StatelessWidget {
  const CardDarkGlow({
    super.key,
    required this.child,
    this.radius = 16,
    this.borderAlpha = 0x0D,
    this.glowAlpha = 0x05,
  });

  final Widget child;

  /// 描边圆角(与内卡一致)。
  final double radius;

  /// 描边白色 alpha(0x0D ≈ 5%)—— 低对比、不刺眼。
  final int borderAlpha;

  /// 光晕白色 alpha(极弱环境光)。
  final int glowAlpha;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool dark = colors.surface.computeLuminance() < 0.5;
    if (!dark) return child;
    const Color white = Color(0xFFFFFFFF);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: white.withValues(alpha: borderAlpha / 255),
          width: 1,
        ),
        // 极弱外发光:深底上给卡片一圈微亮轮廓(静态)。
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: white.withValues(alpha: glowAlpha / 255),
            blurRadius: 12,
            spreadRadius: -4,
          ),
        ],
      ),
      child: child,
    );
  }
}
