// lib/presentation/widgets/c35_quote_option_sheet.dart
// 编号：C-35 悬浮单选选择窗（v1.27.0 新增）
// 说明：内容设置(API 来源 / 语言风格 / 内容风格)通用单选浮窗 ——
//   MiuixOverlayDialog 封装:
//   - show 布尔常驻树驱动(与设置页导出对话框同款,P-05 先例);
//   - Miuix largeScreen 自动适配:窄屏底部弹出、宽屏居中悬浮;
//   - 选项行高亮选中(primary + w600),点击即选即关;
//   - 内容 ≤7 行紧凑列表,零 ticker,关闭后整树零开销。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 通用单选选项窗(内容设置分组共用)。
class QuoteOptionSheet extends StatelessWidget {
  const QuoteOptionSheet({
    super.key,
    required this.show,
    required this.title,
    required this.options,
    required this.optionLabel,
    required this.selected,
    required this.onSelect,
    required this.onDismissRequest,
  });

  /// 显隐(常驻树,false 零开销)。
  final bool show;

  final String title;

  /// 选项键列表(按当前上下文传入:API 5 项 / 语言 3 项 / 风格随 API)。
  final List<String> options;

  /// 键 → 展示标签。
  final String Function(String) optionLabel;

  /// 当前选中键(高亮)。
  final String selected;

  /// 选中回调(调用方负责落设置 + 关闭)。
  final ValueChanged<String> onSelect;

  /// 点遮罩/返回关闭。
  final VoidCallback onDismissRequest;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    return MiuixOverlayDialog(
      show: show,
      title: title,
      onDismissRequest: onDismissRequest,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final String key in options)
            GestureDetector(
              key: ValueKey<String>('quoteSheet.$key'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: MiuixText(
                  optionLabel(key),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.body1.copyWith(
                    color: key == selected ? colors.primary : colors.onSurface,
                    fontWeight: key == selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
