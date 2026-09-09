// test/glow_press_gate_test.dart
// 编号：GLOW-04 滚动期按压门控单测（v1.50.1）
// 覆盖：静止时按下照常触发按压光圈；滚动中按下不触发；
//   滚动开始立即收掉进行中的光圈（此后不再逐帧重建）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xiangjugong/core/widgets/glow_material.dart';

/// 光感层自身的 CustomPaint（GlowMaterial 内部唯一一个）。
Finder _glowPaint() => find.descendant(
  of: find.byType(GlowMaterial),
  matching: find.byType(CustomPaint),
);

/// 当前 painter 实例：按压动画逐帧 setState 会换新实例，
/// 实例相同即「本帧没有重建」，可用于判定光圈是否在跑。
/// 注：光感画在卡片**之上**，用的是 `foregroundPainter`（不是 `painter`）。
Object? _painterOf(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(_glowPaint().first);
  return paint.foregroundPainter ?? paint.painter;
}

Future<void> _pumpGlow(WidgetTester tester) async {
  await tester.pumpWidget(
    MiuixTheme(
      data: MiuixThemeData.light(),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GlowMaterial(
            interactive: true,
            // 必须有可命中的实心子级：GlowMaterial 的 Listener 是
            // HitTestBehavior.deferToChild，裸 SizedBox 不参与命中测试。
            child: ColoredBox(
              color: Color(0xFFEEEEEE),
              child: SizedBox(width: 120, height: 80),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 按下并让按压动画真正推进一帧（Ticker 首帧只记录起始时间，elapsed=0）。
Future<TestGesture> _pressAndAdvance(WidgetTester tester) async {
  final TestGesture g = await tester.startGesture(
    tester.getCenter(find.byType(GlowMaterial)),
  );
  await tester.pump(); // Ticker 记录起始时间
  await tester.pump(const Duration(milliseconds: 40)); // 光圈推进
  return g;
}

void main() {
  // 全局门控是静态状态，逐个用例显式置位并在收尾复位，避免用例间串味。
  setUp(() => GlowPressGate.scrollActive.value = false);
  tearDown(() => GlowPressGate.scrollActive.value = false);

  testWidgets('静止时按下触发按压光圈（painter 逐帧重建）', (WidgetTester tester) async {
    await _pumpGlow(tester);
    final Object? before = _painterOf(tester);

    final TestGesture g = await _pressAndAdvance(tester);

    expect(
      identical(before, _painterOf(tester)),
      isFalse,
      reason: '按下后光圈动画应逐帧重建 painter',
    );

    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('滚动中按下不触发按压光圈（painter 不变）', (WidgetTester tester) async {
    await _pumpGlow(tester);
    final Object? before = _painterOf(tester);

    GlowPressGate.scrollActive.value = true; // 模拟滚动开始
    final TestGesture g = await _pressAndAdvance(tester);

    expect(
      identical(before, _painterOf(tester)),
      isTrue,
      reason: '滚动中按下应被门控拦下，不产生任何重建/重绘',
    );

    await g.up();
    await tester.pump();
  });

  testWidgets('滚动开始立即收掉进行中的光圈（此后不再逐帧重建）', (WidgetTester tester) async {
    await _pumpGlow(tester);
    final TestGesture g = await _pressAndAdvance(tester); // 光圈进行中
    final Object? during = _painterOf(tester);

    GlowPressGate.scrollActive.value = true; // 滚动开始 → 应收掉光圈
    await tester.pump();
    final Object? afterScroll = _painterOf(tester);

    expect(
      identical(during, afterScroll),
      isFalse,
      reason: '滚动开始应把光圈收掉（触发一次重建归零）',
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(
      identical(afterScroll, _painterOf(tester)),
      isTrue,
      reason: '光圈应已停止，不再有逐帧重建',
    );

    await g.up();
    await tester.pump();
  });
}
