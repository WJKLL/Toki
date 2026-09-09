// lib/domain/entities/ledger_entry.dart
// 编号：S-25 记账领域实体（v1.50.0，P-20 记账一级页）
// 说明：账目（流水）与账目类型 —— 纯领域实体，不依赖 UI/存储。
//   - 金额一律以「分」为单位的 int 存储（避免 double 累加误差；展示时转元）；
//   - 类型三态：支出 / 收入 / 转账（转账不计收支统计，仅调账户余额）；
//   - date 存完整时刻（列表按日分组、统计按月聚合）；
//   - categoryId 关联 LedgerCategory（转账为空串）。

/// 账目类型。
enum LedgerKind {
  expense('支出'),
  income('收入'),
  transfer('转账');

  const LedgerKind(this.label);

  /// 中文标签。
  final String label;
}

/// 金额格式化（分 → 元，两位小数 + 千分位，不带正负号）。
String formatCents(int cents) {
  final bool neg = cents < 0;
  final int abs = cents.abs();
  final String yuan = _group((abs ~/ 100).toString());
  final String frac = (abs % 100).toString().padLeft(2, '0');
  return '${neg ? '-' : ''}$yuan.$frac';
}

/// 带符号金额（支出前置「-」、收入前置「+」、转账不带符号）。
String formatSignedCents(LedgerKind kind, int cents) {
  final String v = formatCents(cents);
  return switch (kind) {
    LedgerKind.expense => '-$v',
    LedgerKind.income => '+$v',
    LedgerKind.transfer => v,
  };
}

/// 千分位分组。
String _group(String digits) {
  if (digits.length <= 3) return digits;
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

/// 一条账目（流水）。
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.accountId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final LedgerKind kind;

  /// 金额（分，恒为正；方向由 [kind] 决定）。
  final int amountCents;

  /// 分类 id（转账为空串）。
  final String categoryId;

  /// 记账时刻（列表按日分组、统计按月聚合）。
  final DateTime date;

  /// 备注。
  final String note;

  /// 账户 id（预留；一期统一记入默认账户）。
  final String? accountId;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isExpense => kind == LedgerKind.expense;
  bool get isIncome => kind == LedgerKind.income;
  bool get isTransfer => kind == LedgerKind.transfer;

  /// 计入收支统计的带符号金额（支出为负、收入为正、转账为 0）。
  int get signedCents => switch (kind) {
    LedgerKind.expense => -amountCents,
    LedgerKind.income => amountCents,
    LedgerKind.transfer => 0,
  };

  LedgerEntry copyWith({
    LedgerKind? kind,
    int? amountCents,
    String? categoryId,
    DateTime? date,
    String? note,
    String? accountId,
    DateTime? updatedAt,
  }) {
    return LedgerEntry(
      id: id,
      kind: kind ?? this.kind,
      amountCents: amountCents ?? this.amountCents,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'amountCents': amountCents,
    'categoryId': categoryId,
    'date': date.millisecondsSinceEpoch,
    'note': note,
    'accountId': accountId,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      id: json['id'] as String? ?? '',
      kind: _kindOf(json['kind']),
      amountCents: (json['amountCents'] as int?)?.abs() ?? 0,
      categoryId: json['categoryId'] as String? ?? '',
      date: _dateOf(json['date']),
      note: json['note'] as String? ?? '',
      accountId: json['accountId'] as String?,
      createdAt: _dateOf(json['createdAt']),
      updatedAt: _dateOf(json['updatedAt']),
    );
  }

  static LedgerKind _kindOf(Object? raw) {
    for (final LedgerKind k in LedgerKind.values) {
      if (k.name == raw) return k;
    }
    return LedgerKind.expense;
  }

  static DateTime _dateOf(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }
}
