// lib/presentation/widgets/c44_todo_task_card.dart
// 编号：C-44 待办任务卡片（v1.43.0 阶段1，P-10 单日列表项）
// 说明：MiuixCard 单行任务卡 —— 优先级色点 + 标题 + 副行(优先级/截止) +
//   右侧「完成」圆钮（点按归档进回收站）：
//   - 整卡点按 → 进入流程图编辑器（v1.44.0 P-11 /todo/:taskId）；
//   - 长按 → 请求操作菜单（编辑 / 删除，由使用方弹层处理）；
//   - 纯展示 + 回调（不直接依赖 provider，便于测试与复用）；
//   - v1.44.x：外包统一卡片壳 CardShadow(双层阴影)+ CardDarkGlow(暗色
//     描边光晕)，与首页卡片同阴影语言（浅色阴影、深色高光可读）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../domain/entities/todo_item.dart';
import 'cards/card_shell.dart';

/// C-44 待办任务卡片。
class C44TodoTaskCard extends StatelessWidget {
  const C44TodoTaskCard({
    super.key,
    required this.todo,
    required this.onOpen,
    required this.onComplete,
    required this.onMenuRequest,
  });

  final TodoItem todo;

  /// 整卡点按（进入流程图编辑器 P-11）。
  final VoidCallback onOpen;

  /// 完成 → 归档（回收站 P-12）。
  final VoidCallback onComplete;

  /// 长按 → 请求操作菜单（编辑 / 删除）。
  final VoidCallback onMenuRequest;

  /// 优先级色（0 低绿 / 1 中琥珀 / 2 高橙红）。
  static Color priorityColor(int priority) => switch (priority) {
    0 => const Color(0xFF36D167),
    2 => const Color(0xFFFF5B29),
    _ => const Color(0xFFF5A623),
  };

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    // v1.44.x：统一卡片壳 CardShadow(周围阴影 + 内建暗色高光,同首页)。
    // radius 16 对齐内层 MiuixCard 默认圆角。
    return CardShadow(
      radius: 16,
      child: MiuixCard(
        onPressed: onOpen,
        onLongPress: onMenuRequest,
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
        children: <Widget>[
          // ── 优先级色点 ──
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: priorityColor(todo.priority),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // ── 标题 + 副行 ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MiuixText(
                  todo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ts.body1.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                MiuixText(
                  _subtitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── 完成圆钮（✓ 归档）──
          MiuixPressable(
            key: ValueKey<String>('todo.complete.${todo.id}'),
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.86,
            borderRadius: BorderRadius.circular(999),
            onPressed: onComplete,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: MiuixIcon(
                vector: MiuixIcons.basic.check,
                size: 16,
                tint: colors.primary,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _subtitle() {
    final String pri = '${kTodoPriorityLabels[todo.priority]}优先级';
    // 截止日（选中日视图下多为今天/明天…仍给出绝对日期以防跨日遗留）。
    final DateTime now = DateTime.now();
    final bool thisYear = todo.date.year == now.year;
    final String dateText = thisYear
        ? '${todo.date.month}月${todo.date.day}日'
        : '${todo.date.year}年${todo.date.month}月${todo.date.day}日';
    return '$pri · 截止 $dateText';
  }
}
