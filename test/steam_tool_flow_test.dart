// test/steam_tool_flow_test.dart
// v1.34.0(P-08):Steam 工具端到端流程 —— 工具页分组入口 → 长按 500ms 添加
//   → 首页尾部动态卡 → 点击进 /steam → 四格式输入查询成功 → 凭证行配置。
// 依赖注入:steamApiServiceProvider=MockClient fixture、steamAuthServiceProvider
//   =内存假件(不触碰 FlutterSecureStorage 插件通道)。
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiangjugong/core/tools/steam_api_service.dart';
import 'package:xiangjugong/core/tools/steam_auth_service.dart';
import 'package:xiangjugong/core/tools/tool_catalog_store.dart';
import 'package:xiangjugong/data/repositories/agreement_repository_impl.dart';
import 'package:xiangjugong/data/repositories/settings_repository_impl.dart';
import 'package:xiangjugong/domain/repositories/agreement_repository.dart';
import 'package:xiangjugong/main.dart';
import 'package:xiangjugong/presentation/features/tools/page_p08_steam_query_page.dart';
import 'package:xiangjugong/presentation/providers/agreement_provider.dart';
import 'package:xiangjugong/presentation/providers/settings_providers.dart';
import 'package:xiangjugong/presentation/providers/steam_providers.dart';
import 'package:xiangjugong/presentation/widgets/c34_responsive_card_grid.dart';
import 'package:xiangjugong/presentation/widgets/c36_tool_entry_button.dart';
import 'package:xiangjugong/presentation/widgets/c42_tool_category_panel.dart';
import 'package:xiangjugong/presentation/widgets/cards/card_steam_tool.dart';
import 'package:xiangjugong/presentation/widgets/cards/card_summary.dart';

/// 内存凭证假件(SteamAuthService)。
class _FakeAuthService implements SteamAuthService {
  String? key;

  @override
  Future<String?> readApiKey() async => key;

  @override
  Future<void> saveApiKey(String value) async => key = value.trim();

  @override
  Future<void> clearApiKey() async => key = null;
}

/// 成功 fixture(带 realname + 国家 + 在线态 1)。
const String _kUserJson =
    '{"steamid":"76561198012523355","steamid3":"[U:1:52257627]",'
    '"communityvisibilitystate":3,"profilestate":1,"personaname":"PlayerOne",'
    '"profileurl":"https://steamcommunity.com/profiles/76561198012523355/",'
    '"avatarmedium":"https://avatars.steamstatic.com/x_medium.jpg",'
    '"avatarfull":"https://avatars.steamstatic.com/x_full.jpg",'
    '"personastate":1,"realname":"One Player","loccountrycode":"CN",'
    '"timecreated":1249484586,"timecreated_str":"2009-08-05 23:03:06"}';

void main() {
  late _FakeAuthService fakeAuth;
  SettingsRepositoryImpl? repoHolder;

  tearDown(() {
    // S-02 防抖 Timer 必须释放(否则测试结束 Timer pending 断言失败)。
    repoHolder?.dispose();
    repoHolder = null;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // v1.35.0:测试不走 main() 预加载 → 显式 seed 目录(内置 Steam 保底,
    //   供首页工具卡对账 / 工具页 C-36 入口 / /steam 定制路由使用)。
    ToolCatalogStore.instance.seedFallback();
    fakeAuth = _FakeAuthService();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'user_agreement_accepted': true,
      'user_agreement_version': kAgreementVersion,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsRepositoryImpl repository = SettingsRepositoryImpl(prefs);
    repoHolder = repository;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          agreementRepositoryProvider.overrideWithValue(
            AgreementRepositoryImpl(prefs),
          ),
          steamAuthServiceProvider.overrideWithValue(fakeAuth),
          steamApiServiceProvider.overrideWithValue(
            SteamApiService(
              client: MockClient((http.Request req) async {
                return http.Response(_kUserJson, 200);
              }),
            ),
          ),
        ],
        child: const XiangJuGongApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  /// 底栏切换到指定一级页(底栏标签文本唯一)。
  Future<void> switchTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }

  /// 进入工具页并确保「游戏」分类展开(v1.35.0 C-42 默认折叠):
  /// 已展开(懒渲染 C-36 可见)则不重复点击,避免收起。
  Future<void> openGameGroup(WidgetTester tester) async {
    await switchTab(tester, '工具');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    if (find.byType(C36ToolEntryButton).evaluate().isEmpty) {
      await tester.tap(find.text('游戏'), warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
  }

  /// 消化 S-16 高刷释放 Timer(3s)等非帧 Timer,避免测试尾 pending 断言。
  Future<void> settleTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('工具页入口:长按 500ms → 弹层 → 添加 → 首页出现动态卡', (tester) async {
    await pumpApp(tester);
    // 初始:首页无工具卡。
    expect(find.byType(C37SteamToolCard), findsNothing);
    expect(find.byType(C27HomeSummary), findsOneWidget);

    // 切到工具页:分类折叠面板(默认折叠)→ 展开游戏分类见 Steam 入口。
    await openGameGroup(tester);
    expect(find.byType(C42ToolCategoryPanel), findsOneWidget);
    expect(find.byType(C36ToolEntryButton), findsOneWidget);

    // 长按 500ms(Flutter 默认长按时长)→ 添加弹层。
    await tester.longPress(find.byType(C36ToolEntryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('添加到首页'), findsOneWidget);
    expect(find.text('✨ 添加至首页'), findsOneWidget);

    // 点操作行 → 已添加(弹层收起 + toast)。
    await tester.tap(find.byKey(const ValueKey('toolAdd.steam_summary')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('添加到首页'), findsNothing);

    // 再次长按:操作行置灰(已添加态)。
    await tester.longPress(find.byType(C36ToolEntryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('✅ 已添加至首页'), findsOneWidget);
    // 关闭弹层(点标题外区域:直接返回键不可用,再次点击操作行不可点 →
    // 用 dismiss 手势:弹层 onDismissRequest 由遮罩/返回触发;测试中先点操作行
    // 无效,改用 Navigator 返回弹层?这里直接验证置灰后收起:点遮罩区域)。
    // MiuixOverlayDialog 遮罩点击 → onDismissRequest;点屏幕左上角空白处。
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('✅ 已添加至首页'), findsNothing);

    // 回首页:尾部动态卡出现(添加持久化)。
    await switchTab(tester, '首页');
    expect(find.byType(C37SteamToolCard), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('首页工具卡点击 → /steam 页:输入查询成功态展示', (tester) async {
    await pumpApp(tester);
    // 预置已添加:经工具页长按 UI 添加(同 repository 实例在 scope 内)。
    await openGameGroup(tester);
    await tester.longPress(find.byType(C36ToolEntryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('toolAdd.steam_summary')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await switchTab(tester, '首页');

    // 点工具卡 → 二级页 /steam(统一转场 pump 完成)。
    // 工具卡在网格尾部,先上滚使卡可见再点击。
    await tester.drag(
      find.byType(C34ResponsiveCardGrid),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(find.byType(C37SteamToolCard));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(PageP08SteamQueryPage), findsOneWidget);

    // 凭证行(未配置)+ 输入框 + 按钮。
    expect(find.text('未配置 UAPI 密钥 · 点击配置'), findsOneWidget);
    expect(find.byKey(const ValueKey('steam.input')), findsOneWidget);

    // 输入 SteamID64 → 查询 → 成功卡。
    await tester.enterText(
      find.byKey(const ValueKey('steam.input')),
      '76561198012523355',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('steam.submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('PlayerOne'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget); // 状态胶囊
    expect(find.text('One Player'), findsOneWidget); // 实名行
    expect(find.text('CN'), findsOneWidget); // 国家
    expect(find.byKey(const ValueKey('steam.openProfile')), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('凭证行 → 密钥弹层:保存后状态更新为已配置', (tester) async {
    await pumpApp(tester);
    await openGameGroup(tester);
    await tester.tap(find.byType(C36ToolEntryButton)); // 点按 → 进入 /steam
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 打开凭证弹层并保存。
    await tester.tap(find.byKey(const ValueKey('steam.keyRow')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('UAPI 密钥'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('steamKey.input')),
      'my-secret-key',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('steamKey.save')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(fakeAuth.key, 'my-secret-key');
    // 凭证行状态刷新。
    expect(find.text('密钥已配置(加密存储)'), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('编辑态:长按工具卡静止松手 → ✕ 出现 → 点主体不跳转 → ✕ 移除(v1.34.2)', (tester) async {
    await pumpApp(tester);
    // 预置已添加(同 repository 实例)。
    await openGameGroup(tester);
    await tester.longPress(find.byType(C36ToolEntryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('toolAdd.steam_summary')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await switchTab(tester, '首页');
    expect(find.byType(C37SteamToolCard), findsOneWidget);

    // 4 卡网格短,工具卡本就在视口内(无滚动,避免 ensureVisible 扰动外层 PageView)。
    final Offset cardCenter = tester.getCenter(find.byType(C37SteamToolCard));
    expect(cardCenter.dy, lessThan(600)); // 视口内可见

    // 长按 350ms(越过网格 300ms)→ 静止松手 → 编辑态:微缩 + ✕ 弹入。
    final TestGesture hold = await tester.startGesture(
      tester.getCenter(find.byType(C37SteamToolCard)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await hold.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(
      find.byKey(
        const ValueKey('toolRemove.steam_summary'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    // 编辑态:点卡片主体不跳转(防误触,IporePointer 生效)。
    expect(find.byType(PageP08SteamQueryPage), findsNothing); // 长按松手不应误 push
    expect(
      find.byType(C37SteamToolCard, skipOffstage: false),
      findsOneWidget,
    ); // 卡仍在首页树中
    await tester.tap(
      find.byType(C37SteamToolCard),
      warnIfMissed: false, // 编辑态主体被 IgnorePointer 屏蔽,miss 是预期
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(PageP08SteamQueryPage), findsNothing);

    // 点右上 ✕ → 移除 + MiniToast,卡消失(无工具卡自动退出编辑态)。
    await tester.tap(find.byKey(const ValueKey('toolRemove.steam_summary')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(C37SteamToolCard), findsNothing);

    // 再回工具页长按:入口恢复「✨ 添加至首页」(可再次添加)。
    await openGameGroup(tester);
    await tester.longPress(find.byType(C36ToolEntryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('✨ 添加至首页'), findsOneWidget);
    // 关弹层(遮罩区)。
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('✨ 添加至首页'), findsNothing);
    await settleTimers(tester);
  });

  testWidgets('编辑态:系统返回(侧滑)退出后卡片主体恢复可点(v1.34.2)', (tester) async {
    await pumpApp(tester);
    await openGameGroup(tester);
    await tester.longPress(find.byType(C36ToolEntryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('toolAdd.steam_summary')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await switchTab(tester, '首页');
    // 4 卡网格短,工具卡本就在视口内。
    expect(tester.getCenter(find.byType(C37SteamToolCard)).dy, lessThan(600));

    // 长按进编辑态。
    final TestGesture hold2 = await tester.startGesture(
      tester.getCenter(find.byType(C37SteamToolCard)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await hold2.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 系统返回(模拟侧滑返回手势)→ PopScope 拦截,退出编辑态(应用不退出)。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(PageP08SteamQueryPage), findsNothing);

    // 退出后卡片主体恢复可点:点卡 → 跳 /steam。
    await tester.tap(find.byType(C37SteamToolCard));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(PageP08SteamQueryPage), findsOneWidget);
    await settleTimers(tester);
  });
}
