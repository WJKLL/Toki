// lib/presentation/widgets/c46_ledger_entry_card.dart
// 编号：C-46 账目流水卡片（v1.50.0，P-20 记账一级页列表项）
// 说明：MiuixCard 单行流水卡 —— 分类图标（圆形色底 + C-45 自绘图标）+
//   分类名/备注 + 右侧金额：
//   - 视觉 1:1 对齐 C-44 待办卡（CardShadow radius 16 + MiuixCard +
//     insideMargin 16/12 + 整卡点按/长按）；
//   - 金额口径：支出 -、收入 +（绿色，与 C-44 低优先级绿同色）、转账无符号；
//   - 纯展示 + 回调（不依赖 provider，便于测试与复用）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/widgets/ledger_icons.dart';
import '../../domain/entities/ledger_category.dart';
import '../../domain/entities/ledger_entry.dart';
import 'cards/card_shell.dart';

/// C-46 账目流水卡片。
class C46LedgerEntryCard extends StatelessWidget {
  const C46LedgerEntryCard({
    super.key,
    required this.entry,
    required this.category,
    required this.onTap,
    this.onLongPress,
  });

  final LedgerEntry entry;

  /// 所属分类（null = 转账 / 分类已删，回退「未分类」）。
  final LedgerCategory? category;

  /// 整卡点按（编辑）。
  final VoidCallback onTap;

  /// 长按（操作菜单）。
  final VoidCallback? onLongPress;

  /// 收入金额色（与 C-44 低优先级绿一致）。
  static const Color kIncomeColor = Color(0xFF36D167);

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final Color catColor = Color(category?.colorValue ?? 0xFF9AA0A6);
    final String title = entry.isTransfer
        ? '转账'
        : (category?.name ?? '未分类');
    final String sub = _subtitle();

    return CardShadow(
      radius: 16,
      child: MiuixCard(
        onPressed: onTap,
        onLongPress: onLongPress,
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            // ── 分类图标（圆形色底 + 自绘图标）──
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: MiuixIcon(
                  vector: ledgerIcon(category?.id ?? ''),
                  size: 20,
                  tint: catColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ── 分类名 + 备注/时间 ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  MiuixText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts.body1.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (sub.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    MiuixText(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── 金额 ──
            MiuixText(
              formatSignedCents(entry.kind, entry.amountCents),
              style: ts.body1.copyWith(
                color: switch (entry.kind) {
                  LedgerKind.income => kIncomeColor,
                  LedgerKind.transfer => colors.onSurfaceVariantSummary,
                  LedgerKind.expense => colors.onSurface,
                },
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 副行：备注 + 时间（备注为空时仅时间）。
  String _subtitle() {
    final String time =
        '${entry.date.hour.toString().padLeft(2, '0')}:'
        '${entry.date.minute.toString().padLeft(2, '0')}';
    final String note = entry.note.trim();
    return note.isEmpty ? time : '$note · $time';
  }
}
