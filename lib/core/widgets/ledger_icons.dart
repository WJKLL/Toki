// lib/core/widgets/ledger_icons.dart
// 编号：C-45 记账图标集（v1.50.0，P-20 记账，自绘矢量图标）
// 说明：flutter_miuix 内置图标（basic 7 个 + extended 124 个）不含钱包/货币/
//   餐饮/交通/医疗等记账语义，故按 miuix 面性图标语言自绘一套：
//   - 统一 24×24 视口、纯几何填充路径（与内置图标同管线 MiuixVectorIcon +
//     MiuixVectorIconPainter，经 MiuixIcon 统一 tint 染色 / FittedBox 缩放）；
//   - 主体控制在 16×16 居中区，笔画重量一致，24px 下清晰可辨；
//   - 分类 id → 图标（与 LedgerCategory.id 一一对应；未知名回退「其他」）。
// 用法：MiuixIcon(vector: ledgerIcon(cat.id), size: 20, tint: Color(cat.colorValue))
// 功耗：图标为 const 视口 + 惰性构建缓存（MiuixVectorIcon 本身不可变，
//   painter shouldRepaint 按 identical 判等 → 静止零重绘）。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 统一视口（正方形；FittedBox 等比缩放到目标 size）。
const Size _kViewport = Size(24, 24);

// ── 构造辅助 ──────────────────────────────────────────────────

/// 填充路径。
MiuixVectorPath _fill(Path Function() build) => MiuixVectorPath(build: build);

/// 描边路径（圆头，视口坐标下的线宽）。
MiuixVectorPath _stroke(Path Function() build, {double width = 1.9}) =>
    MiuixVectorPath(
      build: build,
      style: PaintingStyle.stroke,
      strokeWidth: width,
      strokeCap: StrokeCap.round,
    );

/// 圆角矩形。
Path _rr(double l, double t, double r, double b, double radius) => Path()
  ..addRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(l, t, r, b), Radius.circular(radius)),
  );

/// 椭圆。
Path _oval(double l, double t, double r, double b) =>
    Path()..addOval(Rect.fromLTRB(l, t, r, b));

/// 圆。
Path _circle(double cx, double cy, double radius) =>
    _oval(cx - radius, cy - radius, cx + radius, cy + radius);

/// 偶数-奇数填充（用于挖洞：外轮廓 + 内部形状）。
Path _cut(void Function(Path p) add) {
  final Path p = Path()..fillType = PathFillType.evenOdd;
  add(p);
  return p;
}

/// 组装图标。
MiuixVectorIcon _icon(String name, List<MiuixVectorPath> paths) =>
    MiuixVectorIcon(
      name: name,
      viewport: _kViewport,
      intrinsicSize: _kViewport,
      paths: paths,
    );

// ── 支出一级 ──────────────────────────────────────────────────

/// 餐饮：碗 + 筷子。
final MiuixVectorIcon _food = _icon('ledger.food', <MiuixVectorPath>[
  _fill(
    () => Path()
      ..moveTo(3.4, 11)
      ..lineTo(20.6, 11)
      ..arcTo(const Rect.fromLTRB(3.4, 4.4, 20.6, 17.6), 0, math.pi, false)
      ..close(),
  ),
  _fill(
    () => Path()
      ..moveTo(14.2, 2.6)
      ..lineTo(15.8, 3.1)
      ..lineTo(10.6, 9.8)
      ..lineTo(9.0, 9.3)
      ..close(),
  ),
  _fill(
    () => Path()
      ..moveTo(17.4, 3.2)
      ..lineTo(19.0, 3.7)
      ..lineTo(13.8, 10.4)
      ..lineTo(12.2, 9.9)
      ..close(),
  ),
]);

/// 交通：小汽车（车身 + 车顶 + 双轮）。
final MiuixVectorIcon _transport = _icon(
  'ledger.transport',
  <MiuixVectorPath>[
    _fill(() => _rr(3, 9.6, 21, 16.4, 3)),
    _fill(
      () => Path()
        ..moveTo(7.2, 9.6)
        ..lineTo(9.4, 5.6)
        ..lineTo(14.6, 5.6)
        ..lineTo(16.8, 9.6)
        ..close(),
    ),
    _fill(() => _circle(7.6, 17.2, 2.2)),
    _fill(() => _circle(16.4, 17.2, 2.2)),
  ],
);

/// 购物：购物袋（袋身 + 提手）。
final MiuixVectorIcon _shopping = _icon('ledger.shopping', <MiuixVectorPath>[
  _fill(
    () => Path()
      ..moveTo(4.6, 8)
      ..lineTo(19.4, 8)
      ..lineTo(18.2, 19.4)
      ..lineTo(5.8, 19.4)
      ..close(),
  ),
  _stroke(
    () => Path()
      ..moveTo(9, 8.4)
      ..arcTo(const Rect.fromLTRB(9, 3.4, 15, 9.4), math.pi, math.pi, false),
  ),
]);

/// 居住：房子（屋顶 + 屋身 + 门洞）。
final MiuixVectorIcon _housing = _icon('ledger.housing', <MiuixVectorPath>[
  _fill(
    () => Path()
      ..moveTo(12, 3.4)
      ..lineTo(21, 11)
      ..lineTo(19.4, 12.8)
      ..lineTo(12, 6.2)
      ..lineTo(4.6, 12.8)
      ..lineTo(3, 11)
      ..close(),
  ),
  _fill(
    () => _cut((Path p) {
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(5.6, 11, 18.4, 20.6),
          const Radius.circular(1.6),
        ),
      );
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(10.2, 15.4, 13.8, 20.6),
          const Radius.circular(1.2),
        ),
      );
    }),
  ),
]);

/// 娱乐：音符（符头 + 符杆 + 符尾）。
final MiuixVectorIcon _entertainment = _icon(
  'ledger.entertainment',
  <MiuixVectorPath>[
    _fill(() => _oval(5.4, 14.4, 11.4, 18.8)),
    _fill(
      () => Path()
        ..moveTo(10.4, 16.6)
        ..lineTo(10.4, 5.4)
        ..lineTo(11.6, 5.4)
        ..lineTo(11.6, 16.6)
        ..close(),
    ),
    _fill(
      () => Path()
        ..moveTo(11.6, 5.4)
        ..lineTo(18.6, 7.8)
        ..lineTo(18.6, 11.4)
        ..lineTo(11.6, 9.0)
        ..close(),
    ),
  ],
);

/// 医疗：十字。
final MiuixVectorIcon _medical = _icon('ledger.medical', <MiuixVectorPath>[
  _fill(() => _rr(9.8, 4.4, 14.2, 19.6, 1.6)),
  _fill(() => _rr(4.4, 9.8, 19.6, 14.2, 1.6)),
]);

/// 学习：书本（封皮 + 文字线）。
final MiuixVectorIcon _education = _icon('ledger.education', <MiuixVectorPath>[
  _fill(
    () => _cut((Path p) {
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(4.4, 4.6, 19.6, 19.4),
          const Radius.circular(2),
        ),
      );
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(7.4, 8, 16.6, 9.6),
          const Radius.circular(0.8),
        ),
      );
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(7.4, 11.8, 16.6, 13.4),
          const Radius.circular(0.8),
        ),
      );
    }),
  ),
]);

/// 通讯：手机（外框 + 屏幕）。
final MiuixVectorIcon _communication = _icon(
  'ledger.communication',
  <MiuixVectorPath>[
    _fill(
      () => _cut((Path p) {
        p.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(6.4, 2.6, 17.6, 21.4),
            const Radius.circular(2.6),
          ),
        );
        p.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(8, 5.2, 16, 17.6),
            const Radius.circular(1.2),
          ),
        );
      }),
    ),
  ],
);

/// 服饰：T恤。
final MiuixVectorIcon _clothing = _icon('ledger.clothing', <MiuixVectorPath>[
  _fill(
    () => Path()
      ..moveTo(9, 3.6)
      ..lineTo(5.2, 5.4)
      ..lineTo(2.6, 10.4)
      ..lineTo(6.2, 12)
      ..lineTo(6.2, 20.4)
      ..lineTo(17.8, 20.4)
      ..lineTo(17.8, 12)
      ..lineTo(21.4, 10.4)
      ..lineTo(18.8, 5.4)
      ..lineTo(15, 3.6)
      ..quadraticBezierTo(12, 6.4, 9, 3.6)
      ..close(),
  ),
]);

/// 人情：礼物盒（盒盖 + 盒身 + 蝴蝶结）。
final MiuixVectorIcon _social = _icon('ledger.social', <MiuixVectorPath>[
  _fill(() => _rr(3.2, 6.6, 20.8, 10.6, 1.4)),
  _fill(() => _rr(4.6, 10.6, 19.4, 19.8, 1.4)),
  _fill(() => _circle(9.6, 5, 2.1)),
  _fill(() => _circle(14.4, 5, 2.1)),
]);

/// 数码：显示器（屏框 + 支架 + 底座）。
final MiuixVectorIcon _digital = _icon('ledger.digital', <MiuixVectorPath>[
  _fill(
    () => _cut((Path p) {
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(2.6, 4.2, 21.4, 16.6),
          const Radius.circular(2),
        ),
      );
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(4.6, 6.2, 19.4, 14.6),
          const Radius.circular(1),
        ),
      );
    }),
  ),
  _fill(() => _rr(9.6, 16.6, 14.4, 19, 0.6)),
  _fill(() => _rr(6.6, 19, 17.4, 20.6, 0.8)),
]);

/// 其他：三个点。
final MiuixVectorIcon _other = _icon('ledger.other', <MiuixVectorPath>[
  _fill(() => _circle(6.4, 12, 2.2)),
  _fill(() => _circle(12, 12, 2.2)),
  _fill(() => _circle(17.6, 12, 2.2)),
]);

// ── 收入 ──────────────────────────────────────────────────────

/// 工资：纸币。
final MiuixVectorIcon _salary = _icon('ledger.salary', <MiuixVectorPath>[
  _fill(
    () => _cut((Path p) {
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(2.6, 6.4, 21.4, 17.6),
          const Radius.circular(2),
        ),
      );
      p.addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 3.2));
    }),
  ),
]);

/// 奖金：奖杯（杯身 + 杯柄 + 底座）。
final MiuixVectorIcon _bonus = _icon('ledger.bonus', <MiuixVectorPath>[
  _fill(
    () => Path()
      ..moveTo(7, 4.2)
      ..lineTo(17, 4.2)
      ..lineTo(15.8, 12)
      ..quadraticBezierTo(12, 14.6, 8.2, 12)
      ..close(),
  ),
  _stroke(
    () => Path()
      ..moveTo(7.4, 5.8)
      ..arcTo(const Rect.fromLTRB(3.2, 5.8, 7.6, 10.6), math.pi * 1.5, math.pi, false),
    width: 1.6,
  ),
  _stroke(
    () => Path()
      ..moveTo(16.6, 5.8)
      ..arcTo(const Rect.fromLTRB(16.4, 5.8, 20.8, 10.6), math.pi * 1.5, -math.pi, false),
    width: 1.6,
  ),
  _fill(() => _rr(9.6, 13.4, 14.4, 15.6, 0.6)),
  _fill(() => _rr(6.8, 15.6, 17.2, 19.4, 1)),
]);

/// 理财：上升折线 + 箭头。
final MiuixVectorIcon _investment = _icon(
  'ledger.investment',
  <MiuixVectorPath>[
    _stroke(
      () => Path()
        ..moveTo(4, 18)
        ..lineTo(9.4, 12.6)
        ..lineTo(13.4, 15.6)
        ..lineTo(20, 8.4),
      width: 2,
    ),
    _stroke(
      () => Path()
        ..moveTo(14.6, 8.4)
        ..lineTo(20, 8.4)
        ..lineTo(20, 13.8),
      width: 2,
    ),
  ],
);

/// 红包：封套 + 翻盖弧。
final MiuixVectorIcon _redpacket = _icon('ledger.redpacket', <MiuixVectorPath>[
  _fill(
    () => _cut((Path p) {
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(4.6, 4, 19.4, 20.4),
          const Radius.circular(2.4),
        ),
      );
      p.addOval(const Rect.fromLTRB(4.6, 6.4, 19.4, 13.6));
    }),
  ),
]);

// ── 购物二级 ──────────────────────────────────────────────────

/// 电脑：同「数码」显示器。
final MiuixVectorIcon _shopComputer = _icon(
  'ledger.shop.computer',
  _digital.paths,
);

/// 手机：同「通讯」。
final MiuixVectorIcon _shopPhone = _icon(
  'ledger.shop.phone',
  _communication.paths,
);

/// 平板：竖屏设备（外框 + 屏幕）。
final MiuixVectorIcon _shopTablet = _icon('ledger.shop.tablet', <MiuixVectorPath>[
  _fill(
    () => _cut((Path p) {
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(5.4, 2.8, 18.6, 21.2),
          const Radius.circular(2.4),
        ),
      );
      p.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(7, 5, 17, 18.4),
          const Radius.circular(1),
        ),
      );
    }),
  ),
]);

/// 外设：鼠标（椭圆 + 滚轮缝）。
final MiuixVectorIcon _shopPeripheral = _icon(
  'ledger.shop.peripheral',
  <MiuixVectorPath>[
    _fill(
      () => _cut((Path p) {
        p.addOval(const Rect.fromLTRB(7, 4, 17, 20.4));
        p.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(11.2, 6.6, 12.8, 11.2),
            const Radius.circular(0.8),
          ),
        );
      }),
    ),
  ],
);

/// 家电：冰箱（门缝 + 把手）。
final MiuixVectorIcon _shopAppliance = _icon(
  'ledger.shop.appliance',
  <MiuixVectorPath>[
    _fill(
      () => _cut((Path p) {
        p.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(6.4, 3, 17.6, 21),
            const Radius.circular(2),
          ),
        );
        p.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(6.4, 9.4, 17.6, 10.6),
            const Radius.circular(0.5),
          ),
        );
      }),
    ),
    _fill(() => _rr(14.4, 5.4, 15.6, 8.2, 0.5)),
  ],
);

/// 家居：沙发（靠背 + 座 + 扶手 + 脚）。
final MiuixVectorIcon _shopHome = _icon('ledger.shop.home', <MiuixVectorPath>[
  _fill(() => _rr(4.6, 7.4, 19.4, 14.2, 1.6)),
  _fill(() => _rr(4.6, 13, 19.4, 18, 1.4)),
  _fill(() => _rr(2.6, 9.6, 5.4, 18, 1.4)),
  _fill(() => _rr(18.6, 9.6, 21.4, 18, 1.4)),
  _fill(() => _rr(5.6, 18, 7.2, 20.2, 0.5)),
  _fill(() => _rr(16.8, 18, 18.4, 20.2, 0.5)),
]);

/// 日用：瓶（盖 + 颈 + 身）。
final MiuixVectorIcon _shopDaily = _icon('ledger.shop.daily', <MiuixVectorPath>[
  _fill(() => _rr(9.4, 3, 14.6, 5.4, 0.8)),
  _fill(() => _rr(10.4, 5.4, 13.6, 8.2, 0.6)),
  _fill(() => _rr(7.4, 8.2, 16.6, 21, 2.4)),
]);

/// 美妆：口红（管身 + 斜切膏体）。
final MiuixVectorIcon _shopBeauty = _icon('ledger.shop.beauty', <MiuixVectorPath>[
  _fill(() => _rr(9.4, 10.4, 14.6, 20.6, 0.8)),
  _fill(
    () => Path()
      ..moveTo(9.4, 10.4)
      ..lineTo(14.6, 10.4)
      ..lineTo(14.6, 4.2)
      ..lineTo(11.2, 6.8)
      ..close(),
  ),
]);

/// 食品：苹果（果身 + 梗 + 叶）。
final MiuixVectorIcon _shopFood = _icon('ledger.shop.food', <MiuixVectorPath>[
  _fill(() => _circle(12, 13.8, 6.8)),
  _fill(
    () => Path()
      ..moveTo(11.3, 7.6)
      ..lineTo(12.7, 7.6)
      ..lineTo(13.1, 4.2)
      ..lineTo(11.7, 4.2)
      ..close(),
  ),
  _fill(
    () => Path()
      ..moveTo(13, 5.6)
      ..quadraticBezierTo(16.6, 3.4, 17.8, 6)
      ..quadraticBezierTo(14.6, 7.4, 13, 5.6)
      ..close(),
  ),
]);

/// 服饰（二级）：同「服饰」T恤。
final MiuixVectorIcon _shopClothing = _icon(
  'ledger.shop.clothing',
  _clothing.paths,
);

/// 图书：同「学习」书本。
final MiuixVectorIcon _shopBook = _icon('ledger.shop.book', _education.paths);

/// 玩具：积木（两块 + 凸点）。
final MiuixVectorIcon _shopToy = _icon('ledger.shop.toy', <MiuixVectorPath>[
  _fill(() => _rr(3.4, 12, 11.2, 19.8, 1)),
  _fill(() => _rr(12.8, 12, 20.6, 19.8, 1)),
  _fill(() => _circle(7.3, 10.6, 1.6)),
  _fill(() => _circle(16.7, 10.6, 1.6)),
]);

/// 其他（二级）：同「其他」三点。
final MiuixVectorIcon _shopOther = _icon('ledger.shop.other', _other.paths);

// ── 分类 id → 图标 ────────────────────────────────────────────

/// 分类 id → 图标映射（与 defaultLedgerCategories() 的 id 一一对应）。
final Map<String, MiuixVectorIcon> _kLedgerIcons = <String, MiuixVectorIcon>{
  // 支出一级
  'food': _food,
  'transport': _transport,
  'shopping': _shopping,
  'housing': _housing,
  'entertainment': _entertainment,
  'medical': _medical,
  'education': _education,
  'communication': _communication,
  'clothing': _clothing,
  'social': _social,
  'digital': _digital,
  'other_expense': _other,
  // 收入
  'salary': _salary,
  'bonus': _bonus,
  'investment': _investment,
  'redpacket': _redpacket,
  'other_income': _other,
  // 购物二级
  'shopping_computer': _shopComputer,
  'shopping_phone': _shopPhone,
  'shopping_tablet': _shopTablet,
  'shopping_peripheral': _shopPeripheral,
  'shopping_appliance': _shopAppliance,
  'shopping_home': _shopHome,
  'shopping_daily': _shopDaily,
  'shopping_beauty': _shopBeauty,
  'shopping_food': _shopFood,
  'shopping_clothing': _shopClothing,
  'shopping_book': _shopBook,
  'shopping_toy': _shopToy,
  'shopping_other': _shopOther,
};

/// 按分类 id 取图标（未知名回退「其他」，绝不抛出）。
MiuixVectorIcon ledgerIcon(String categoryId) =>
    _kLedgerIcons[categoryId] ?? _other;
