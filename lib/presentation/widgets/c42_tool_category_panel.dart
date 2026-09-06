// === 文件: lib/presentation/widgets/c42_tool_category_panel.dart ===
// 编号：C-42 工具分类折叠面板（v1.35.0 新增,P-01-04 分组数据源改造）
// 说明：工具页按 UAPI 实测分类分组 —— 每组一个折叠面板:
//   - 头部 = 分类图标 + 分类名 + 工具数 + 旋转箭头（MiuixPressable sink
//     按压反馈,与 C-36 同反馈语言;展开/收起 AnimatedSize 300ms 平滑）;
//   - **默认折叠**,仅展开时渲染子项(懒渲染,功耗友好);
//   - 展开区 = 自适应入口网格(C-36,列数复用 C-34 gridColumnsForWidth)。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_icons.dart';
import '../../domain/entities/tool_config.dart';
import 'c34_responsive_card_grid.dart';
import 'c36_tool_entry_button.dart';
import 'cards/card_shell.dart';

/// C-42 单分类折叠面板。
class C42ToolCategoryPanel extends ConsumerStatefulWidget {
  const C42ToolCategoryPanel({super.key, required this.node});

  final ToolCategoryNode node;

  @override
  ConsumerState<C42ToolCategoryPanel> createState() =>
      _C42ToolCategoryPanelState();
}

class _C42ToolCategoryPanelState extends ConsumerState<C42ToolCategoryPanel> {
  /// 默认折叠;展开时才渲染网格子项（懒渲染）。
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ToolCategoryNode node = widget.node;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final String iconName =
        node.icon.isNotEmpty ? node.icon : node.category.icon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ── 头部:独立圆角长条(阴影立体 + 深色描边光晕;整条可点折叠)──
        MiuixPressable(
          feedbackType: MiuixPressFeedbackType.sink,
          sinkAmount: 0.96,
          borderRadius: BorderRadius.circular(14),
          onPressed: () => setState(() => _expanded = !_expanded),
          // v1.44.x：暗色高光内建进 CardShadow(此处原 CardDarkGlow 撤除,
          // 防双重描边)。
          child: CardShadow(
            radius: 14,
            child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: <Widget>[
                    MiuixIcon(
                      vector: appIcon(iconName),
                      size: 18,
                      tint: colors.onSurfaceVariantSummary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MiuixText(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.body1.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    MiuixText(
                      '${node.tools.length} 个',
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                    const SizedBox(width: 4),
                    // 箭头:展开时旋转 180°。
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: MiuixIcon(
                        vector: appIcon('expandMore'),
                        size: 20,
                        tint: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                ),
              ),
          ),
        ),
        // ── 展开区:顶部缩进分割线(标题/内容分界)+ 网格(懒渲染)──
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 中间分割:标题条与展开内容的分界线(outline 淡,缩进)。
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 10),
                      child: Container(
                        height: 0.5,
                        color: colors.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildGrid(context),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// 展开区入口网格：列数复用 C-34（<600→2 / 600-1099→3 / ≥1100→4）。
  Widget _buildGrid(BuildContext context) {
    final ToolCategoryNode node = widget.node;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availW = constraints.maxWidth;
        final int cols = gridColumnsForWidth(availW);
        const double gap = kGridCardGap;
        final double cellW = (availW - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final ToolConfig item in node.tools)
              SizedBox(
                width: cellW,
                child: C36ToolEntryButton(
                  item: item,
                  categoryIcon: node.icon,
                ),
              ),
          ],
        );
      },
    );
  }
}
