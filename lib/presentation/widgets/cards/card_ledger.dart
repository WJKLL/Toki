// lib/presentation/widgets/cards/card_ledger.dart
// 编号：C-51 记账剩余卡 / C-52 记账支出卡（v1.50.2，首页网格）
// 说明：按用户口径拆成**两张独立卡片**（原 v1.50.1 单卡切换版废弃）：
//   - C-51 剩余卡（1×1）：本月剩余圆环，口径 = 预算 + 本月收入 − 本月支出；
//   - C-52 支出卡（2×1）：顶部四档粗体标签（本日/本周/本月/本年）横向排列，
//     下方分别对应细体金额（同时展示，非切换）。
//   - 两卡均点击进记账一级页（/?page=2）。
// 性能：watch ledgerHomeCardProvider（轻量派生）；C-32 圆环自带
//   RepaintBoundary，静止零 ticker。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/home_card.dart';
import '../../../domain/entities/ledger_entry.dart';
import '../../providers/ledger_providers.dart';
import '../../providers/settings_providers.dart';
import '../c32_ring_progress.dart';

/// C-51 记账剩余卡（1×1）：圆环 + 本月剩余。
class C51LedgerRemainingCard extends ConsumerWidget {
  const C51LedgerRemainingCard({super.key, required this.data});

  final LedgerRemainingCardData data;

  /// 剩余环默认金黄（Monet 关闭时；与 C-44 中优先级金黄同色系）。
  static const Color kRemainingGold = Color(0xFFF5A623);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final LedgerHomeCardData d = ref.watch(ledgerHomeCardProvider);
    final bool hasQuota = d.quotaCents > 0;
    // 环色：超支一律 error；否则 Monet 开启 → 跟随取色主色，关闭 → 默认金黄。
    final bool monet = ref.watch(
      appSettingsProvider.select((AppSettings s) => s.monetEnabled),
    );
    final Color ringColor = d.remainingCents < 0
        ? colors.error
        : (monet ? colors.primary : kRemainingGold);

    return MiuixCard(
      onPressed: () => context.go('/?page=2'),
      insideMargin: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: <Widget>[
          // 圆环：剩余 / 额度（预算 + 本月收入）。
          C32AnimatedRing(
            progress: d.remainingRatio,
            color: ringColor,
            backgroundColor: colors.outline.withValues(alpha: 0.2),
            size: 46,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MiuixText(
                  '本月剩余',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
                const SizedBox(height: 3),
                MiuixText(
                  hasQuota ? formatCents(d.remainingCents) : '未设预算',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts.title4.copyWith(
                    color: d.remainingCents < 0
                        ? colors.error
                        : colors.onSurface,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// C-52 记账支出卡（2×1）：四档粗体标签 + 下方细体金额。
class C52LedgerExpenseCard extends ConsumerWidget {
  const C52LedgerExpenseCard({super.key, required this.data});

  final LedgerExpenseCardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final LedgerHomeCardData d = ref.watch(ledgerHomeCardProvider);

    return MiuixCard(
      onPressed: () => context.go('/?page=2'),
      insideMargin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MiuixText(
            data.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 8),
          // 四档：顶部粗体标签，下方细体金额（同时展示）。
          Row(
            children: <Widget>[
              for (final LedgerRange r in LedgerRange.values)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // 标签字号对齐卡片标题档（subtitle 14 粗体）。
                      MiuixText(
                        r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts.subtitle.copyWith(color: colors.onSurface),
                      ),
                      const SizedBox(height: 3),
                      MiuixText(
                        formatCents(d.expenseByRange[r] ?? 0),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts.body2.copyWith(
                          color: colors.onSurfaceVariantSummary,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
