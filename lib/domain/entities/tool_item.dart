// lib/domain/entities/tool_item.dart
// 编号：F-04 工具集目录实体（v1.34.0 新增;P-01-04 工具入口数据源）
// 说明：纯领域实体 —— 工具目录静态条目(名称/图标/路由/积分),由工具页
//   入口网格与首页动态工具卡共用(首页卡 id 以 [homeCardId] 关联)。
//   图标约定:core/widgets/steam_logo_icon.dart 自绘徽标走 [logoKind];
//   不依赖任何 UI 框架(Clean Architecture)。
class ToolItem {
  const ToolItem({
    required this.id,
    required this.name,
    required this.summary,
    required this.logoKind,
    required this.route,
    required this.credits,
    required this.homeCardId,
  });

  /// 工具目录 id(持久化 settings.homeToolItems 的元素值)。
  final String id;

  /// 展示名(入口/卡片/弹层统一)。
  final String name;

  /// 一句说明(弹层副行 / 未来列表用)。
  final String summary;

  /// 徽标种类(当前仅 'steam' 自绘;C-38 SteamLogoIcon)。
  final String logoKind;

  /// 点击进入的二级页路由(R-11 /steam)。
  final String route;

  /// 每次查询消耗的 UAPI 积分(说明文案)。
  final int credits;

  /// 首页动态工具卡 id(HomeCardData.id;加入首页网格后尾部追加)。
  final String homeCardId;

  // ── 当前目录(游戏工具分组,未来条目追加于此)──────────────────

  /// Steam 用户查询(工具目录第一项)。
  static const ToolItem steam = ToolItem(
    id: 'steam_summary',
    name: 'Steam 用户',
    summary: '查询公开资料、头像与在线状态',
    logoKind: 'steam',
    route: '/steam',
    credits: 2,
    homeCardId: 'tool_steam_summary',
  );

  /// 按目录 id 查找(未知返回 null)。
  static ToolItem? byId(String id) {
    for (final ToolItem item in kToolCatalog) {
      if (item.id == id) return item;
    }
    return null;
  }
}

/// 工具目录(顺序 = 工具页「🎮 游戏工具」分组入口顺序)。
const List<ToolItem> kToolCatalog = <ToolItem>[ToolItem.steam];
