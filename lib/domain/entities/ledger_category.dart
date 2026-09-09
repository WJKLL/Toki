// lib/domain/entities/ledger_category.dart
// 编号：S-25 记账分类领域实体（v1.50.0，P-20 记账一级页）
// 说明：账目分类（一级 + 二级）与内置预设分类表 —— 纯领域实体，不依赖 UI/存储。
//   - kind 区分支出/收入分类（转账无分类）；
//   - parentId 为空 = 一级分类，非空 = 该分类下的二级分类（如「购物 → 电脑」）；
//   - 颜色以 ARGB int 存储（领域层不引 Flutter，UI 侧 Color(colorValue)）；
//   - builtIn=true 为内置分类（可改名/排序，但不可删除）。
// 分类体系（v1.50.0 定稿）：支出 12 个一级（购物下挂 13 个二级）+ 收入 5 个。

import 'ledger_entry.dart';

/// 账目分类。
class LedgerCategory {
  const LedgerCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.parentId = '',
    required this.colorValue,
    this.order = 0,
    this.builtIn = false,
  });

  final String id;
  final String name;

  /// 归属类型（支出分类 / 收入分类）。
  final LedgerKind kind;

  /// 上级分类 id（空 = 一级分类）。
  final String parentId;

  /// 分类色（ARGB）。
  final int colorValue;

  /// 同级排序（升序）。
  final int order;

  /// 是否内置（内置不可删除）。
  final bool builtIn;

  /// 是否一级分类。
  bool get isTop => parentId.isEmpty;

  LedgerCategory copyWith({
    String? name,
    String? parentId,
    int? colorValue,
    int? order,
  }) {
    return LedgerCategory(
      id: id,
      name: name ?? this.name,
      kind: kind,
      parentId: parentId ?? this.parentId,
      colorValue: colorValue ?? this.colorValue,
      order: order ?? this.order,
      builtIn: builtIn,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'kind': kind.name,
    'parentId': parentId,
    'colorValue': colorValue,
    'order': order,
    'builtIn': builtIn,
  };

  factory LedgerCategory.fromJson(Map<String, dynamic> json) {
    return LedgerCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: _kindOf(json['kind']),
      parentId: json['parentId'] as String? ?? '',
      colorValue: (json['colorValue'] as int?) ?? 0xFF9AA0A6,
      order: (json['order'] as int?) ?? 0,
      builtIn: json['builtIn'] as bool? ?? false,
    );
  }

  static LedgerKind _kindOf(Object? raw) {
    for (final LedgerKind k in LedgerKind.values) {
      if (k.name == raw) return k;
    }
    return LedgerKind.expense;
  }
}

// ── 内置预设分类（v1.50.0）────────────────────────────────────

/// 预设一级支出分类（id / 名称 / 颜色）。
const List<(String, String, int)> _kExpenseTop = <(String, String, int)>[
  ('food', '餐饮', 0xFFFF7A45),
  ('transport', '交通', 0xFF4A9EFF),
  ('shopping', '购物', 0xFFFF5B8D),
  ('housing', '居住', 0xFF7C8DF7),
  ('entertainment', '娱乐', 0xFFB06BFF),
  ('medical', '医疗', 0xFFFF6B6B),
  ('education', '学习', 0xFF4ECB71),
  ('communication', '通讯', 0xFF38C7D4),
  ('clothing', '服饰', 0xFFFF9F43),
  ('social', '人情', 0xFFF06292),
  ('digital', '数码', 0xFF5C7CFA),
  ('other_expense', '其他', 0xFF9AA0A6),
];

/// 「购物」下的二级分类（id 后缀 / 名称；颜色继承父级）。
const List<(String, String)> _kShoppingSub = <(String, String)>[
  ('computer', '电脑'),
  ('phone', '手机'),
  ('tablet', '平板'),
  ('peripheral', '外设'),
  ('appliance', '家电'),
  ('home', '家居'),
  ('daily', '日用'),
  ('beauty', '美妆'),
  ('food', '食品'),
  ('clothing', '服饰'),
  ('book', '图书'),
  ('toy', '玩具'),
  ('other', '其他'),
];

/// 预设收入分类。
const List<(String, String, int)> _kIncomeTop = <(String, String, int)>[
  ('salary', '工资', 0xFF4ECB71),
  ('bonus', '奖金', 0xFFFF9F43),
  ('investment', '理财', 0xFF5C7CFA),
  ('redpacket', '红包', 0xFFFF5B8D),
  ('other_income', '其他', 0xFF9AA0A6),
];

/// 内置预设分类全量（首次启动播种 / 「恢复默认分类」用）。
List<LedgerCategory> defaultLedgerCategories() {
  final List<LedgerCategory> out = <LedgerCategory>[];
  for (int i = 0; i < _kExpenseTop.length; i++) {
    final (String id, String name, int color) = _kExpenseTop[i];
    out.add(
      LedgerCategory(
        id: id,
        name: name,
        kind: LedgerKind.expense,
        colorValue: color,
        order: i,
        builtIn: true,
      ),
    );
    // 购物挂 13 个二级（颜色继承父级，保证同族视觉统一）。
    if (id == 'shopping') {
      for (int j = 0; j < _kShoppingSub.length; j++) {
        final (String sid, String sname) = _kShoppingSub[j];
        out.add(
          LedgerCategory(
            id: 'shopping_$sid',
            name: sname,
            kind: LedgerKind.expense,
            parentId: 'shopping',
            colorValue: color,
            order: j,
            builtIn: true,
          ),
        );
      }
    }
  }
  for (int i = 0; i < _kIncomeTop.length; i++) {
    final (String id, String name, int color) = _kIncomeTop[i];
    out.add(
      LedgerCategory(
        id: id,
        name: name,
        kind: LedgerKind.income,
        colorValue: color,
        order: i,
        builtIn: true,
      ),
    );
  }
  return out;
}
