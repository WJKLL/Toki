// lib/presentation/widgets/c49_month_navigation.dart
// 编号：C-49 月份导航（v1.50.0，P-20 记账一级页顶部）
// 说明：‹ 2026年9月 › 左右翻月；点中间标题回到本月（非本月时标题右侧
//   显示「回本月」小字提示）。视觉沿用全 App 圆形色底按钮语言
//   （surfaceContainerHigh 圆底 + onSurfaceVariantActions 图标）。
// 功耗：Stateless、无动画控制器，静止零 ticker。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// C-49 月份导航。
class C49MonthNavigation extends StatelessWidget {
  const C49MonthNavigation({
    super.key,
    required this.month,
    required this.onChanged,
  });

  /// 当前查看月份（仅年 + 月）。
  final DateTime month;

  /// 月份变化回调（翻月 / 回本月）。
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final DateTime now = DateTime.now();
    final bool isCurrent = month.year == now.year && month.month == now.month;

    return Row(
      children: <Widget>[
        _arrow(colors, forward: false, onTap: () => onChanged(_shift(-1))),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点标题 → 回本月（已在本月时无操作）。
            onTap: isCurrent ? null : () => onChanged(DateTime(now.year, now.month)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MiuixText(
                  '${month.year}年${month.month}月',
                  style: ts.subtitle.copyWith(color: colors.onSurface),
                ),
                const SizedBox(height: 2),
                MiuixText(
                  isCurrent ? '本月' : '点击回到本月',
                  fontSize: 11,
                  color: isCurrent
                      ? colors.primary
                      : colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ),
        ),
        _arrow(colors, forward: true, onTap: () => onChanged(_shift(1))),
      ],
    );
  }

  DateTime _shift(int delta) => DateTime(month.year, month.month + delta);

  /// 左右箭头圆钮。
  Widget _arrow(
    MiuixColors colors, {
    required bool forward,
    required VoidCallback onTap,
  }) {
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.9,
      borderRadius: BorderRadius.circular(999),
      onPressed: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: RotatedBox(
            quarterTurns: forward ? 0 : 2,
            child: MiuixIcon(
              vector: MiuixIcons.basic.arrowRight,
              size: 16,
              tint: colors.onSurfaceVariantActions,
            ),
          ),
        ),
      ),
    );
  }
}
