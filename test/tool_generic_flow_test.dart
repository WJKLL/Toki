// test/tool_generic_flow_test.dart
// v1.35.0（P-09）：通用工具链路 —— 工具页 C-42 分组(默认折叠,点击展开) →
//   C-36 入口 → /tool/:id 通用页：有参手动提交(text 模板)、无参自动请求
//   (keyValue 模板)。MockClient fixture 按路径返回,零真实网络。
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiangjugong/core/tools/steam_auth_service.dart';
import 'package:xiangjugong/core/tools/tool_api_service.dart';
import 'package:xiangjugong/core/tools/tool_catalog_store.dart';
import 'package:xiangjugong/data/repositories/agreement_repository_impl.dart';
import 'package:xiangjugong/data/repositories/settings_repository_impl.dart';
import 'package:xiangjugong/data/repositories/todo_repository_impl.dart';
import 'package:xiangjugong/domain/repositories/agreement_repository.dart';
import 'package:xiangjugong/main.dart';
import 'package:xiangjugong/presentation/providers/agreement_provider.dart';
import 'package:xiangjugong/presentation/providers/settings_providers.dart';
import 'package:xiangjugong/presentation/providers/steam_providers.dart';
import 'package:xiangjugong/presentation/providers/todo_providers.dart';
import 'package:xiangjugong/presentation/providers/tool_items_provider.dart';
import 'package:xiangjugong/presentation/widgets/c36_tool_entry_button.dart';
import 'package:xiangjugong/presentation/widgets/c42_tool_category_panel.dart';

/// 测试目录：文本组(md5 有参 / myip 无参)。
const String _kSeedJson = '''
{
  "categories": [
    {
      "id": "text",
      "name": "文本",
      "icon": "notes",
      "tools": [
        {
          "id": "md5",
          "name": "MD5 哈希",
          "summary": "文本 MD5 摘要",
          "apiPath": "/api/v1/text/md5",
          "params": [
            { "name": "text", "label": "原文", "type": "text", "in": "query" }
          ],
          "displayType": "text",
          "result": { "field": "md5" }
        },
        {
          "id": "myip",
          "name": "我的 IP",
          "summary": "查询本机公网 IP",
          "apiPath": "/api/v1/network/myip",
          "displayType": "keyValue",
          "result": {
            "fields": [
              { "key": "ip", "label": "IP" },
              { "key": "region", "label": "地区" }
            ]
          }
        }
      ]
    },
    {
      "id": "enhanced",
      "name": "增强",
      "icon": "notes",
      "tools": [
        {
          "id": "nested_kv",
          "name": "嵌套取值",
          "summary": "点路径 + 枚举映射 + 数字截断",
          "apiPath": "/api/v1/test/nested",
          "displayType": "keyValue",
          "result": {
            "fields": [
              { "key": "data.stat.view", "label": "播放" },
              { "key": "owner.name", "label": "UP 主" },
              { "key": "data.live_status", "label": "状态", "map": { "0": "未开播", "1": "直播中" } },
              { "key": "data.avg", "label": "平均延迟" }
            ]
          }
        },
        {
          "id": "scalar_list",
          "name": "标量列表",
          "summary": "数字数组逐行展示",
          "apiPath": "/api/v1/test/numbers",
          "displayType": "list",
          "result": {
            "listPath": "numbers"
          }
        }
      ]
    }
  ]
}
''';

class _FakeAuthService implements SteamAuthService {
  String? key;
  @override
  Future<String?> readApiKey() async => key;
  @override
  Future<void> saveApiKey(String value) async => key = value.trim();
  @override
  Future<void> clearApiKey() async => key = null;
}

void main() {
  late _FakeAuthService fakeAuth;
  SettingsRepositoryImpl? repoHolder;

  tearDown(() {
    repoHolder?.dispose();
    repoHolder = null;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    ToolCatalogStore.instance.seedFromJsonString(_kSeedJson);
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
          // v1.43.0(S-23)：待办仓储注入（P-10 为 PageView 首页左页）。
          todoRepositoryProvider.overrideWithValue(TodoRepositoryImpl(prefs)),
          steamAuthServiceProvider.overrideWithValue(fakeAuth),
          toolApiServiceProvider.overrideWithValue(
            ToolApiService(
              client: MockClient((http.Request req) async {
                const Map<String, String> jsonHeaders = <String, String>{
                  'content-type': 'application/json; charset=utf-8',
                };
                final String path = req.url.path;
                if (path == '/api/v1/text/md5') {
                  return http.Response(
                    '{"md5":"5eb63bbbe01eeed093cb22bb8f5acdc3"}',
                    200,
                    headers: jsonHeaders,
                  );
                }
                if (path == '/api/v1/network/myip') {
                  return http.Response(
                    '{"ip":"120.238.162.8","region":"中国 广东 肇庆","isp":"China Mobile"}',
                    200,
                    headers: jsonHeaders,
                  );
                }
                if (path == '/api/v1/test/nested') {
                  return http.Response(
                    '{"owner":{"name":"张三"},"data":{"stat":{"view":123456},"live_status":1,"avg":70.683893001}}',
                    200,
                    headers: jsonHeaders,
                  );
                }
                if (path == '/api/v1/test/numbers') {
                  return http.Response(
                    '{"numbers":[7,6,1]}',
                    200,
                    headers: jsonHeaders,
                  );
                }
                return http.Response(
                  '{"code":"NOT_FOUND"}',
                  404,
                  headers: jsonHeaders,
                );
              }),
            ),
          ),
        ],
        child: const XiangJuGongApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  Future<void> switchTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }

  Future<void> settleTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('工具页:分类默认折叠,点击展开出现 C-36 入口', (tester) async {
    await pumpApp(tester);
    await switchTab(tester, '工具');
    // 分组标题存在(文本 + 增强 两个分类)。
    expect(find.byType(C42ToolCategoryPanel), findsNWidgets(2));
    expect(find.text('文本'), findsOneWidget);
    expect(find.text('增强'), findsOneWidget);
    // 默认折叠:入口按钮不可见。
    expect(find.byType(C36ToolEntryButton), findsNothing);
    // 点击分类头展开 → C-36 出现。
    await tester.tap(find.text('文本'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(C36ToolEntryButton), findsNWidgets(2));
    await settleTimers(tester);
  });

  testWidgets('通用页:有参工具手动提交 → text 模板结果', (tester) async {
    await pumpApp(tester);
    await switchTab(tester, '工具');
    await tester.tap(find.text('文本'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // 点 md5 入口进 /tool/md5。
    await tester.tap(find.text('MD5 哈希'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // 输入 + 提交。
    await tester.enterText(
      find.byKey(const ValueKey<String>('toolParam.text')),
      'hello world',
    );
    await tester.tap(find.byKey(const ValueKey<String>('tool.submit')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // text 模板结果(md5 值出现)。
    expect(find.text('5eb63bbbe01eeed093cb22bb8f5acdc3'), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('通用页:无参工具进页自动请求 → keyValue 模板结果', (tester) async {
    await pumpApp(tester);
    await switchTab(tester, '工具');
    await tester.tap(find.text('文本'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // 点 myip 入口进 /tool/myip（无参 → 自动请求）。
    await tester.tap(find.text('我的 IP'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    // 导航到达验证:顶栏标题 '我的 IP'(原页已 offstage,不重复计数)。
    expect(
      find.text('我的 IP'),
      findsWidgets,
      reason: '应已导航到 /tool/myip',
    );
    // 中间态诊断:非 loading、非 error。
    expect(find.textContaining('请求失败'), findsNothing);
    expect(find.textContaining('请求中'), findsNothing);
    // keyValue 结果:标签 + 值。
    expect(find.text('地区'), findsOneWidget);
    expect(find.text('中国 广东 肇庆'), findsOneWidget);
    // 自动请求后按钮文案为刷新。
    expect(find.textContaining('刷新'), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('增强:点路径/枚举映射/数字截断 keyValue(v1.38.0)', (tester) async {
    await pumpApp(tester);
    await switchTab(tester, '工具');
    await tester.tap(find.text('增强'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('嵌套取值'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    // 点路径取值(data.stat.view / owner.name)。
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    // 枚举值映射 live_status 1 → 直播中。
    expect(find.text('直播中'), findsOneWidget);
    // 长小数截断 70.683893001 → 70.68。
    expect(find.text('70.68'), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('增强:标量数组逐行 list(v1.38.0)', (tester) async {
    await pumpApp(tester);
    await switchTab(tester, '工具');
    await tester.tap(find.text('增强'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('标量列表'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    // 数字数组 [7,6,1] 每元素一行标题。
    expect(find.text('7'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await settleTimers(tester);
  });
}
