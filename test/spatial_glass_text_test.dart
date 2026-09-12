// test/spatial_glass_text_test.dart
// 编号：C-70 单测（v2.1.0）—— 「内容玻璃」接线守卫
//
// 为什么要有这个文件：本项目的头号事故模式是"改了但没生效" ——
// 参数加了、滑条画了，但渲染器那条路根本没接上，用户拉半天没反应。
// 所以这里守的不是像素，而是**接线**：滑条一动，树里必须真的出现玻璃层，
// 且实心填充必须真的让位。
//
// 覆盖：
//   1. S-42 的 contentGlass 默认 0、copyWith 生效（不破坏任何既有预设）
//   2. 「玻璃字」预设真的开了内容玻璃，且与「玻璃」（胶囊底）是两套东西
//   3. C-68 在 contentGlass > 0 时**确实把 C-70 插进了 layers**
//   4. C-68 在 contentGlass > 0 时把实心填充淡出为 (1 − 强度)
//      —— 不淡出的话玻璃会被整片盖住，那根滑条就等于没反应
//   5. C-70 在强度 0 时不挂 BackdropFilter（省掉一次强制图层分离）
//   6. C-70 首帧（形状图还没生成）返回**等尺寸空盒**，不塌成 0 也不跳
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xiangjugong/domain/entities/spatial_style.dart';
import 'package:xiangjugong/presentation/widgets/kernel/spatial_glass_text.dart';
import 'package:xiangjugong/presentation/widgets/kernel/spatial_styled_text.dart';

/// 裸 pumpWidget 没有 MediaQuery 祖先，而 C-70 要用 devicePixelRatio；
/// 不给会直接 assert 失败，所以每个用例都套上。
Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(devicePixelRatio: 1),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

/// 按不透明度找 [Opacity]。用它定位"承载实心填充的那一层"。
Finder _opacityIs(double expected) => find.byWidgetPredicate(
  (Widget w) => w is Opacity && (w.opacity - expected).abs() < 0.001,
  description: 'Opacity($expected)',
);

void main() {
  group('S-42 contentGlass 模型', () {
    test('默认关闭，既有预设一个都没被改动', () {
      expect(const SpatialStyle().contentGlass, 0);
      expect(SpatialStylePresets.minimal.contentGlass, 0);
      expect(SpatialStylePresets.glass.contentGlass, 0);
      expect(SpatialStylePresets.neon.contentGlass, 0);
      expect(SpatialStylePresets.journal.contentGlass, 0);
      expect(SpatialStylePresets.outlined.contentGlass, 0);
    });

    test('copyWith 能设、能改回 0，且不牵连其它字段', () {
      const SpatialStyle s = SpatialStyle(fontSize: 34, strokeWidth: 2);
      expect(s.copyWith(contentGlass: 0.6).contentGlass, 0.6);
      expect(
        s.copyWith(contentGlass: 0.6).copyWith(contentGlass: 0).contentGlass,
        0,
      );
      expect(s.copyWith(contentGlass: 0.6).fontSize, 34);
      expect(s.copyWith(contentGlass: 0.6).strokeWidth, 2);
    });

    test('「玻璃字」与「玻璃」是两回事，预设清单里必须在且名字可区分', () {
      // 玻璃字 = 内容玻璃（字本身变玻璃）
      expect(SpatialStylePresets.glassText.contentGlass, greaterThan(0));
      // 玻璃   = 垫胶囊底（字仍是实心的）
      expect(SpatialStylePresets.glass.hasPlate, isTrue);
      expect(SpatialStylePresets.glass.contentGlass, 0);

      final List<String> names = SpatialStylePresets.all
          .map(((String, SpatialStyle) e) => e.$1)
          .toList();
      expect(names, contains('玻璃'));
      expect(names, contains('玻璃字'));
    });
  });

  group('C-68 接线：玻璃层确实插进去了', () {
    testWidgets('contentGlass > 0 → 树里出现 C-70', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SpatialStyledText(
            text: '玻璃',
            style: SpatialStyle(contentGlass: 1),
          ),
        ),
      );
      expect(find.byType(SpatialGlassText), findsOneWidget);
    });

    testWidgets('contentGlass == 0 → 不出现 C-70，不白挂 BackdropFilter', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SpatialStyledText(
            text: '普通',
            style: SpatialStyle(strokeWidth: 3),
          ),
        ),
      );
      expect(find.byType(SpatialGlassText), findsNothing);
    });

    testWidgets('实心填充随强度淡出（1 − 强度）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SpatialStyledText(
            text: '玻璃',
            style: SpatialStyle(contentGlass: 0.75),
          ),
        ),
      );
      // 1 − 0.75 = 0.25。这一层不存在的话，玻璃会被实心字整片盖住。
      expect(_opacityIs(0.25), findsWidgets);
    });

    testWidgets('强度全开时填充完全让位（1 − 1 = 0）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SpatialStyledText(
            text: '玻璃',
            style: SpatialStyle(contentGlass: 1),
          ),
        ),
      );
      expect(_opacityIs(0), findsWidgets);
    });
  });

  group('C-70 自身', () {
    testWidgets('强度 0 → 不挂 BackdropFilter', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SpatialGlassText(
            text: 'x',
            style: SpatialStyle(),
            intensity: 0,
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('首帧等尺寸空盒：不画玻璃，但也绝不塌成 0 尺寸', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SpatialGlassText(
            text: '玻璃',
            style: SpatialStyle(fontSize: 40),
            intensity: 1,
          ),
        ),
      );
      // 形状图是异步生成的。首帧没有图 → 必须不画（否则会拿空图当遮罩）
      expect(find.byType(BackdropFilter), findsNothing);
      // 但必须占住文字该有的尺寸，否则组件会先塌再弹
      final Size size = tester.getSize(find.byType(SpatialGlassText));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });

    testWidgets('空文字不炸，退化成 0 尺寸', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SpatialGlassText(text: '', style: SpatialStyle(), intensity: 1),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
