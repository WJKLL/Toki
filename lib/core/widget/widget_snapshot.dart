// === 文件: lib/core/widget/widget_snapshot.dart ===
// 编号：S-26 内部件 · 桌面小组件快照（v1.51.1 焦点卡契约）
// 说明：Flutter 侧把「当前 / 下一节课」焦点卡算好并序列化为 JSON 交给原生渲染。
//   本文件**纯逻辑**（无 IO、无 UI、无平台通道），全部可单测。
//
//   v1.51.1 结构对齐鸿蒙版服务卡片（harmonyos_port 的 TodayCourseCard.ets +
//   lib/core/cards/course_card_sync.dart）：由「今日课程三列列表」改为「焦点卡」——
//   标题/周次 → 当前或下一节标签 → 课程名大字 → 教室 → 下一节行。
//   计算口径（周次过滤 / 进行中与下一节判定 / 文案）逐条移植鸿蒙版实现，
//   使两端卡片文案与判定完全一致；时刻换算复用共享的 courseSpanOf。
import 'dart:convert';

import '../../domain/entities/class_period.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/course_span.dart';

/// 今日课程焦点卡快照：原生侧渲染的唯一数据源。
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.dateKey,
    required this.weekText,
    required this.curTag,
    required this.curName,
    required this.curRoom,
    required this.nextLine,
    required this.remainText,
    required this.isDark,
    required this.updatedAt,
  });

  /// 载荷格式版本。v2 = 焦点卡契约（v1 为已废弃的三列列表契约）。
  static const int version = 2;

  /// 日期键 `yyyy-MM-dd`；原生比对当日日期，不一致视为过期数据。
  final String dateKey;

  /// 周次副标题，如「第 12 周 · 第 1 学期」（与鸿蒙版同文案）。
  final String weekText;

  /// 状态标签，**强调色**显示：`当前课程` / `下一节课` / `全天课程结束`
  /// （无课表时为 `暂无课程`）。
  final String curTag;

  /// 课程名（**大字视觉焦点**）；无课/休息时为 `暂无课程` / `休息中`。
  final String curName;

  /// 教室行，如 `教室:A-301`；无教室信息时为空串（原生隐藏该行）。
  final String curRoom;

  /// 末行提示，如 `下一节课是:大学英语 10:00` / `今天没有更多课了`。
  final String nextLine;

  /// 倒计时文本，如 `剩余 35 分钟`；仅上课中出现，其余为空串。
  /// （鸿蒙版此处是圆环进度 + 数字，Android RemoteViews 画不出环形，
  ///   故降级为等义的文本。）
  final String remainText;

  /// 亮暗模式 → 原生据此切换 `widget_bg_light` / `widget_bg_dark` 布局。
  final bool isDark;

  /// 写入时间戳（毫秒；诊断用）。
  final int updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': version,
    'updatedAt': updatedAt,
    'dateKey': dateKey,
    'weekText': weekText,
    'curTag': curTag,
    'curName': curName,
    'curRoom': curRoom,
    'nextLine': nextLine,
    'remainText': remainText,
    'isDark': isDark,
  };

  /// 编码为写入原生的 JSON 文本。
  String encode() => jsonEncode(toJson());

  /// 空态快照（课表尚未加载时的兜底，与鸿蒙版「暂无课程」同文案）。
  static WidgetSnapshot empty({
    required DateTime now,
    required bool isDark,
    ScheduleMeta? meta,
  }) => WidgetSnapshot(
    dateKey: dateKeyOf(now),
    weekText: weekTextOf(meta, now),
    curTag: '',
    curName: '暂无课程',
    curRoom: '',
    nextLine: '点击卡片去添加',
    remainText: '',
    isDark: isDark,
    updatedAt: now.millisecondsSinceEpoch,
  );
}

/// 由课表数据构建今日课程焦点卡快照（纯函数，可直接单测）。
///
/// 筛选口径与 `course_reminder_bridge._scheduleCourseAlarms` 一致：
/// `c.day == 当日星期 && c.showsOn(effectiveWeek)`；节次时间缺失（整段算不出）
/// 的课程会被跳过 —— 与鸿蒙版 `CourseCardSync` 完全相同。
WidgetSnapshot buildTodaySnapshot({
  required List<Course> courses,
  required List<ClassPeriod> periods,
  required ScheduleMeta meta,
  required DateTime now,
  required bool isDark,
}) {
  final int weekday = now.weekday; // 1=周一 .. 7=周日
  final int week = meta.effectiveWeek(now);
  final int nowMin = now.hour * 60 + now.minute;

  // 今日课程（带整段起止分钟），按开始时刻升序。
  final List<_Row> rows = <_Row>[];
  for (final Course c in courses) {
    if (c.day != weekday) continue;
    if (!c.showsOn(week)) continue;
    final CourseSpan? span = courseSpanOf(c, periods);
    if (span == null) continue; // 节次未启用/时间缺失 → 无法定位，略过。
    rows.add(
      _Row(
        name: c.name,
        start: span.start,
        end: span.end,
        room: c.location?.trim() ?? '',
      ),
    );
  }
  rows.sort((_Row a, _Row b) => a.start.compareTo(b.start));

  final String weekLabel = weekTextOf(meta, now);

  // 今天没课（或课表为空）。
  if (rows.isEmpty) {
    return WidgetSnapshot(
      dateKey: dateKeyOf(now),
      weekText: weekLabel,
      curTag: '',
      curName: '暂无课程',
      curRoom: '',
      nextLine: '点击卡片去添加',
      remainText: '',
      isDark: isDark,
      updatedAt: now.millisecondsSinceEpoch,
    );
  }

  // 进行中的课程（落在 [start, end) 内）与下一节课（第一个尚未结束且非进行中的）。
  _Row? current;
  _Row? next;
  for (final _Row r in rows) {
    if (nowMin >= r.start && nowMin < r.end) {
      current = r;
    } else if (r.end > nowMin && next == null) {
      next = r;
    }
  }

  String curTag;
  String curName;
  String curRoom = '';
  String nextLine;
  String remainText = '';

  if (current != null) {
    curTag = '当前课程';
    curName = current.name;
    curRoom = _roomLabel(current.room);
    remainText = '剩余 ${current.end - nowMin} 分钟';
    nextLine = next != null
        ? '下一节课是:${next.name} ${ClassPeriod.formatMinutes(next.start)}'
        : '今天没有更多课了';
  } else if (next != null) {
    curTag = '下一节课';
    curName = next.name;
    curRoom = _roomLabel(next.room);
    // 再下一节（用于末行提示）。
    _Row? next2;
    for (final _Row r in rows) {
      if (r.start > next.start) {
        next2 = r;
        break;
      }
    }
    nextLine = next2 != null
        ? '再下一节:${next2.name} ${ClassPeriod.formatMinutes(next2.start)}'
        : '今天没有更多课了';
  } else {
    // 全天课程已结束。
    curTag = '全天课程结束';
    curName = '休息中';
    nextLine = '明天也要好好上课 ✨';
  }

  return WidgetSnapshot(
    dateKey: dateKeyOf(now),
    weekText: weekLabel,
    curTag: curTag,
    curName: curName,
    curRoom: curRoom,
    nextLine: nextLine,
    remainText: remainText,
    isDark: isDark,
    updatedAt: now.millisecondsSinceEpoch,
  );
}

/// 标题行副标题：「第 N 周 · 第 M 学期」（与鸿蒙版同文案）。
String weekTextOf(ScheduleMeta? meta, DateTime now) {
  final int week = meta?.effectiveWeek(now) ?? 1;
  final int term = meta?.term ?? 1;
  return '第 $week 周 · 第 $term 学期';
}

/// 教室行文本；无教室信息时返回空串（原生隐藏该行，不留占位）。
String _roomLabel(String room) => room.isEmpty ? '' : '教室:$room';

/// `yyyy-MM-dd`（本地时区）。
String dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 今日课程中间态（仅本文件使用）。
class _Row {
  const _Row({
    required this.name,
    required this.start,
    required this.end,
    required this.room,
  });

  final String name;
  final int start;
  final int end;
  final String room;
}
