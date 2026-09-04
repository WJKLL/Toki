// test/settings_ui_state_test.dart
// 回归测试（v1.0.6）：设置页「点击生效但 UI 状态不更新」故障闭环验证。
// 验证点：
//   1. 状态层：ref.watch → 点击开关 → value 必须同步翻转（S-01 状态 → UI 重建）。
//   2. 视觉层（🔧 v1.0.6 根因）：MiuixSwitch 圆点由 _thumbPos 动画驱动，
//      若页面整体 TickerMode(enabled:false) 动画会被静音冻结——断言圆点
//      Positioned.left 必须实际右移（蓝色底 + 白圆点靠右的期望行为）。
//   3. 分段高亮：点击「浅色」→ selectedTabIndex 必须为 1。
//   4. S-02 持久化：点击后写回（防抖 300ms 内）可读回。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiangjugong/data/repositories/agreement_repository_impl.dart';
import 'package:xiangjugong/data/repositories/settings_repository_impl.dart';
import 'package:xiangjugong/domain/entities/app_settings.dart';
import 'package:xiangjugong/domain/repositories/agreement_repository.dart';
import 'package:xiangjugong/main.dart';
import 'package:xiangjugong/presentation/features/settings/page_p01_02_settings_page.dart';
import 'package:xiangjugong/presentation/providers/agreement_provider.dart';
import 'package:xiangjugong/presentation/providers/settings_providers.dart';

void main() {
  testWidgets('设置页开关/分段点击后 UI 状态同步更新（回归 v1.0.6）', (tester) async {
    // 手机尺寸（逻辑 360×800 < 700px 断点 → 窄屏布局）。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // v1.20.0+：协议卡仓储需 override 且预置「已同意当前版本」直通 Gate。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'user_agreement_accepted': true,
      'user_agreement_version': kAgreementVersion,
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

    // 进入设置页（R-03）。
    final BuildContext shellCtx = tester.element(
      find.byType(MiuixScaffold).first,
    );
    GoRouter.of(shellCtx).go('/settings');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 设置页自身的滚动视图（MiuixScaffold 内 ListView）。
    final Finder settingsScrollable = find
        .descendant(
          of: find.byType(PageP0102SettingsPage),
          matching: find.byType(Scrollable),
        )
        .first;

    // ── 1) 悬浮底栏开关：初始 false → 点击 → value 翻转 + 圆点右移 ──
    final Finder floatingSwitch = find.byKey(const ValueKey('switch.floating'));
    await tester.ensureVisible(floatingSwitch);
    await tester.pumpAndSettle();
    MiuixSwitchPreference before = tester.widget<MiuixSwitchPreference>(
      floatingSwitch,
    );
    expect(before.value, isFalse, reason: '初始应为关闭');

    final double thumbLeftBefore = _switchThumbLeft(tester, floatingSwitch);

    // 🔧 复活适配(v1.26.0):C-25 顶栏悬浮于内容之上 —— ensureVisible 会把
    //   行贴到视口顶部(被顶栏盖住),需再下拉 200px 让开关行进入安全区。
    await tester.ensureVisible(floatingSwitch);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(settingsScrollable, const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(floatingSwitch);
    // ⚠️ C-22 悬浮模式开启后 CaptureHeartbeat 心跳（repeat 常驻，v1.7.6 T50）
    //   永不停歇，pumpAndSettle 会超时 —— 改用有限 pump 等待开关动画与
    //   布局切换（Column→Stack）完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final MiuixSwitchPreference after = tester.widget<MiuixSwitchPreference>(
      floatingSwitch,
    );
    expect(
      after.value,
      isTrue,
      reason: '🔧 修复验证：点击后开关 value 必须同步为 true（ref.watch 重建 → prop 更新）',
    );

    // 🔧 v1.0.6 视觉层断言：圆点必须实际右移（>10px）。修复前页面整体
    //   TickerMode(enabled:false) 静音 _thumbPos 动画，此处必然失败。
    final double thumbLeftAfter = _switchThumbLeft(tester, floatingSwitch);
    expect(
      thumbLeftAfter,
      greaterThan(thumbLeftBefore + 10),
      reason:
          '🔧 修复验证（v1.0.6 根因）：白圆点必须右移（蓝色底+圆点靠右），'
          'TickerMode 不得静音开关动画',
    );

    // ── 2) UI 模式分段（C-13）：点击「浅色」→ 高亮索引必须为 1 ──
    final Finder uiModeRow = find.byKey(const ValueKey('uiMode'));
    await tester.ensureVisible(uiModeRow);
    // 悬浮模式已开启：心跳常驻 → 有限 pump（同上）。
    await tester.pump(const Duration(milliseconds: 400));
    // MiuixScaffold 顶栏悬浮绘制在内容之上：将内容下移，确保分段整体在顶栏之下。
    // 🔧 复活适配(v1.26.0):下拉量 120→240(展开态大标题 ~120,须完全脱离)。
    await tester.drag(settingsScrollable, const Offset(0, 240));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.descendant(of: uiModeRow, matching: find.text('浅色')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final MiuixTabRow tabRow = tester.widget<MiuixTabRow>(uiModeRow);
    expect(
      tabRow.selectedTabIndex,
      1,
      reason: '🔧 修复验证：点击「浅色」后高亮索引必须为 1（高亮跟随状态）',
    );

    // ── 3) S-02 持久化：等待防抖落盘后读回 ──
    await tester.pump(const Duration(milliseconds: 400));
    final AppSettings reloaded = repository.load();
    expect(
      reloaded.floatingBarEnabled,
      isTrue,
      reason: 'S-02 持久化：悬浮底栏状态必须写回并可读回',
    );
    expect(reloaded.uiMode, AppUiMode.light, reason: 'S-02 持久化：UI 模式必须写回并可读回');

    repository.dispose();
  });
}

/// 读取 MiuixSwitch 内部圆点（Thumb）Positioned 的 left 值：
/// 轨道用 Positioned.fill（left==0 且 right!=null），圆点用 left 驱动（right==null）。
double _switchThumbLeft(WidgetTester tester, Finder switchRow) {
  final Iterable<Positioned> positioned = tester.widgetList<Positioned>(
    find.descendant(of: switchRow, matching: find.byType(Positioned)),
  );
  for (final Positioned p in positioned) {
    if (p.right == null && p.left != null) return p.left!;
  }
  fail('未找到 MiuixSwitch 的圆点 Positioned');
}
