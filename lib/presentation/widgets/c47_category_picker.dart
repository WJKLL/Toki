// lib/presentation/widgets/c47_category_picker.dart
// 编号：C-47 分类选择器（v1.50.0，P-20 记账「记一笔」）
// 说明：一级分类 4 列网格 + 二级分类横排（选中一级且存在二级时展开）：
//   - 图标走 C-45 自绘图标集（ledgerIcon），色走分类自身色；
//   - 选中态：色底加深 + 同色描边 + 名称着色（与待办优先级胶囊同语言）；
//   - 纯展示 + 回调，不依赖 provider（便于复用与测试）；
//   - 无动画控制器：选中切换为纯重建，静止零 ticker。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/widgets/ledger_icons.dart';
import '../../domain/entities/ledger_category.dart';

/// C-47 一级分类网格（4 列）。
class C47CategoryPicker extends StatelessWidget {
  const C47CategoryPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  /// 一级分类（调用方已按类型过滤 + 排序）。
  final List<LedgerCategory> categories;

  /// 当前选中分类 id（空 = 未选）。
  final String selectedId;

  final ValueChanged<LedgerCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const int columns = 4;
        const double spacing = 8;
        final double itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: <Widget>[
            for (final LedgerCategory c in categories)
              SizedBox(
                width: itemWidth,
                child: _CategoryTile(
                  category: c,
                  selected: c.id == selectedId,
                  iconSize: 22,
                  onTap: () => onSelected(c),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// C-47 二级分类横排（紧凑：图标 + 名称一行）。
class C47SubCategoryPicker extends StatelessWidget {
  const C47SubCategoryPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<LedgerCategory> categories;
  final String selectedId;
  final ValueChanged<LedgerCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MiuixText(
          '细分',
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final LedgerCategory c in categories)
              _SubChip(
                category: c,
                selected: c.id == selectedId,
                onTap: () => onSelected(c),
              ),
          ],
        ),
      ],
    );
  }
}

/// 一级分类格子（圆形色底图标 + 名称）。
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.iconSize,
    required this.onTap,
  });

  final LedgerCategory category;
  final bool selected;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Color tint = Color(category.colorValue);
    return GestureDetector(
      key: ValueKey<String>('ledger.cat.${category.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: selected ? 0.24 : 0.12),
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: tint, width: 1.4)
                  : null,
            ),
            child: Center(
              child: MiuixIcon(
                vector: ledgerIcon(category.id),
                size: iconSize,
                tint: selected ? tint : tint.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(height: 6),
          MiuixText(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? tint : colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }
}

/// 二级分类胶囊（图标 + 名称）。
class _SubChip extends StatelessWidget {
  const _SubChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final LedgerCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Color tint = Color(category.colorValue);
    return GestureDetector(
      key: ValueKey<String>('ledger.subcat.${category.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? tint.withValues(alpha: 0.20)
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: selected ? Border.all(color: tint, width: 1.2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MiuixIcon(
              vector: ledgerIcon(category.id),
              size: 15,
              tint: selected ? tint : colors.onSurfaceVariantSummary,
            ),
            const SizedBox(width: 6),
            MiuixText(
              category.name,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? tint : colors.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}
