// lib/presentation/providers/home_cards_provider.dart
// 编号：P-01-01 首页卡片数据源（v1.14.0;v1.22.0 网格化拆分;
//   v1.26.0 摘要动态内容迁出至 quote_provider.dart）
// 说明：
//   - 摘要区(C-27)内容 v1.26.0 起由 S-21/S-22 动态提供(问候语 + 每日一言),
//     不再经本文件;summary 类型保留仅供 C-34 类型穷尽;
//   - gridCardsProvider:网格内卡片顺序(Notifier),顺序持久化到
//     S-02 settings.cardOrder(仅松手/显式调用后防抖写盘;坏数据回默认);
//   - 卡片本体数据(组合卡/倒计时)由各自组件 watch 实时 Provider,
//     本文件仅提供顺序与静态文案兜底。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tools/tool_catalog_store.dart';
import '../../domain/entities/home_card.dart';
import 'settings_providers.dart';

/// 默认网格卡顺序(v1.22.0:large 组合卡 / wide 仪表盘 / small×4,
/// 2 列时恰好 3 行满排;v1.34.1:占位卡体系移除,只留有实际内容的卡 ——
/// combo(2×2)+ dashboard(2×1)+ countdown(1×1),工具卡按目录动态追加尾部;
/// 顺序可被 settings.cardOrder 覆盖)。
const List<HomeCardData> kDefaultGridCards = <HomeCardData>[
  ComboCardData(
    remainingTitle: '今日剩余',
    remainingValue: '3h 20m',
    remainingDeadline: '截止 18:00',
  ),
  // v1.49.0:仪表盘卡改为「待办」实时卡 —— 标题兜底在此,
  // 数值/分段进度由 C29 内部 watch todoOverviewProvider 派生(此处置空)。
  DashboardCardData(
    title: '待办',
    stats: <DashboardStat>[],
    progress: <int>[],
  ),
  ClassCountdownCardData(),
];

// ── v1.34.0(P-08):首页工具目录状态(长按添加/移除,持久化)────────────

/// 已加入首页的工具目录 id 列表(settings.homeToolItems;
/// 顺序 = 追加次序,尾部动态生成工具启动卡)。
final homeToolItemsProvider =
    NotifierProvider<HomeToolItemsController, List<String>>(
      HomeToolItemsController.new,
    );

class HomeToolItemsController extends Notifier<List<String>> {
  @override
  List<String> build() {
    // 与工具目录对账:坏数据/已下架 id 直接滤除(不产生非法卡)。
    final List<String> items = ref
        .read(settingsRepositoryProvider)
        .loadHomeToolItems();
    return <String>[
      for (final String id in items)
        if (ToolCatalogStore.instance.byIdSync(id) != null) id,
    ];
  }

  bool contains(String toolId) => state.contains(toolId);

  /// 加入首页(未知目录 id 忽略;已加入幂等)。
  Future<void> add(String toolId) async {
    if (ToolCatalogStore.instance.byIdSync(toolId) == null || contains(toolId)) {
      return;
    }
    final List<String> next = <String>[...state, toolId];
    state = next;
    _persist(next);
  }

  /// 移出首页。
  Future<void> remove(String toolId) async {
    if (!contains(toolId)) return;
    final List<String> next = <String>[
      for (final String id in state)
        if (id != toolId) id,
    ];
    state = next;
    _persist(next);
  }

  void _persist(List<String> ids) {
    ref.read(settingsRepositoryProvider).saveHomeToolItems(ids);
  }
}

/// 内置默认卡 + 按已加入工具目录动态追加的工具启动卡(尾部)。
/// 由 gridCardsProvider.build 读取(目录变更 → rebuild → 尾卡增减)。
List<HomeCardData> buildDefaultCardsWithTools(List<String> toolIds) {
  return <HomeCardData>[
    ...kDefaultGridCards,
    for (final String id in toolIds)
      if (ToolCatalogStore.instance.byIdSync(id) != null)
        ToolLaunchCardData(toolId: id),
  ];
}

/// 网格卡顺序状态(竖屏/横屏各一套,v1.23.1)。
typedef GridOrderState = ({
  List<HomeCardData> portrait,
  List<HomeCardData> landscape,
});

/// 网格卡顺序(竖/横各一套;拖拽 UI 按当前方向读写对应套)。
final gridCardsProvider = NotifierProvider<HomeCardsController, GridOrderState>(
  HomeCardsController.new,
);

class HomeCardsController extends Notifier<GridOrderState> {
  @override
  GridOrderState build() {
    final ({List<String>? portrait, List<String>? landscape}) order = ref
        .read(settingsRepositoryProvider)
        .loadCardOrder();
    // v1.34.0:工具目录(尾部动态卡)为顺序依赖 —— 目录变化时连同默认卡重建。
    final List<String> toolIds = ref.watch(homeToolItemsProvider);
    final List<HomeCardData> defaults = buildDefaultCardsWithTools(toolIds);
    return (
      portrait: _applyOrder(defaults, order.portrait),
      landscape: _applyOrder(defaults, order.landscape),
    );
  }

  /// 按持久化顺序重排:未知 id(新卡)忽略,缺失 id(默认新卡)按默认序追加尾部。
  static List<HomeCardData> _applyOrder(
    List<HomeCardData> defaults,
    List<String>? order,
  ) {
    if (order == null) return defaults;
    final Map<String, HomeCardData> byId = <String, HomeCardData>{
      for (final HomeCardData c in defaults) c.id: c,
    };
    final List<HomeCardData> out = <HomeCardData>[];
    final Set<String> used = <String>{};
    for (final String id in order) {
      final HomeCardData? card = byId[id];
      if (card != null && used.add(id)) out.add(card);
    }
    for (final HomeCardData card in defaults) {
      if (used.add(card.id)) out.add(card);
    }
    return out;
  }

  /// 将 [oldIndex] 的卡移动到 [newIndex]——**移除后列表(base)的插入位**
  /// (与 C-34 拖拽预览的 display 构建语义一致;注意:并非 Flutter
  /// onReorder 的「原列表下标」语义,v1.24.7 修正——旧实现额外 -1 导致
  /// 右拖落点比松手前预览布局前进一格,松手瞬间整网卡片二次让位)。
  /// [landscape] 选择横屏套(否则竖屏套),两套互不影响。
  void reorder({
    required bool landscape,
    required int oldIndex,
    required int newIndex,
  }) {
    final GridOrderState cur = state;
    final List<HomeCardData> src = landscape ? cur.landscape : cur.portrait;
    if (oldIndex < 0 || oldIndex >= src.length) return;
    final List<HomeCardData> list = <HomeCardData>[...src];
    final HomeCardData item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    state = landscape
        ? (portrait: cur.portrait, landscape: list)
        : (portrait: list, landscape: cur.landscape);
    _persist();
  }

  /// 恢复默认顺序(两套;供未来「整理」入口使用)。
  /// v1.34.0:按当前工具目录重建默认(尾部工具卡保留)。
  void restoreDefault() {
    final List<String> toolIds = ref.read(homeToolItemsProvider);
    final List<HomeCardData> defaults = buildDefaultCardsWithTools(toolIds);
    state = (portrait: defaults, landscape: defaults);
    _persist();
  }

  /// 松手后防抖写盘(仓储侧自带 300ms 合并)。
  void _persist() {
    final GridOrderState cur = state;
    ref
        .read(settingsRepositoryProvider)
        .saveCardOrder(
          portrait: <String>[for (final HomeCardData c in cur.portrait) c.id],
          landscape: <String>[for (final HomeCardData c in cur.landscape) c.id],
        );
  }
}
