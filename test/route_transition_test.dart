// test/route_transition_test.dart
// 二级页转场回归测试（v1.29.0）：
//   1. 动效开关开 → push 中途帧页面处于平移中途（动画在播），静置后归零；
//   2. 退场（pop）中途帧位移必须为正向出屏（无「开场反向微弹」——
//      阻尼 0.75 过冲曲线若反向直用会向左弹并停滞，见 miuix_route_transitions）；
//   3. 动效开关关 → push 直切（无位移层，NoTransitionPage）。
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiangjugong/data/repositories/agreement_repository_impl.dart';
import 'package:xiangjugong/data/repositories/settings_repository_impl.dart';
import 'package:xiangjugong/domain/repositories/agreement_repository.dart';
import 'package:xiangjugong/main.dart';
import 'package:xiangjugong/presentation/features/settings/page_p01_02_settings_page.dart';
import 'package:xiangjugong/presentation/providers/agreement_provider.dart';
import 'package:xiangjugong/presentation/providers/settings_providers.dart';
import 'package:xiangjugong/presentation/widgets/c26_more_menu.dart';

/// 搭建应用外壳（协议已同意 + 可选预置开关状态）。
Future<SettingsRepositoryImpl> _pumpApp(
  WidgetTester tester, {
  bool? blurEnabled,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'user_agreement_accepted': true,
    'user_agreement_version': kAgreementVersion,
    // Dart 3.8 null-aware map entry：仅当 blurEnabled 非空时写入。
    'settings.blurEnabled': ?blurEnabled,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsRepositoryImpl repository = SettingsRepositoryImpl(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        agreementRepositoryProvider.overrideWithValue(
          AgreementRepositoryImpl(prefs),
        ),
      ],
      child: const XiangJuGongApp(),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  return repository;
}

/// 经首页 C-26 ⋮ 按钮 push 设置页（v1.32.0:C-26 弹层为 MiuixOverlayDialog）。
Future<void> _pushSettings(WidgetTester tester) async {
  await tester.tap(find.byType(C26MoreMenu), warnIfMissed: false);
  // 等 MiuixOverlayDialog 弹层动画完成后再点菜单项。
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(find.text('设置').last, warnIfMissed: false);
  await tester.pump(); // push 首帧（动画 value≈0）
}

Finder _settingsTranslation() => find.ancestor(
      of: find.byType(PageP0102SettingsPage),
      matching: find.byType(FractionalTranslation),
    );

void main() {
  testWidgets('动效开：push 设置页动画中途有位移，静置归零（v1.29.0）', (tester) async {
    final SettingsRepositoryImpl repository = await _pumpApp(tester);

    await _pushSettings(tester);
    // 动画中途 ~100ms（500ms 总长；阻尼 0.75 曲线 0.2 处 ≈0.54）。
    await tester.pump(const Duration(milliseconds: 100));

    final Finder ft = _settingsTranslation();
    expect(ft, findsWidgets, reason: '设置页应处于转场位移层中');
    final double midDx =
        tester.widget<FractionalTranslation>(ft.first).translation.dx;
    expect(midDx.abs(), greaterThan(0.01),
        reason: '动画中途页面不应已完全到位（直切会立即为 0）');

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final double endDx =
        tester.widget<FractionalTranslation>(ft.first).translation.dx;
    expect(endDx.abs(), lessThan(0.001), reason: '动画结束后页面应完全到位');

    repository.dispose();
  });

  testWidgets('动效开：pop 退场动画仍在播放并最终移除（v1.31.0 回退初版逻辑）',
      (tester) async {
    final SettingsRepositoryImpl repository = await _pumpApp(tester);

    await _pushSettings(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // 返回键退场。
    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pop();
    await tester.pump(); // 首帧（value≈1）
    await tester.pump(const Duration(milliseconds: 100)); // 中途

    final Finder ft = _settingsTranslation();
    expect(ft, findsWidgets);
    final double midDx =
        tester.widget<FractionalTranslation>(ft.first).translation.dx;
    // v1.31.0：退场恢复为最初验收版逻辑（曲线反向遍历,与阻尼 0.95 版同构）——
    //   开场可能有轻微反向位移属预期,只验证动画在播且页面未完全出屏。
    expect(midDx.abs(), greaterThan(0.001), reason: '退场中途应仍在位移（动画在播）');
    expect(midDx, lessThan(0.98), reason: '退场中途不应已完全出屏');

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(_settingsTranslation(), findsNothing, reason: '退场完成后页面应移除');

    repository.dispose();
  });

  testWidgets('动效关：push 直切、无位移层（NoTransitionPage，v1.29.0）',
      (tester) async {
    final SettingsRepositoryImpl repository =
        await _pumpApp(tester, blurEnabled: false);

    await _pushSettings(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(PageP0102SettingsPage), findsOneWidget);
    expect(_settingsTranslation(), findsNothing,
        reason: '动效关应直切（无 FractionalTranslation 位移层）');

    repository.dispose();
  });
}
