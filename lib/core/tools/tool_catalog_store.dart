// === 文件: lib/core/tools/tool_catalog_store.dart ===
// 编号：P-09 通用工具 · 目录缓存单例（v1.35.0 新增）
// 说明：tools.json（assets）启动预加载后的内存缓存 —— 首页工具卡对账
//   （HomeToolItemsController / buildDefaultCardsWithTools）依赖**同步**查询，
//   故 JSON 必须在 main() 预加载完再 runApp（本地 asset 读，非网络）。
//   - seedFromJsonString：解析成功填缓存；失败返回 false（调用方降级）；
//   - seedFallback：asset 异常时内置 Steam 单工具保底（P-08 定制页不受影响）；
//   - byIdSync：同步按 id 查工具（取代退役的 ToolItem.byId）。
import 'dart:convert';

import '../../domain/entities/tool_config.dart';

/// 工具目录内存缓存（进程内单例）。
class ToolCatalogStore {
  ToolCatalogStore._();

  static final ToolCatalogStore instance = ToolCatalogStore._();

  List<ToolCategoryNode> _groups = const <ToolCategoryNode>[];
  List<ToolConfig> _flat = const <ToolConfig>[];
  bool _ready = false;

  /// 是否已成功加载（false = 降级态，仅 Steam 保底）。
  bool get isReady => _ready;

  /// 分类分组（顺序 = JSON categories 顺序；仅含非空分类）。
  List<ToolCategoryNode> get groups => _groups;

  /// 平铺全部工具（含各分类全部条目）。
  List<ToolConfig> get tools => _flat;

  /// 解析 JSON 目录文本并填充缓存；解析失败返回 false（状态不变）。
  bool seedFromJsonString(String source) {
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return false;
      final Object? categories = decoded['categories'];
      if (categories is! List<Object?>) return false;
      final List<ToolCategoryNode> groups = <ToolCategoryNode>[];
      final List<ToolConfig> flat = <ToolConfig>[];
      for (final Object? o in categories) {
        if (o is! Map<String, dynamic>) continue;
        final ToolCategoryNode node = ToolCategoryNode.fromJson(o);
        if (node.tools.isEmpty) continue; // 空分类不建组（如 poem 预留）。
        groups.add(node);
        flat.addAll(node.tools);
      }
      if (flat.isEmpty) return false;
      _groups = List<ToolCategoryNode>.unmodifiable(groups);
      _flat = List<ToolConfig>.unmodifiable(flat);
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 降级保底：内置 Steam 单工具（asset 读/解析异常时，保证 P-08 入口可用）。
  void seedFallback() {
    const ToolConfig steam = ToolConfig(
      id: 'steam_summary',
      name: 'Steam 用户',
      summary: '查询公开资料、头像与在线状态',
      icon: 'custom:steam',
      category: ToolCategory.game,
      apiPath: '/api/v1/game/steam/summary',
      costCredits: 2,
      displayType: ResponseDisplayType.custom,
      customRoute: '/steam',
    );
    _groups = const <ToolCategoryNode>[
      ToolCategoryNode(
        id: 'game',
        name: '游戏',
        icon: 'play',
        category: ToolCategory.game,
        tools: <ToolConfig>[steam],
      ),
    ];
    _flat = const <ToolConfig>[steam];
    _ready = true;
  }

  /// 同步按目录 id 查询（未知/未加载 → null）。
  ToolConfig? byIdSync(String id) {
    for (final ToolConfig t in _flat) {
      if (t.id == id) return t;
    }
    return null;
  }
}
