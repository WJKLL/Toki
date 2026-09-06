// lib/presentation/providers/course_provider.dart
// 编号：S-15 课表状态管理（v1.16.0 重构）
// 说明：课程列表 + 学期信息 Riverpod 状态 —— AsyncNotifier 加载 + 增删改，
//       改后自动持久化（S-15 CourseRepository）。首页迷你课表 / 大课表共享，
//       任一处修改自动同步（Riverpod 自动重建）。
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/excel/excel_timetable_parser.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/class_period.dart';
import '../../domain/entities/course.dart';
import '../../domain/repositories/course_repository.dart';
import 'settings_providers.dart';

/// 课表仓储（main.dart override 注入，与 S-02 共用 SharedPreferences 实例）。
final courseRepositoryProvider = Provider<CourseRepository>(
  (ref) => throw UnimplementedError(
    'courseRepositoryProvider must be overridden in main()',
  ),
);

/// 课程列表状态（加载 + 增删改，改后自动持久化）。
final courseListProvider =
    AsyncNotifierProvider<CourseListNotifier, List<Course>>(
      CourseListNotifier.new,
    );

class CourseListNotifier extends AsyncNotifier<List<Course>> {
  @override
  Future<List<Course>> build() async {
    return ref.read(courseRepositoryProvider).load();
  }

  /// 新增课程（自动生成唯一 id；colorValue 缺省按课程名 auto 分配）。
  /// v1.42.0:支持具体周次 [weeks](起止周手动编辑,与导入课同语义)。
  Future<void> addCourse({
    required String name,
    required int day,
    required int start,
    int len = 1,
    WeekType week = WeekType.every,
    List<int> weeks = const <int>[],
    int? colorValue,
    String? location,
    String? teacher,
  }) async {
    final String id = _genId();
    final List<Course> courses = <Course>[...?state.value];
    courses.add(
      Course(
        id: id,
        name: name,
        day: day,
        start: start,
        len: len,
        week: week,
        weeks: weeks,
        colorValue: colorValue ?? Course.autoColor(name),
        location: location,
        teacher: teacher,
      ),
    );
    await _persist(courses);
  }

  /// v1.17.0（S-18 导入）：Excel 课表合并导入 —— 按 星期×节次 定位，
  /// 同格课程替换（保留原 id / day / start，更新其余字段），其余保留；
  /// 新格子生成新 id。导入课程统一按具体周次（weeks）显示。
  Future<void> importCourses(List<ParsedCourse> parsed) async {
    final List<Course> courses = <Course>[...?state.value];
    final Map<String, int> keyToIndex = <String, int>{};
    for (int i = 0; i < courses.length; i++) {
      keyToIndex['${courses[i].day}-${courses[i].start}'] = i;
    }
    for (final ParsedCourse p in parsed) {
      final String key = '${p.day}-${p.start}';
      final int? i = keyToIndex[key];
      if (i != null) {
        final Course old = courses[i];
        courses[i] = old.copyWith(
          name: p.name,
          len: p.len,
          colorValue: p.colorValue,
          location: p.location,
          teacher: p.teacher,
          weeks: p.weeks,
        );
      } else {
        courses.add(
          Course(
            id: _genId(),
            name: p.name,
            day: p.day,
            start: p.start,
            len: p.len,
            week: WeekType.every,
            colorValue: p.colorValue,
            location: p.location,
            teacher: p.teacher,
            weeks: p.weeks,
          ),
        );
        keyToIndex[key] = courses.length - 1;
      }
    }
    await _persist(courses);
  }

  static String _genId() =>
      '${DateTime.now().millisecondsSinceEpoch}'
      '${math.Random().nextInt(0xFFFF).toRadixString(16)}';

  /// 更新课程。
  Future<void> updateCourse(Course course) async {
    final List<Course> courses = <Course>[...?state.value];
    final int i = courses.indexWhere((Course c) => c.id == course.id);
    if (i < 0) return;
    courses[i] = course;
    await _persist(courses);
  }

  /// 删除课程。
  Future<void> deleteCourse(String id) async {
    final List<Course> courses = <Course>[...?state.value];
    courses.removeWhere((Course c) => c.id == id);
    await _persist(courses);
  }

  Future<void> _persist(List<Course> courses) async {
    state = AsyncData<List<Course>>(courses);
    await ref.read(courseRepositoryProvider).save(courses);
  }
}

/// 学期信息（年级 / 学期 / 当前周次，参考勾丰小站 sched-meta）。
final scheduleMetaProvider =
    AsyncNotifierProvider<ScheduleMetaNotifier, ScheduleMeta>(
      ScheduleMetaNotifier.new,
    );

class ScheduleMetaNotifier extends AsyncNotifier<ScheduleMeta> {
  @override
  Future<ScheduleMeta> build() async {
    return ref.read(courseRepositoryProvider).loadMeta();
  }

  Future<void> saveMeta(ScheduleMeta meta) async {
    state = AsyncData<ScheduleMeta>(meta);
    await ref.read(courseRepositoryProvider).saveMeta(meta);
  }
}

// ── v1.21.0(A-04/C-33):当前课程倒计时 ─────────────────────────────

/// 当前进行中的课程(值对象,卡片 select 最小监听)。
/// [timeMissing] = 该课覆盖的节次在时间表中全部未设置时间(提示去课表页)。
class CurrentClass {
  const CurrentClass({
    required this.course,
    required this.periodLabel,
    required this.spanStartLabel,
    required this.spanEndLabel,
    required this.totalMinutes,
    required this.leftMinutes,
    this.timeMissing = false,
  });

  /// 有课但覆盖节次均无启用时间段(只显示课程名 + 提示)。
  factory CurrentClass.missing(Course course) => CurrentClass(
    course: course,
    periodLabel: Course.periodLabel(course.start, course.len),
    spanStartLabel: '',
    spanEndLabel: '',
    totalMinutes: 0,
    leftMinutes: 0,
    timeMissing: true,
  );

  final Course course;

  /// 「第 1-2 节」文本。
  final String periodLabel;

  /// 整段计时起止(如 08:00 / 09:40);timeMissing 时为空串。
  final String spanStartLabel;
  final String spanEndLabel;

  /// 课程整段总分钟(跨节含课间,如 100)。
  final int totalMinutes;

  /// 剩余分钟(0..total)。
  final int leftMinutes;

  /// 该课节次无时间设置(时间表未启用)。
  final bool timeMissing;

  /// 剩余比例 0..1(上课满环 → 下课空环)。
  double get ratio =>
      totalMinutes <= 0 ? 0 : (leftMinutes / totalMinutes).clamp(0.0, 1.0);

  /// 剩余百分比文本(与圆环比例一致,0..100 取整)。
  String get leftText {
    final int percent = totalMinutes <= 0
        ? 0
        : (leftMinutes * 100 / totalMinutes).round().clamp(0, 100);
    return '剩余 $percent%';
  }
}

/// 当前课程派生:节次时间表(启用段) ∩ 今日课表(day + 当前周次过滤) ∩ 覆盖节次。
/// 刷新:首页倒计时卡每分钟 ref.invalidate 本 provider(读新 DateTime.now())。
/// 边界:当前不在任何启用节次内 → null(休息);跨节课按「首节起 ~ 末节止」
///   整段计时(覆盖节次中启用的首末段,课间计入);覆盖节次全未启用 → timeMissing。
final currentClassProvider = Provider<CurrentClass?>((ref) {
  final List<Course> courses =
      ref.watch(courseListProvider).value ?? const <Course>[];
  final ScheduleMeta meta =
      ref.watch(scheduleMetaProvider).value ?? const ScheduleMeta();
  final List<ClassPeriod> periods = ref.watch(
    appSettingsProvider.select((AppSettings s) => s.classPeriods),
  );
  if (periods.isEmpty) return null;
  final DateTime now = DateTime.now();
  final int weekday = now.weekday; // 1=周一..7=周日
  final int nowMinutes = now.hour * 60 + now.minute;

  // 1) 当前处于第几节(0 基):首个覆盖 nowMinutes 的启用时间段。
  int? activeIndex;
  for (int i = 0; i < periods.length; i++) {
    final ClassPeriod p = periods[i];
    if (p.enabled &&
        p.endMinutes > p.startMinutes &&
        nowMinutes >= p.startMinutes &&
        nowMinutes < p.endMinutes) {
      activeIndex = i;
      break;
    }
  }
  if (activeIndex == null) return null; // 休息/课间/未设时间

  // 2) 今日且有该节次的课程(周次过滤:weeks 精确 / 单双周三态)。
  final int periodNo = activeIndex + 1; // 1 基
  Course? course;
  for (final Course c in courses) {
    if (c.day != weekday) continue;
    if (!c.showsOn(meta.week)) continue;
    if (periodNo >= c.start && periodNo < c.start + c.len) {
      course = c;
      break;
    }
  }
  if (course == null) return null; // 该节次无课(休息)

  // 3) 整段计时:课程覆盖节次(1 基 c.start .. c.start+len-1)中启用时段的首末。
  final int firstIndex = (course.start - 1).clamp(0, periods.length - 1);
  final int lastIndex = (course.start + course.len - 2).clamp(
    firstIndex,
    periods.length - 1,
  );
  final List<ClassPeriod> covered = <ClassPeriod>[];
  for (int i = firstIndex; i <= lastIndex; i++) {
    final ClassPeriod p = periods[i];
    if (p.enabled && p.endMinutes > p.startMinutes) covered.add(p);
  }
  if (covered.isEmpty) return CurrentClass.missing(course);

  final int spanStart = covered.first.startMinutes;
  final int spanEnd = covered.last.endMinutes;
  final int total = spanEnd - spanStart;
  int left = spanEnd - nowMinutes;
  if (left < 0) left = 0;
  if (left > total) left = total; // 未开始兜底
  return CurrentClass(
    course: course,
    periodLabel: Course.periodLabel(course.start, course.len),
    spanStartLabel: ClassPeriod.formatMinutes(spanStart),
    spanEndLabel: ClassPeriod.formatMinutes(spanEnd),
    totalMinutes: total,
    leftMinutes: left,
  );
});

/// 下一节课(值对象):今天、当前课结束后最近一节「启用节次 + 有课」。
class NextClass {
  const NextClass({
    required this.course,
    required this.periodLabel,
    required this.startLabel,
  });

  final Course course;

  /// 「第 3 节」文本(跨节课显示首节)。
  final String periodLabel;

  /// 开始时刻「09:50」。
  final String startLabel;
}

/// 第 [periodNo](1 基)节今天的课程(单双周/weeks 过滤);无则 null。
Course? _todayCourseAt(
  int periodNo,
  List<Course> courses,
  ScheduleMeta meta,
  int weekday,
) {
  for (final Course c in courses) {
    if (c.day != weekday) continue;
    if (!c.showsOn(meta.week)) continue;
    if (periodNo >= c.start && periodNo < c.start + c.len) return c;
  }
  return null;
}

/// 下一节课派生:跳过「当前课(含跨节覆盖)」与「已结束/未启用」节次,
/// 返回下一个有课的启用节;null = 今天没有更多课(或课表为空)。
/// 刷新:首页组合卡每分钟 invalidate(与 currentClassProvider 同机制)。
final nextClassProvider = Provider<NextClass?>((ref) {
  final List<Course> courses =
      ref.watch(courseListProvider).value ?? const <Course>[];
  final ScheduleMeta meta =
      ref.watch(scheduleMetaProvider).value ?? const ScheduleMeta();
  final List<ClassPeriod> periods = ref.watch(
    appSettingsProvider.select((s) => s.classPeriods),
  );
  if (courses.isEmpty || periods.isEmpty) return null;
  final DateTime now = DateTime.now();
  final int weekday = now.weekday;
  final int nowMinutes = now.hour * 60 + now.minute;

  // 当前课(含跨节)覆盖的末节(1 基);无课/未设时间 → 0(从头找)。
  final CurrentClass? cur = ref.watch(currentClassProvider);
  final int skipThrough = (cur != null && !cur.timeMissing)
      ? cur.course.start + cur.course.len - 1
      : 0;

  for (int i = 0; i < periods.length; i++) {
    final ClassPeriod p = periods[i];
    if (!p.enabled || p.endMinutes <= p.startMinutes) continue;
    if (p.endMinutes <= nowMinutes) continue; // 本节已结束
    final int periodNo = i + 1;
    if (periodNo <= skipThrough) continue; // 仍在当前课内
    final Course? course = _todayCourseAt(periodNo, courses, meta, weekday);
    if (course == null) continue; // 本节无课(课间/自习)
    return NextClass(
      course: course,
      periodLabel: Course.periodLabel(course.start, course.len),
      startLabel: ClassPeriod.formatMinutes(p.startMinutes),
    );
  }
  return null; // 今天没有更多课了
});
