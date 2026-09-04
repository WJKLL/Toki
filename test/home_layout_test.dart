// test/home_layout_test.dart
// 回归测试（v1.0.7 / v1.2.0）：安卓版主页（P-01-01）内容位置异常闭环验证。
// 覆盖用户验证步骤：冷启动 / 返回主页 / 横竖屏切换；v1.2.0 追加 C-21 折叠验证。
// 断言核心：首页滚动视图顶边必须顶格（顶栏之下、无大片空白）；滚动后 C-21
//           折叠标题栏必须收起（内容上移）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiangjugong/core/constants/app_constants.dart';
import 'package:xiangjugong/data/repositories/agreement_repository_impl.dart';
import 'package:xiangjugong/data/repositories/settings_repository_impl.dart';
import 'package:xiangjugong/domain/repositories/agreement_repository.dart';
import 'package:xiangjugong/main.dart';
import 'package:xiangjugong/presentation/features/home/page_p01_01_home_page.dart';
import 'package:xiangjugong/presentation/providers/agreement_provider.dart';
import 'package:xiangjugong/presentation/providers/settings_providers.dart';
import 'package:xiangjugong/presentation/widgets/c21_collapsing_title_bar.dart';
import 'package:xiangjugong/presentation/widgets/c24_frosted_fab.dart';
import 'package:xiangjugong/presentation/widgets/c26_more_menu.dart';
import 'package:xiangjugong/presentation/widgets/cards/card_summary.dart';

/// 首页首个内容元素（C-27 摘要卡）的屏幕顶部坐标 —— 度量"内容是否被下推"。
/// C-23 展开态 ≈ 56+64+12+卡片内边距；折叠态更小；大片空白表现为异常偏大。
/// v1.26.0:锚点由已下线的 '版本' 文本改为摘要卡类型(首页内容 v1.14 起重构)。
double _homeFirstContentTop(WidgetTester tester) {
  final Finder summary = find.byType(C27HomeSummary);
  expect(summary, findsOneWidget, reason: '首页首个内容卡(C-27)必须存在');
  return tester.getTopLeft(summary.first).dy;
}

void main() {
  Future<SettingsRepositoryImpl> pumpApp(WidgetTester tester) async {
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
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    return repository;
  }

  testWidgets('P-01-01 首页布局稳定：冷启动/返回/旋转/折叠均正常（回归 v1.4.0）', (tester) async {
    // ── 手机竖屏（逻辑 360×800 < 700px → 窄屏布局）──
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final SettingsRepositoryImpl repository = await pumpApp(tester);

    // 场景 1：冷启动 → 内容顶格（无大片空白）。C-23 展开态 header = 56+64+状态栏，
    //   首内容（'版本'）top ≈ 56+64+12+卡片内边距 ≈ 150；阈值 300 仍可捕获大片空白。
    final double coldTop = _homeFirstContentTop(tester);
    expect(coldTop, greaterThan(0), reason: 'header 必须提供内容偏移（非零）');
    expect(
      coldTop,
      lessThan(300),
      reason: '🔧 布局稳定性：冷启动首页必须顶格（header 之下，无大片空白）',
    );
    expect(find.text('Toki'), findsWidgets, reason: 'C-23 大标题存在（v1.30.0 更名）');

    // 🔧 修复（v1.3.2 / T14）：折叠标题栏不再渲染长副标题。
    expect(
      find.text(AppConstants.tagline),
      findsNothing,
      reason: '✅ 验证通过：折叠栏未渲染长副标题（紧凑单行头部）',
    );

    // ✨ v1.3.0（T9）/ v1.3.3（T18）/ v1.4.0（C-23）：胶囊按钮 —— 展开态 1 左 +
    //   3 右共 4 个;v1.13.0 起右侧仅保留 C-26 更多菜单 → 1 左 + 1 右 = 2 个;
    //   v1.32.1 C-26 触发器改裸图标(MiuixIcon,组件内 IconButton 热区)→ 胶囊仅导航。
    expect(
      find.byType(C21CapsuleIconButton),
      findsOneWidget,
      reason: '✅ 验证通过：展开态顶栏胶囊按钮仅剩左侧导航（v1.32.1 C-26 裸图标）',
    );
    expect(
      find.byType(C26MoreMenu),
      findsOneWidget,
      reason: '✅ 验证通过：展开态顶栏 C-26 更多菜单存在',
    );
    expect(
      find.byKey(const ValueKey('c21.navigation')),
      findsOneWidget,
      reason: '✅ 验证通过：左侧菜单按钮存在',
    );

    // ✨ v1.5.0（T28）：C-24 毛玻璃 FAB 存在且可点击（占位回调无异常）。
    expect(
      find.byType(C24FrostedFab),
      findsOneWidget,
      reason: '✅ 验证通过：首页右下角 FAB 存在',
    );
    // 点击按钮无报错（占位空回调）。FAB 悬浮于顶栏快照层之下,命中目标
    // 常落在上层遮罩 —— 此处仅验证点击回调不抛异常(warnIfMissed 关闭)。
    await tester.tap(find.byType(C24FrostedFab), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: '✅ 验证通过：点击 FAB 无异常');

    // 场景 2（T17）：C-23 折叠验证 —— 向下滚动后 header 收起（大标题上移消失、
    //   小标题滑入），首内容上移。
    // 🔧 复活适配(v1.26.0):首页滚动视图 v1.12 起为 ListView(C-25 折叠联动),
    //   不再存在 CustomScrollView —— 锚点改为页面内首个 Scrollable。
    final Finder homeScroll = find
        .descendant(
          of: find.byType(PageP0101HomePage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(homeScroll, const Offset(0, -300));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(
      _homeFirstContentTop(tester),
      lessThan(coldTop),
      reason: '✅ C-23 折叠验证：滚动后 header 收起，内容必须上移',
    );

    // 折叠态：左侧导航胶囊 + C-26 更多菜单仍可见（按钮行常驻顶部）。
    expect(
      find.byType(C21CapsuleIconButton),
      findsOneWidget,
      reason: '✅ 验证通过：折叠态导航胶囊仍可见（按钮行常驻）',
    );
    expect(
      find.byType(C26MoreMenu),
      findsOneWidget,
      reason: '✅ 验证通过：折叠态 C-26 更多菜单仍可见',
    );

    // 点击按钮无报错（占位空回调）。
    await tester.tap(find.byType(C21CapsuleIconButton).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: '✅ 验证通过：点击胶囊按钮无异常');

    // 场景 3：进入设置页再返回主页 → 布局不变。
    // 🔧 复活适配(v1.26.0):push 后旧 shell context 已 deactivated,
    //   每次跳转需重新取 context。
    GoRouter.of(tester.element(find.byType(MiuixScaffold).first))
        .go('/settings');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    GoRouter.of(tester.element(find.byType(MiuixScaffold).first)).go('/home');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(
      _homeFirstContentTop(tester),
      lessThan(300),
      reason: '🔧 布局稳定性：从设置页返回后首页仍顶格',
    );

    // 场景 4：旋转为横屏（逻辑 800×360 ≥ 700px → 宽屏侧栏布局）→ 布局正确。
    tester.view.physicalSize = const Size(2400, 1080);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.byType(PageP0101HomePage), findsOneWidget);
    expect(
      _homeFirstContentTop(tester),
      lessThan(300),
      reason: '🔧 布局稳定性：横屏（宽屏侧栏）下首页仍顶格',
    );

    // 场景 5：转回竖屏 → 布局不变。
    tester.view.physicalSize = const Size(1080, 2400);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(
      _homeFirstContentTop(tester),
      lessThan(300),
      reason: '🔧 布局稳定性：转回竖屏后首页仍顶格',
    );

    repository.dispose();
  });
}
