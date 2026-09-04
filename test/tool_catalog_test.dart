// test/tool_catalog_test.dart
// v1.35.0（P-09）：工具目录模型 + Store 单测 —— ToolConfig JSON 解析
//  （字段映射/派生 route/homeCardId）、ToolResult 各 displayType 子字段、
//  ToolCatalogStore seed/降级/byIdSync（零网络、零 Flutter 依赖）。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/tools/tool_catalog_store.dart';
import 'package:xiangjugong/domain/entities/tool_config.dart';

const String _kCatalogJson = '''
{
  "categories": [
    {
      "id": "game",
      "name": "游戏",
      "icon": "play",
      "tools": [
        {
          "id": "steam_summary",
          "name": "Steam 用户",
          "summary": "查询公开资料",
          "icon": "custom:steam",
          "apiPath": "/api/v1/game/steam/summary",
          "method": "GET",
          "costCredits": 2,
          "displayType": "custom",
          "customRoute": "/steam"
        }
      ]
    },
    {
      "id": "text",
      "name": "文本",
      "icon": "notes",
      "tools": [
        {
          "id": "base64_encode",
          "name": "Base64 编码",
          "summary": "文本编码",
          "apiPath": "/api/v1/text/base64/encode",
          "method": "POST",
          "costCredits": 1,
          "params": [
            { "name": "text", "label": "原文", "type": "text", "in": "body" }
          ],
          "displayType": "text",
          "result": { "field": "encoded" }
        },
        {
          "id": "hotboard",
          "name": "热榜",
          "summary": "热搜",
          "apiPath": "/api/v1/misc/hotboard",
          "params": [
            { "name": "type", "label": "平台", "type": "select", "options": ["weibo", "zhihu"], "in": "query", "defaultValue": "weibo" }
          ],
          "displayType": "list",
          "result": { "listPath": "list", "itemTitle": "title", "itemSubtitle": "hot_value", "itemUrl": "url" }
        }
      ]
    }
  ]
}
''';

void main() {
  group('ToolCategory 映射', () {
    test('id ↔ enum（webParse 特例 + fromId 反查）', () {
      expect(ToolCategory.webParse.id, 'webParse');
      expect(ToolCategory.fromId('webParse'), ToolCategory.webParse);
      expect(ToolCategory.fromId('game'), ToolCategory.game);
      expect(ToolCategory.fromId('不存在'), isNull);
    });
  });

  group('ToolConfig.fromJson', () {
    test('解析 + 派生 route/homeCardId（customRoute 优先）', () {
      final ToolCategoryNode node = ToolCategoryNode.fromJson(
        <String, dynamic>{
          'id': 'text',
          'name': '文本',
          'icon': 'notes',
          'tools': <Object>[
            <String, dynamic>{
              'id': 'base64_encode',
              'name': 'Base64 编码',
              'apiPath': '/api/v1/text/base64/encode',
              'method': 'POST',
              'params': <Object>[
                <String, dynamic>{'name': 'text', 'label': '原文', 'in': 'body'},
              ],
              'displayType': 'text',
              'result': <String, dynamic>{'field': 'encoded'},
            },
          ],
        },
      );
      final ToolConfig t = node.tools.single;
      expect(t.id, 'base64_encode');
      expect(t.category, ToolCategory.text); // 由节点 id 注入。
      expect(t.method, 'POST');
      expect(t.route, '/tool/base64_encode');
      expect(t.homeCardId, 'tool_base64_encode');
      expect(t.result.field, 'encoded');
      expect(t.params.single.inQuery, isFalse); // in=body → 非 query。
    });

    test('customRoute → route 走定制页', () {
      const ToolConfig steam = ToolConfig(
        id: 'steam_summary',
        name: 'Steam',
        summary: '',
        icon: 'custom:steam',
        category: ToolCategory.game,
        apiPath: '/api/v1/game/steam/summary',
        displayType: ResponseDisplayType.custom,
        customRoute: '/steam',
      );
      expect(steam.route, '/steam');
      expect(steam.homeCardId, 'tool_steam_summary');
    });

    test('inQuery 参数（翻译 to_lang 走 query）', () {
      final ToolParam p = ToolParam.fromJson(
        <String, dynamic>{'name': 'to_lang', 'label': '目标语言', 'in': 'query'},
      );
      expect(p.inQuery, isTrue);
    });
  });

  group('ToolResult displayType 子字段', () {
    test('keyValue fields + imageField', () {
      final ToolResult r = ToolResult.fromJson(<String, dynamic>{
        'imageField': 'face',
        'fields': <Object>[
          <String, dynamic>{'key': 'name', 'label': '昵称'},
          <String, dynamic>{'key': 'level', 'label': '等级'},
        ],
      });
      expect(r.imageField, 'face');
      expect(r.fields.length, 2);
      expect(r.fields.first.key, 'name');
      expect(r.fields.first.label, '昵称');
    });

    test('空 result → 默认', () {
      const ToolResult r = ToolResult();
      expect(r.field, isNull);
      expect(r.fields, isEmpty);
    });
  });

  group('ToolCatalogStore', () {
    test('seedFromJsonString：分组 + 平铺 + byIdSync', () {
      final ToolCatalogStore store = ToolCatalogStore.instance;
      expect(store.seedFromJsonString(_kCatalogJson), isTrue);
      expect(store.isReady, isTrue);
      expect(store.groups.length, 2);
      // 平铺含 3 工具。
      expect(store.tools.length, 3);
      // byIdSync 命中。
      final ToolConfig? b64 = store.byIdSync('base64_encode');
      expect(b64, isNotNull);
      expect(b64!.route, '/tool/base64_encode');
      expect(store.byIdSync('不存在'), isNull);
      // steam 定制路由仍保留。
      expect(store.byIdSync('steam_summary')!.route, '/steam');
      // 工具经节点注入分类。
      expect(b64.category, ToolCategory.text);
    });

    test('坏 JSON → 返回 false', () {
      expect(ToolCatalogStore.instance.seedFromJsonString('{bad'), isFalse);
      expect(ToolCatalogStore.instance.seedFromJsonString('{"x":1}'), isFalse);
    });

    test('seedFallback：内置 Steam 单工具保底', () {
      final ToolCatalogStore store = ToolCatalogStore.instance;
      store.seedFallback();
      expect(store.isReady, isTrue);
      expect(store.groups.length, 1);
      final ToolConfig? steam = store.byIdSync('steam_summary');
      expect(steam, isNotNull);
      expect(steam!.route, '/steam');
      expect(steam.icon, 'custom:steam');
    });
  });
}
