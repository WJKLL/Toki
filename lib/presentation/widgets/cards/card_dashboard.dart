// lib/presentation/widgets/cards/card_dashboard.dart
// 编号：C-29 仪表盘卡片（v1.14.0 登记,PROJECT_SPEC §5;v1.22.0 紧凑化）
// 职责：统计仪表盘 —— 标题 + 3 统计项（数值/标签）+ 分段进度条。
// 布局：网格 wide(2×1,整卡高 104):竖三段紧凑排(标题 13 / 统计行 / 进度条),
//       宽卡内自然横向铺满(3/4 列网格中占 2 格宽)。
// 样式：MiuixCard 标准样式 + 分段进度(progress 权重,主段 primary)。
// 性能：纯静态（const 数据），零 ticker。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../domain/entities/home_card.dart';

/// C-29 仪表盘卡片。
class C29DashboardCard extends StatelessWidget {
  const C29DashboardCard({super.key, required this.data});

  final DashboardCardData data;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return MiuixCard(
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
          // 3 统计项（等宽;紧凑字号）。
          Row(
            children: <Widget>[
              for (int i = 0; i < data.stats.length; i++)
                Expanded(
                  child: _StatCell(
                    value: data.stats[i].value,
                    label: data.stats[i].label,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 分段进度条（progress 权重）。
          Row(
            children: <Widget>[
              for (int i = 0; i < data.progress.length; i++)
                Expanded(
                  flex: data.progress[i],
                  child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: i == 0 ? colors.primary : colors.outline,
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
