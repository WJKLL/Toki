// lib/presentation/features/todo/page_p12_archive_page.dart
// 编号：P-12 回收站列表（v1.43.0 阶段2，二级页 /todo/archived）
// 说明：展示已归档(完成)任务的精简条目 —— 标题 + 原截止日 + 完成日：
//   - 恢复：翻回未完成并回到待办主页原日期（流程图数据保留）；
//   - 永久删除：确认后从待办+归档移除并删除流程图数据；
//   - 空态引导；顶栏 C-25 + C-21 返回胶囊。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../../domain/entities/todo_item.dart';
import '../../providers/todo_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/cards/card_shell.dart';

/// P-12 回收站页。
class PageP12ArchivePage extends ConsumerStatefulWidget {
  const PageP12ArchivePage({super.key});

  @override
  ConsumerState<PageP12ArchivePage> createState() => _PageP12ArchivePageState();
}

class _PageP12ArchivePageState extends ConsumerState<PageP12ArchivePage> {
  /// 待永久删除的目标（null = 确认弹窗关闭）。
  ArchivedTodo? _deleteTarget;

  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('archive.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  /// 恢复（未完成 + 移除归档条目）。
  Future<void> _restore(ArchivedTodo a) async {
    await ref.read(todoListProvider.notifier).restore(a.id);
    if (mounted) {
      showMiniToast(
        context,
        '已恢复 · ${a.title}（截止 ${_dateText(a.originalDate)}）',
      );
    }
  }

  Future<void> _confirmDelete() async {
    final ArchivedTodo? a = _deleteTarget;
    setState(() => _deleteTarget = null);
    if (a == null) return;
    await ref.read(todoListProvider.notifier).permanentlyDelete(a.id);
    if (mounted) showMiniToast(context, '已永久删除 · ${a.title}');
  }

  static String _dateText(DateTime d) {
    final DateTime now = DateTime.now();
    final bool thisYear = d.year == now.year;
    return thisYear ? '${d.month}月${d.day}日' : '${d.year}年${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '回收站',
        largeTitle: '回收站',
        navigationIcon: _backButton,
        scrollBehavior: _collapse,
      ),
      content: (padding) {
        final Widget list = ListView(
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(top: 12 + padding.top, bottom: 24),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            ..._buildBody(context),
          ],
        );
        return ColoredBox(color: colors.surface, child: list);
      },
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final List<ArchivedTodo> archived =
        ref.watch(archivedListProvider).value ?? const <ArchivedTodo>[];
    // 最近完成在前。
    final List<ArchivedTodo> sorted = <ArchivedTodo>[...archived]
      ..sort((ArchivedTodo a, ArchivedTodo b) =>
          b.completedAt.compareTo(a.completedAt));

    if (sorted.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
          child: Column(
            children: <Widget>[
              MiuixIcon(
                vector: appIcon('delete'),
                size: 44,
                tint: colors.outline.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 14),
              MiuixText(
                '回收站是空的',
                style: ts.body1,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 4),
              MiuixText(
                '点任务卡右侧 ✓ 完成的任务会出现在这里',
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
            ],
          ),
        ),
      ];
    }
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: MiuixText(
          '${sorted.length} 个已完成任务',
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
        ),
      ),
      for (final ArchivedTodo a in sorted)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          // v1.44.x：统一卡片壳 CardShadow(阴影 + 内建暗色高光,同首页)。
          child: CardShadow(
            radius: 16,
            child: MiuixCard(
              insideMargin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      MiuixText(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts.body1.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      MiuixText(
                        '截止 ${_dateText(a.originalDate)} · '
                        '完成于 ${_dateText(a.completedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        fontSize: 11,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 恢复。
                MiuixPressable(
                  key: ValueKey<String>('archive.restore.${a.id}'),
                  feedbackType: MiuixPressFeedbackType.sink,
                  sinkAmount: 0.86,
                  borderRadius: BorderRadius.circular(999),
                  onPressed: () => _restore(a),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: MiuixIcon(
                      vector: appIcon('undo'),
                      size: 15,
                      tint: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 永久删除。
                MiuixPressable(
                  key: ValueKey<String>('archive.delete.${a.id}'),
                  feedbackType: MiuixPressFeedbackType.sink,
                  sinkAmount: 0.86,
                  borderRadius: BorderRadius.circular(999),
                  onPressed: () => setState(() => _deleteTarget = a),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: MiuixIcon(
                      vector: appIcon('delete'),
                      size: 15,
                      tint: colors.error,
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      // 删除确认弹窗。
      _buildDeleteDialog(colors),
    ];
  }

  Widget _buildDeleteDialog(MiuixColors colors) {
    final ArchivedTodo? a = _deleteTarget;
    return MiuixOverlayDialog(
      show: a != null,
      title: '永久删除',
      onDismissRequest: () => setState(() => _deleteTarget = null),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MiuixText(
              '「${a?.title ?? ''}」将被永久删除，无法恢复。',
              fontSize: 14,
              color: colors.onSurface,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                MiuixButton(
                  onPressed: () => setState(() => _deleteTarget = null),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                MiuixButton(
                  onPressed: _confirmDelete,
                  colors: MiuixButtonColors(
                    color: colors.error,
                    disabledColor: colors.error.withValues(alpha: 0.4),
                    contentColor: colors.onError,
                    disabledContentColor: colors.onError,
                  ),
                  child: const Text('永久删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
