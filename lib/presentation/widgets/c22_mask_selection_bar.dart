// lib/presentation/widgets/c22_mask_selection_bar.dart
// 编号：C-22 内部子组件（普通模式蒙版选择框，v1.7.0，PROJECT_SPEC §5 C-22 增强）
// ✨ 新增：普通模式蒙版选择框（悬浮栏关闭时使用）
// 说明：静态选择框 —— 半透明底栏背景（无毛玻璃）、选中项圆角矩形蒙版、
//   无拖动、无液态玻璃效果、无动画（零 ticker）。
// 功耗要点：纯静态（Stateless、全 const 构建）；整栏 RepaintBoundary 由
//   编排器（C22ContentThroughFloatingBottomBar）包裹；手势区 viewPadding.bottom
//   内置于栏底，适配外壳 Column 布局。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/widgets/app_icons.dart';
import 'c22_content_through_floating_bottom_bar.dart';

/// C-22 普通模式蒙版选择框（静态，无拖动）。
class C22MaskSelectionBar extends StatelessWidget {
  const C22MaskSelectionBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<C22BarItemData> items;

  static const double _kHeight = 56; // 通栏高度（含内容）
  static const double _kRadius = 20; // 栏顶圆角
  static const double _kMaskRadius = 16; // 蒙版圆角

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final double gestureInset = MediaQuery.viewPaddingOf(context).bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: _kHeight,
          decoration: BoxDecoration(
            // 报告 T44：背景 surface（无模糊）。
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(_kRadius),
            ),
            border: Border(
              top: BorderSide(
                color: colors.outline.withValues(alpha: 0.25),
                width: 0.5, // 极细浅色描边
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double itemWidth = constraints.maxWidth / items.length;
              return Stack(
                children: [
                  // ── 蒙版（选中项圆角矩形，静态定位）──
                  Positioned(
                    left: currentIndex * itemWidth + 8,
                    top: 6,
                    width: itemWidth - 16,
                    height: _kHeight - 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(_kMaskRadius),
                      ),
                    ),
                  ),
                  // ── 选项行（静态，无拖动）──
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _C22MaskItem(
                            data: items[i],
                            selected: currentIndex == i,
                            onTap: () => onDestinationSelected(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        // 手势区（内置，适配外壳 Column 布局，等价 C-01 defaultWindowInsetsPadding）。
        SizedBox(height: gestureInset),
      ],
    );
  }
}

/// C-22 蒙版选择框项（icon + 小标签，静态）。
class _C22MaskItem extends StatelessWidget {
  const _C22MaskItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final C22BarItemData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Color tint = selected
        ? colors.primary
        : colors.onSurfaceVariantSummary;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: data.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MiuixIcon(vector: appIcon(data.iconName), size: 22, tint: tint),
            const SizedBox(height: 2),
            MiuixText(
              data.label,
              style: MiuixTheme.of(context).textStyles.body2,
              color: tint,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
