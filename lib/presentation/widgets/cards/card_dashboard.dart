// lib/presentation/widgets/cards/card_dashboard.dart
// 编号：C-29 待办卡片（v1.14.0 仪表盘登记;v1.22.0 紧凑化;
//   v1.49.0 改造:更名「待办」并实时联动待办页）
// 职责：首页 2×1 实时待办卡 —— 标题「待办」+ 三段统计(今日完成/总任务/
//   当前待办)+ 底部四段进度(已完成/已逾期/今天到期/未来,权重=数量)。
// 联动：watch todoOverviewProvider(todo 全量 + 归档派生)—— 在待办页
//   增删改/勾完成后返回首页自动刷新;点击卡片 → 待办一级页(/?page=0)。
// 布局：网格 wide(2×1,整卡高 104):竖三段紧凑排(标题 13 / 统计行 / 进度条)。
// 样式：MiuixCard(原生 onPressed 按压反馈)+ 四段语义色。
// 性能：watch 轻量派生;静态零 ticker。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/home_card.dart';
import '../../providers/todo_providers.dart';

/// C-29 待办卡。
class C29DashboardCard extends ConsumerWidget {
  const C29DashboardCard({super.key, required this.data});

  final DashboardCardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final TodoOverview o = ref.watch(todoOverviewProvider);
    final List<int> seg = o.segments;
    final bool empty = seg.every((int w) => w == 0);
    return MiuixCard(
      onPressed: () => context.go('/?page=0'), // 跳待办一级页。
      insideMargin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MiuixText(
            data.title,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariantSummary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // 3 统计项(等宽;紧凑字号):今日完成 / 总任务 / 当前待办。
          Row(
            children: <Widget>[
              _StatCell(value: '${o.doneToday}', label: '今日完成'),
              _StatCell(value: '${o.total}', label: '总任务'),
              _StatCell(value: '${o.pending}', label: '待办'),
            ],
          ),
          const SizedBox(height: 8),
          // 四段进度:已完成(主色)/已逾期(error)/今天到期(次级)/未来(灰)。
          Row(
            children: <Widget>[
              for (int i = 0; i < 4; i++)
                Expanded(
                  flex: empty ? 1 : seg[i].clamp(0, 1 << 30),
                  child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: empty
                          ? colors.outline.withValues(alpha: 0.25)
                          : switch (i) {
                              0 => colors.primary,
                              1 => colors.error,
                              2 => colors.secondary,
                              _ => colors.outline,
                            },
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 统计项单元（数值 + 标签;网格 wide 卡紧凑档）。
class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MiuixText(
          value,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        const SizedBox(height: 1),
        MiuixText(label, fontSize: 11, color: colors.onSurfaceVariantSummary),
      ],
    );
  }
}
