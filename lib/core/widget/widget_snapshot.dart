// === 文件: lib/core/widget/widget_snapshot.dart ===
// 编号：S-26 内部件 · 桌面小组件快照（v1.51.0）
// 说明：Flutter 侧把「今日课程」算好并序列化为 JSON 交给原生渲染。
//   本文件**纯逻辑**（无 IO、无 UI、无平台通道），全部可单测。
//   今日课程筛选与时刻换算与 course_reminder_bridge 同源（courseSpanOf），
//   不复制业务规则 —— 避免「通知说第 3-4 节、卡片说第 3 节」这类漂移。
import 'dart:convert';

import '../../domain/entities/class_period.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/course_span.dart';

/// 今日课程单行：课程名 → 时间 → 课室。
class WidgetCourseRow {
  const WidgetCourseRow({
    required this.name,
    required this.time,
    required this.room,
    required this.state,
    required this.color,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// 课程名。
  final String name;

  /// 时间列：`08:00-09:40`；节次时间未设置时退化为 `第1-2节`。
  final String time;

  /// 课室列（`Course.location`，可为空串 —— 卡片留空不占位）。
  final String room;

  /// 状态：`ongoing` / `upcoming` / `past`（原生据此高亮进行中）。
  final String state;

  /// 课程色（`Course.colorValue`，ARGB int）；仅 `ongoing` 行使用。
  final int color;

  /// 该课整段开始分钟（当日 0 点起）；-1 = 节次时间缺失。
  /// 原生侧据此**按当前时刻重算** [state]：课程闹钟 / 周期刷新时 App 可能
  /// 并未运行，只有靠这两个数才能让「上课中 / 已结束」在无人干预时也对。
  final int startMinutes;

  /// 该课整段结束分钟；-1 = 节次时间缺失。
  final int endMinutes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'time': time,
    'room': room,
    'state': state,
    'color': color,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
  };
}

/// 今日课程快照：原生侧渲染的唯一数据源。
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.dateKey,
    required this.dayLabel,
    required this.total,
    required this.courses,
    required this.isDark,
    required this.updatedAt,
  });

  /// 载荷格式版本（原生据此判兼容；未知版本按空态渲染）。
  static const int version = 1;

  /// 卡面最多显示的行数（超出部分走「… 等 N 门」）。
  static const int maxRows = 3;

  /// 日期键 `yyyy-MM-dd`；原生比对当日日期，不一致视为过期数据。
  final String dateKey;

  /// 标题用星期文本，如「周三」。
  final String dayLabel;

  /// 今日课程总门数（含未在卡面展示的）。
  final int total;

  /// 今日课程行（**全部**今日课程；原生只渲染前 [maxRows] 行）。
  final List<WidgetCourseRow> courses;

  /// 亮暗模式 → 原生切换 `widget_bg_light` / `widget_bg_dark`。
  final bool isDark;

  /// 写入时间戳（毫秒；诊断用）。
  final int updatedAt;

  /// 今日无课。
  bool get isEmpty => total == 0;

  /// 未在卡面展示的门数（「… 等 N 门」）。
  int get overflow => total > maxRows ? total - maxRows : 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': version,
    'updatedAt': updatedAt,
    'dateKey': dateKey,
    'dayLabel': dayLabel,
    'total': total,
    'isDark': isDark,
    'courses': courses.map((WidgetCourseRow r) => r.toJson()).toList(),
  };

  /// 编码为写入原生的 JSON 文本。
  String encode() => jsonEncode(toJson());

  /// 空态快照（课程为空 / 需清空时的兜底）。
  static WidgetSnapshot empty({
    required DateTime now,
    required bool isDark,
  }) => WidgetSnapshot(
    dateKey: dateKeyOf(now),
    dayLabel: Course.dayLabel(now.weekday),
    total: 0,
    courses: const <WidgetCourseRow>[],
    isDark: isDark,
    updatedAt: now.millisecondsSinceEpoch,
  );
}

/// 由课表数据构建今日课程快照（纯函数，可直接单测）。
///
/// 筛选口径与 course_reminder_bridge._scheduleCourseAlarms 一致：
/// `c.day == 当日星期 && c.showsOn(effectiveWeek)`。
WidgetSnapshot buildTodaySnapshot({
  required List<Course> courses,
  required List<ClassPeriod> periods,
  required int effectiveWeek,
  required DateTime now,
  required bool isDark,
}) {
  final int weekday = now.weekday; // 1=周一 .. 7=周日
  final int nowMinutes = now.hour * 60 + now.minute;

  // 今日课程 + 一次算好整段计时（排序与渲染共用，避免重复换算）。
  final List<({Course course, CourseSpan? span})> today =
      <({Course course, CourseSpan? span})>[];
  for (final Course c in courses) {
    if (c.day != weekday) continue;
    if (!c.showsOn(effectiveWeek)) continue;
    today.add((course: c, span: courseSpanOf(c, periods)));
  }
  // 按开始时刻升序；时间缺失者排在末尾（保持相对稳定，不影响可读性）。
  const int kNoTime = 1 << 30;
  today.sort(
    (({Course course, CourseSpan? span}) a, ({Course course, CourseSpan? span}) b) =>
        (a.span?.start ?? kNoTime).compareTo(b.span?.start ?? kNoTime),
  );

  final List<WidgetCourseRow> rows = <WidgetCourseRow>[
    for (final ({Course course, CourseSpan? span}) item in today)
      WidgetCourseRow(
        name: item.course.name,
        time: item.span == null
            ? Course.periodLabel(item.course.start, item.course.len)
            : '${ClassPeriod.formatMinutes(item.span!.start)}-'
                  '${ClassPeriod.formatMinutes(item.span!.end)}',
        room: item.course.location?.trim() ?? '',
        state: _stateOf(item.span, nowMinutes),
        color: item.course.colorValue,
        startMinutes: item.span?.start ?? -1,
        endMinutes: item.span?.end ?? -1,
      ),
  ];

  return WidgetSnapshot(
    dateKey: dateKeyOf(now),
    dayLabel: Course.dayLabel(weekday),
    total: rows.length,
    courses: rows,
    isDark: isDark,
    updatedAt: now.millisecondsSinceEpoch,
  );
}

/// 单门课相对当前时刻的状态。时间缺失（节次未启用）无法判定 → 按未开始处理。
String _stateOf(CourseSpan? span, int nowMinutes) {
  if (span == null) return 'upcoming';
  if (nowMinutes >= span.end) return 'past';
  if (nowMinutes >= span.start) return 'ongoing';
  return 'upcoming';
}

/// `yyyy-MM-dd`（本地时区）。
String dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
