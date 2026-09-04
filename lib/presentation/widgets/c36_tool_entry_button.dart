// === 文件: lib/presentation/widgets/c36_tool_entry_button.dart ===
// 编号：C-36 工具入口按钮（v1.34.0 新增;v1.35.0 数据源 ToolItem → ToolConfig）
// 说明：工具目录单个入口(48dp 高,样式 = MiuixCard squircle + CardShadow
//   悬浮阴影 + sink 按压反馈[≈0.96 下沉],与首页卡片同阴影语言):
//   - **点按** → context.push(工具派生 route:customRoute 或 /tool/<id>);
//   - **长按 500ms**(Flutter 默认长按阈值)+ HapticFeedback.mediumImpact
//     → 弹出「添加到首页」浮层(MiuixOverlayDialog:窄屏底部/宽屏居中,
//     与 C-35 同体系) —— 已加入时操作行置灰不可点(『✅ 已添加至首页』);
//   - 图标经 ToolBrandIcon(C-38 泛化):custom:steam 自绘 / 其余 MiuixIcons,
//     工具 icon 缺省回退分类 icon;
//   - 网格布局由使用方(P-01-04 / C-42)排布,本组件单卡。
// 功耗:静态图标/文案;浮层 show 布尔常驻树,false 零开销(与 C-35 一致)。
import 'dart:async' show unawaited;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'cards/card_shell.dart';
import '../../core/widgets/mini_toast.dart';
import '../../core/widgets/tool_brand_icon.dart';
import '../../domain/entities/tool_config.dart';
import '../providers/home_cards_provider.dart';

/// C-36 工具入口按钮(点击进工具 / 长按 500ms 添加至首页)。
class C36ToolEntryButton extends ConsumerStatefulWidget {
  const C36ToolEntryButton({
    super.key,
    required this.item,
    this.categoryIcon,
  });

  final ToolConfig item;

  /// 分类图标名(工具 icon 缺省时兜底)。
  final String? categoryIcon;

  @override
  ConsumerState<C36ToolEntryButton> createState() => _C36ToolEntryButtonState();
}

class _C36ToolEntryButtonState extends ConsumerState<C36ToolEntryButton> {
  /// 添加浮层显隐(show 布尔驱动,false 零开销)。
  bool _sheet = false;

  void _openSheet() {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _sheet = true);
  }

  void _addToHome() {
    final ToolConfig item = widget.item;
    unawaited(ref.read(homeToolItemsProvider.notifier).add(item.id));
    showMiniToast(context, '已添加到首页 · ${item.name}');
    setState(() => _sheet = false);
  }

  @override
  Widget build(BuildContext context) {
    final ToolConfig item = widget.item;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool added = ref.watch(
      homeToolItemsProvider.select(
        (List<String> ids) => ids.contains(item.id),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ── 48dp 入口:CardShadow + MiuixCard(squircle) + sink 按压 ──
        CardShadow(
          radius: 16,
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: MiuixCard(
              cornerRadius: 16,
              feedbackType: MiuixPressFeedbackType.sink,
              onPressed: () => context.push(item.route),
              onLongPress: _openSheet,
              insideMargin: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  ToolBrandIcon(
                    tool: item,
                    fallbackIcon: widget.categoryIcon,
                    size: 22,
                    tint: colors.onSurfaceVariantActions,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MiuixText(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MiuixTheme.of(context).textStyles.body2.copyWith(
                        color: colors.onSurfaceContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── 长按添加浮层(MiuixOverlayDialog 自适应;关闭即整树零开销)──
        MiuixOverlayDialog(
          show: _sheet,
          title: '添加到首页',
          onDismissRequest: () => setState(() => _sheet = false),
          content: GestureDetector(
            key: ValueKey<String>('toolAdd.${item.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: added ? null : _addToHome,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: <Widget>[
                  ToolBrandIcon(
                    tool: item,
                    fallbackIcon: widget.categoryIcon,
                    size: 26,
                    tint: added
                        ? colors.disabledOnSurface
                        : colors.onSurfaceVariantActions,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        MiuixText(
                          added ? '✅ 已添加至首页' : '✨ 添加至首页',
                          style: MiuixTheme.of(context).textStyles.body1.copyWith(
                            color: added
                                ? colors.disabledOnSurface
                                : colors.onSurface,
                            fontWeight: added
                                ? FontWeight.w400
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MiuixText(
                          added ? '已加入,点首页卡片右上 ✕ 可移除' : item.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          fontSize: 12,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ],
                    ),
                  ),
                  if (added)
                    MiuixIcon(
                      vector: MiuixIcons.basic.check,
                      size: 18,
                      tint: colors.disabledOnSurface,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
