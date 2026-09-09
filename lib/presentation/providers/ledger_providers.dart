// lib/presentation/providers/ledger_providers.dart
// 编号：S-25 记账状态管理（v1.50.0，P-20 记账一级页）
// 说明：账目全量 + 分类全量两路 Riverpod 状态 —— AsyncNotifier 加载 + CRUD；
//   任一处修改自动持久化（一级页 / 统计页 / 分类管理共享，自动同步）。
//   - 金额一律「分」为单位 int；
//   - 月度统计与按日分组为**纯函数**（computeMonthStats / groupEntriesByDay），可单测；
//   - 月份切换为独立 Notifier（StateProvider 在 Riverpod 3 已移除）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/ledger_category.dart';
import '../../domain/entities/ledger_entry.dart';
import '../../domain/repositories/ledger_repository.dart';

/// 记账仓储（main.dart override 注入，与 todoRepositoryProvider 同模式）。
final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => throw UnimplementedError(
    'ledgerRepositoryProvider must be overridden in main()',
  ),
);

// ── 账目 ──────────────────────────────────────────────────────

final ledgerEntriesProvider =
    AsyncNotifierProvider<LedgerEntriesNotifier, List<LedgerEntry>>(
      LedgerEntriesNotifier.new,
    );

class LedgerEntriesNotifier extends AsyncNotifier<List<LedgerEntry>> {
  @override
  Future<List<LedgerEntry>> build() async {
    return ref.read(ledgerRepositoryProvider).loadEntries();
  }

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  /// 新增一条账目（金额为分，恒正；转账 categoryId 传空串）。
  Future<void> add({
    required LedgerKind kind,
    required int amountCents,
    required String categoryId,
    required DateTime date,
    String note = '',
  }) async {
    if (amountCents <= 0) return;
    final DateTime now = DateTime.now();
    final LedgerEntry entry = LedgerEntry(
      id: _genId(),
      kind: kind,
      amountCents: amountCents,
      categoryId: categoryId,
      date: date,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _persist(<LedgerEntry>[...?state.value, entry]);
  }

  /// 更新整条（编辑）。
  Future<void> updateEntry(LedgerEntry entry) async {
    final List<LedgerEntry> list = <LedgerEntry>[...?state.value];
    final int i = list.indexWhere((LedgerEntry e) => e.id == entry.id);
    if (i < 0) return;
    list[i] = entry;
    await _persist(list);
  }

  /// 删除一条。
  Future<void> remove(String id) async {
    await _persist(<LedgerEntry>[
      for (final LedgerEntry e in state.value ?? const <LedgerEntry>[])
        if (e.id != id) e,
    ]);
  }

  Future<void> _persist(List<LedgerEntry> entries) async {
    state = AsyncData<List<LedgerEntry>>(entries);
    await _repo.saveEntries(entries);
  }

  static String _genId() =>
      '${DateTime.now().millisecondsSinceEpoch}'
      '${(DateTime.now().microsecond % 0xFFFF).toRadixString(16)}';
}

// ── 分类 ──────────────────────────────────────────────────────

final ledgerCategoriesProvider =
    AsyncNotifierProvider<LedgerCategoriesNotifier, List<LedgerCategory>>(
      LedgerCategoriesNotifier.new,
    );

class LedgerCategoriesNotifier extends AsyncNotifier<List<LedgerCategory>> {
  @override
  Future<List<LedgerCategory>> build() async {
    return ref.read(ledgerRepositoryProvider).loadCategories();
  }

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  /// 新增自定义分类（追加到同级末尾）。
  Future<void> addCategory({
    required String name,
    required LedgerKind kind,
    String parentId = '',
    int colorValue = 0xFF9AA0A6,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final List<LedgerCategory> list = <LedgerCategory>[...?state.value];
    int order = 0;
    for (final LedgerCategory c in list) {
      if (c.kind == kind && c.parentId == parentId && c.order >= order) {
        order = c.order + 1;
      }
    }
    list.add(
      LedgerCategory(
        id: 'custom_${_genId()}',
        name: trimmed,
        kind: kind,
        parentId: parentId,
        colorValue: colorValue,
        order: order,
      ),
    );
    await _persist(list);
  }

  /// 改名。
  Future<void> renameCategory(String id, String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _persist(<LedgerCategory>[
      for (final LedgerCategory c in state.value ?? const <LedgerCategory>[])
        if (c.id == id) c.copyWith(name: trimmed) else c,
    ]);
  }

  /// 删除（连同其二级分类；内置分类不可删）。
  Future<void> removeCategory(String id) async {
    await _persist(<LedgerCategory>[
      for (final LedgerCategory c in state.value ?? const <LedgerCategory>[])
        if (c.id != id && c.parentId != id && !(c.id == id && c.builtIn)) c,
    ]);
  }

  /// 恢复内置预设（丢弃全部自定义分类）。
  Future<void> resetToDefault() async {
    final List<LedgerCategory> preset = defaultLedgerCategories();
    state = AsyncData<List<LedgerCategory>>(preset);
    await _repo.resetCategories();
  }

  Future<void> _persist(List<LedgerCategory> categories) async {
    state = AsyncData<List<LedgerCategory>>(categories);
    await _repo.saveCategories(categories);
  }

  static String _genId() =>
      '${DateTime.now().millisecondsSinceEpoch}'
      '${(DateTime.now().microsecond % 0xFFFF).toRadixString(16)}';
}

/// 分类 id → 分类（O(1) 查询，UI 列表按 id 取色/取名）。
final ledgerCategoryMapProvider = Provider<Map<String, LedgerCategory>>((ref) {
  final List<LedgerCategory> list =
      ref.watch(ledgerCategoriesProvider).value ?? const <LedgerCategory>[];
  return <String, LedgerCategory>{
    for (final LedgerCategory c in list) c.id: c,
  };
});

/// 指定类型的一级分类（升序）。
List<LedgerCategory> topCategoriesOf(
  List<LedgerCategory> all,
  LedgerKind kind,
) {
  return <LedgerCategory>[
    for (final LedgerCategory c in all)
      if (c.isTop && c.kind == kind) c,
  ]..sort((LedgerCategory a, LedgerCategory b) => a.order.compareTo(b.order));
}

/// 指定父分类下的二级分类（升序）。
List<LedgerCategory> subCategoriesOf(
  List<LedgerCategory> all,
  String parentId,
) {
  return <LedgerCategory>[
    for (final LedgerCategory c in all)
      if (c.parentId == parentId) c,
  ]..sort((LedgerCategory a, LedgerCategory b) => a.order.compareTo(b.order));
}

// ── 当前查看月份 ──────────────────────────────────────────────

final ledgerMonthProvider = NotifierProvider<LedgerMonthController, DateTime>(
  LedgerMonthController.new,
);

/// 当前查看的月份（仅年 + 月，day 恒为 1）。
class LedgerMonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  /// 前后翻月（delta = ±1 或任意月数）。
  void shift(int delta) {
    state = DateTime(state.year, state.month + delta);
  }

  /// 直接跳到某月。
  void setMonth(DateTime month) {
    state = DateTime(month.year, month.month);
  }

  /// 回到本月。
  void toCurrent() {
    final DateTime now = DateTime.now();
    state = DateTime(now.year, now.month);
  }
}

// ── 月度预算 ──────────────────────────────────────────────────

/// 月度预算（分；0 = 未设置）。
final ledgerBudgetProvider = NotifierProvider<LedgerBudgetController, int>(
  LedgerBudgetController.new,
);

class LedgerBudgetController extends Notifier<int> {
  @override
  int build() => ref.read(ledgerRepositoryProvider).loadBudgetCents();

  Future<void> setBudget(int cents) async {
    state = cents < 0 ? 0 : cents;
    await ref.read(ledgerRepositoryProvider).saveBudgetCents(state);
  }
}

// ── 时间范围统计（首页 C-51 卡片）──────────────────────────────

/// 时间范围档（首页记账卡切换）。
enum LedgerRange {
  day('本日'),
  week('本周'),
  month('本月'),
  year('本年');

  const LedgerRange(this.label);

  final String label;
}

/// 范围起点（含）。周一为一周起点（与系统日历一致）。
DateTime ledgerRangeStart(LedgerRange range, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  return switch (range) {
    LedgerRange.day => today,
    LedgerRange.week => today.subtract(Duration(days: today.weekday - 1)),
    LedgerRange.month => DateTime(now.year, now.month),
    LedgerRange.year => DateTime(now.year),
  };
}

/// 指定范围内的支出合计（分；转账不计）。
int computeExpenseInRange(
  List<LedgerEntry> entries,
  LedgerRange range,
  DateTime now,
) {
  final DateTime start = ledgerRangeStart(range, now);
  int sum = 0;
  for (final LedgerEntry e in entries) {
    if (!e.isExpense) continue;
    if (e.date.isBefore(start)) continue;
    sum += e.amountCents;
  }
  return sum;
}

/// 首页记账卡数据快照。
class LedgerHomeCardData {
  const LedgerHomeCardData({
    required this.budgetCents,
    required this.monthExpenseCents,
    required this.monthIncomeCents,
    required this.expenseByRange,
  });

  /// 月度预算（分；0 = 未设置）。
  final int budgetCents;

  final int monthExpenseCents;
  final int monthIncomeCents;

  /// 各时间范围支出合计（分）。
  final Map<LedgerRange, int> expenseByRange;

  /// 剩余 = 预算 + 收入 − 支出（用户口径）。
  int get remainingCents =>
      budgetCents + monthIncomeCents - monthExpenseCents;

  /// 额度基数 = 预算 + 收入（用于圆环比例）。
  int get quotaCents => budgetCents + monthIncomeCents;

  /// 剩余占比（0..1；无额度时为 0）。
  double get remainingRatio {
    final int quota = quotaCents;
    if (quota <= 0) return 0.0;
    return (remainingCents / quota).clamp(0.0, 1.0);
  }

  /// 本月已用比例（0..1；无额度时为 0）。
  double get usedRatio => 1.0 - remainingRatio;
}

/// 首页 C-51 记账卡数据（预算 + 本月收支 + 四档支出）。
final ledgerHomeCardProvider = Provider<LedgerHomeCardData>((ref) {
  final List<LedgerEntry> entries =
      ref.watch(ledgerEntriesProvider).value ?? const <LedgerEntry>[];
  final int budget = ref.watch(ledgerBudgetProvider);
  final DateTime now = DateTime.now();
  final LedgerMonthStats month = computeMonthStats(
    entries: entries,
    categories: const <LedgerCategory>[],
    month: DateTime(now.year, now.month),
  );
  return LedgerHomeCardData(
    budgetCents: budget,
    monthExpenseCents: month.expenseCents,
    monthIncomeCents: month.incomeCents,
    expenseByRange: <LedgerRange, int>{
      for (final LedgerRange r in LedgerRange.values)
        r: computeExpenseInRange(entries, r, now),
    },
  );
});

// ── 月度统计 / 分组（纯函数，可单测）────────────────────────────

/// 单分类统计（金额降序）。
class LedgerCategoryStat {
  const LedgerCategoryStat({
    required this.categoryId,
    required this.name,
    required this.colorValue,
    required this.cents,
    required this.ratio,
  });

  final String categoryId;
  final String name;
  final int colorValue;

  /// 该类累计金额（分，恒正）。
  final int cents;

  /// 占同类型总额比例（0..1）。
  final double ratio;
}

/// 月度收支汇总。
class LedgerMonthStats {
  const LedgerMonthStats({
    required this.expenseCents,
    required this.incomeCents,
    required this.expenseCount,
    required this.incomeCount,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });

  final int expenseCents;
  final int incomeCents;
  final int expenseCount;
  final int incomeCount;
  final List<LedgerCategoryStat> expenseByCategory;
  final List<LedgerCategoryStat> incomeByCategory;

  /// 结余（收入 - 支出，可为负）。
  int get balanceCents => incomeCents - expenseCents;

  /// 该月无任何收支记录。
  bool get isEmpty => expenseCount == 0 && incomeCount == 0;
}

/// 月度统计（转账不计入收支，仅调整账户余额）。
LedgerMonthStats computeMonthStats({
  required List<LedgerEntry> entries,
  required List<LedgerCategory> categories,
  required DateTime month,
}) {
  int expense = 0;
  int income = 0;
  int expenseCount = 0;
  int incomeCount = 0;
  final Map<String, int> expenseMap = <String, int>{};
  final Map<String, int> incomeMap = <String, int>{};

  for (final LedgerEntry e in entries) {
    if (e.date.year != month.year || e.date.month != month.month) continue;
    if (e.isTransfer) continue;
    if (e.isExpense) {
      expense += e.amountCents;
      expenseCount++;
      expenseMap[e.categoryId] = (expenseMap[e.categoryId] ?? 0) + e.amountCents;
    } else {
      income += e.amountCents;
      incomeCount++;
      incomeMap[e.categoryId] = (incomeMap[e.categoryId] ?? 0) + e.amountCents;
    }
  }

  return LedgerMonthStats(
    expenseCents: expense,
    incomeCents: income,
    expenseCount: expenseCount,
    incomeCount: incomeCount,
    expenseByCategory: _toStats(expenseMap, expense, categories),
    incomeByCategory: _toStats(incomeMap, income, categories),
  );
}

List<LedgerCategoryStat> _toStats(
  Map<String, int> map,
  int total,
  List<LedgerCategory> categories,
) {
  final Map<String, LedgerCategory> byId = <String, LedgerCategory>{
    for (final LedgerCategory c in categories) c.id: c,
  };
  // 二级分类归并到一级（统计口径按一级展示；明细仍保留在账目 categoryId 中）。
  final Map<String, int> rolled = <String, int>{};
  map.forEach((String id, int cents) {
    final LedgerCategory? cat = byId[id];
    final String topId = (cat != null && cat.parentId.isNotEmpty)
        ? cat.parentId
        : id;
    rolled[topId] = (rolled[topId] ?? 0) + cents;
  });

  final List<LedgerCategoryStat> out = <LedgerCategoryStat>[];
  rolled.forEach((String id, int cents) {
    final LedgerCategory? cat = byId[id];
    out.add(
      LedgerCategoryStat(
        categoryId: id,
        name: cat?.name ?? '未分类',
        colorValue: cat?.colorValue ?? 0xFF9AA0A6,
        cents: cents,
        ratio: total > 0 ? cents / total : 0.0,
      ),
    );
  });
  out.sort((LedgerCategoryStat a, LedgerCategoryStat b) {
    return b.cents.compareTo(a.cents);
  });
  return out;
}

/// 按日分组（组内按时间倒序；组按日期倒序）。
class LedgerDayGroup {
  const LedgerDayGroup({
    required this.day,
    required this.entries,
    required this.expenseCents,
    required this.incomeCents,
  });

  /// 该组日期（仅日期部分）。
  final DateTime day;
  final List<LedgerEntry> entries;
  final int expenseCents;
  final int incomeCents;

  /// 分组标题（今天 / 昨天 / M月D日 周X）。
  String label(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime target = DateTime(day.year, day.month, day.day);
    final int diff = today.difference(target).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff == -1) return '明天';
    const List<String> week = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '${day.month}月${day.day}日 周${week[day.weekday - 1]}';
  }
}

/// 按日分组（输入已按月份过滤的账目）。
List<LedgerDayGroup> groupEntriesByDay(List<LedgerEntry> entries) {
  final Map<String, List<LedgerEntry>> buckets = <String, List<LedgerEntry>>{};
  for (final LedgerEntry e in entries) {
    final String key =
        '${e.date.year}-${e.date.month}-${e.date.day}';
    (buckets[key] ??= <LedgerEntry>[]).add(e);
  }
  final List<LedgerDayGroup> groups = <LedgerDayGroup>[];
  buckets.forEach((String _, List<LedgerEntry> list) {
    list.sort((LedgerEntry a, LedgerEntry b) => b.date.compareTo(a.date));
    int expense = 0;
    int income = 0;
    for (final LedgerEntry e in list) {
      if (e.isExpense) {
        expense += e.amountCents;
      } else if (e.isIncome) {
        income += e.amountCents;
      }
    }
    groups.add(
      LedgerDayGroup(
        day: DateTime(list.first.date.year, list.first.date.month, list.first.date.day),
        entries: list,
        expenseCents: expense,
        incomeCents: income,
      ),
    );
  });
  groups.sort((LedgerDayGroup a, LedgerDayGroup b) => b.day.compareTo(a.day));
  return groups;
}

// ── 派生视图 ──────────────────────────────────────────────────

/// 当月账目（按时间倒序）。
final ledgerMonthEntriesProvider = Provider<List<LedgerEntry>>((ref) {
  final List<LedgerEntry> all =
      ref.watch(ledgerEntriesProvider).value ?? const <LedgerEntry>[];
  final DateTime month = ref.watch(ledgerMonthProvider);
  final List<LedgerEntry> out = <LedgerEntry>[
    for (final LedgerEntry e in all)
      if (e.date.year == month.year && e.date.month == month.month) e,
  ]..sort((LedgerEntry a, LedgerEntry b) => b.date.compareTo(a.date));
  return out;
});

/// 当月按日分组（一级页主体）。
final ledgerDayGroupsProvider = Provider<List<LedgerDayGroup>>((ref) {
  return groupEntriesByDay(ref.watch(ledgerMonthEntriesProvider));
});

/// 当月收支汇总（一级页顶部 + 统计页）。
final ledgerMonthStatsProvider = Provider<LedgerMonthStats>((ref) {
  final List<LedgerEntry> all =
      ref.watch(ledgerEntriesProvider).value ?? const <LedgerEntry>[];
  final List<LedgerCategory> categories =
      ref.watch(ledgerCategoriesProvider).value ?? const <LedgerCategory>[];
  final DateTime month = ref.watch(ledgerMonthProvider);
  return computeMonthStats(
    entries: all,
    categories: categories,
    month: month,
  );
});
