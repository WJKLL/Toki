// lib/domain/entities/home_card.dart
// 编号：P-01-01 首页卡片数据模型（v1.14.0，C-27~C-30 数据源；v1.22.0 网格化）
// 说明：首页卡片体系的数据模型 —— sealed 类型 + 各卡片数据类。
//       v1.22.0：引入 CardSize（colspan/rowspan）与 id（排序持久化/ValueKey）,
//       纯领域实体，不依赖 UI 框架（Clean Architecture，F-02 首页模块）。
//       v1.34.1：占位卡体系移除（C-30 停用）—— 网格只保留有实际内容的卡。

/// 卡片尺寸档（网格 colspan × rowspan）。
enum CardSize {
  /// 1×1：倒计时、工具启动卡。
  small,

  /// 2×1：仪表盘。
  wide,

  /// 2×2：组合大卡。
  large,
}

extension CardSizeSpan on CardSize {
  /// 占列数（2 列网格中 wide/large 即整行宽）。
  int get colspan => this == CardSize.small ? 1 : 2;

  /// 占行数。
  int get rowspan => this == CardSize.large ? 2 : 1;
}

enum HomeCardType {
  /// C-27 摘要区：雑魚，XX + 每日一言（固定顶置，不入网格）。
  summary,

  /// C-28 组合大卡片：[小课表 + 今日剩余仪表盘环]。
  combo,

  /// C-29 仪表盘：统计 + 进度条。
  dashboard,

  /// A-04 课程倒计时（C-33，v1.21.0）。
  countdown,

  /// v1.34.0（P-08）：工具启动卡（C-37,按目录动态追加尾部,右上 ✕ 可移除）。
  tool,
}

/// 首页卡片数据基类（sealed：穷尽匹配，避免非法类型）。
/// v1.22.0：[id] 唯一标识（排序持久化 key / ValueKey），[size] 网格尺寸档。
sealed class HomeCardData {
  const HomeCardData({
    required this.type,
    required this.id,
    required this.size,
  });

  final HomeCardType type;
  final String id;
  final CardSize size;
}

/// C-27 摘要区数据（v1.26.0 起内容不再静态化:问候语由 S-22 现算、
/// 每日一言由 S-21 流式提供 —— 本类型仅保留供 C-34 类型穷尽 switch,
/// 字段不再有运行时数据源）。
class SummaryCardData extends HomeCardData {
  const SummaryCardData({
    required this.greeting,
    required this.dailyLabel,
    required this.dailyContent,
  }) : super(type: HomeCardType.summary, id: 'summary', size: CardSize.wide);

  /// 大标题问候（如「雑魚，XX」）。
  final String greeting;

  /// 每日一言标签（如「每日一言」）。
  final String dailyLabel;

  /// 每日一言内容。
  final String dailyContent;
}

/// 小课表条目（时间 + 事项）—— v1.15.0 起小课表数据改由 S-15 课程仓库驱动，
/// 本占位类型移除。
enum ComboRemainingField { title, value, deadline }

/// C-28 组合大卡片数据：今日剩余仪表盘（小课表数据来自 courseListProvider）。
class ComboCardData extends HomeCardData {
  const ComboCardData({
    required this.remainingTitle,
    required this.remainingValue,
    required this.remainingDeadline,
  }) : super(type: HomeCardType.combo, id: 'combo', size: CardSize.large);

  /// 今日剩余仪表盘标题（「今日剩余」）。
  final String remainingTitle;

  /// 今日剩余数值（如「3h 20m」）。
  final String remainingValue;

  /// 截止说明（如「截止 18:00」）。
  final String remainingDeadline;
}

/// 仪表盘统计项（数值 + 标签）。
class DashboardStat {
  const DashboardStat({required this.value, required this.label});

  final String value;
  final String label;
}

/// C-29 仪表盘数据：标题 + 统计项 + 分段进度。
class DashboardCardData extends HomeCardData {
  const DashboardCardData({
    required this.title,
    required this.stats,
    required this.progress,
  }) : super(
         type: HomeCardType.dashboard,
         id: 'dashboard',
         size: CardSize.wide,
       );

  final String title;
  final List<DashboardStat> stats;

  /// 分段进度（如 [3,1,1,1]：各段宽度权重）。
  final List<int> progress;
}

/// A-04 课程倒计时卡片数据（v1.21.0）：仅占位/分发用,
/// 真实数据由 C-33 内部 watch currentClassProvider / 节次时间表获取。
class ClassCountdownCardData extends HomeCardData {
  const ClassCountdownCardData({this.title = '课程倒计时'})
    : super(
        type: HomeCardType.countdown,
        id: 'countdown',
        size: CardSize.small,
      );

  /// 卡片标题（空态时展示）。
  final String title;
}

/// v1.34.0(P-08):工具启动卡数据 —— 首页网格尾部动态追加
/// (settings.homeToolItems 持久化;点击进入工具路由)。
/// [toolId] = 工具目录 id(ToolItem.id);[id] 派生 `tool_<toolId>`,
/// 未知 toolId 由 provider 层直接滤除,不产生非法卡。
/// v1.34.1:移除交互 = 卡片右上 ✕ 一键移除(C-37 内实现);
/// 长按 300ms 仍归网格拖拽排序。
class ToolLaunchCardData extends HomeCardData {
  const ToolLaunchCardData({required this.toolId})
    : super(
        type: HomeCardType.tool,
        id: 'tool_$toolId',
        size: CardSize.small,
      );

  final String toolId;
}
