// === 文件: test/widget_snapshot_test.dart ===
// 编号：S-26 · 桌面小组件快照构建单测（v1.51.0）
// 说明：buildTodaySnapshot 是纯函数（无 IO / 无通道），覆盖四个易错点：
//   今日筛选（含单双周 / 指定周过滤）、时刻换算（含节次未启用退化）、
//   ongoing / past / upcoming 判定、按开始时刻排序。
//   另回归 Course.periodLabel 跨节末节号（v1.51.0 修复的既有笔误）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/widget/widget_snapshot.dart';
import 'package:xiangjugong/domain/entities/class_period.dart';
import 'package:xiangjugong/domain/entities/course.dart';

void main() {
  // 2026-09-09 为周三（weekday == 3）；下面所有用例以此为「今天 09:00」。
  final DateTime wed0900 = DateTime(2026, 9, 9, 9, 0);
  // 默认节次模板：第1节 08:00-08:45、第2节 08:55-09:40、第3节 09:50-10:35，
  // 第13-16 节默认 enabled=false。
  const List<ClassPeriod> periods = ClassPeriod.defaults;

  Course mk({
    required String id,
    required String name,
    required int day,
    required int start,
    int len = 1,
    WeekType week = WeekType.every,
    String? location,
    List<int> weeks = const <int>[],
    int colorValue = 0xFF0080FF,
  }) => Course(
    id: id,
    name: name,
    day: day,
    start: start,
    len: len,
    week: week,
    location: location,
    weeks: weeks,
    colorValue: colorValue,
  );

  WidgetSnapshot build(
    List<Course> courses, {
    int effectiveWeek = 1,
    DateTime? now,
    bool isDark = false,
  }) => buildTodaySnapshot(
    courses: courses,
    periods: periods,
    effectiveWeek: effectiveWeek,
    now: now ?? wed0900,
    isDark: isDark,
  );

  test('基准日前提：2026-09-09 是周三', () {
    expect(wed0900.weekday, 3);
  });

  group('今日筛选', () {
    test('只取当天，且单双周 / 指定周过滤生效', () {
      final WidgetSnapshot s = build(
        <Course>[
          mk(id: 'a', name: '高等数学', day: 3, start: 1, len: 2, location: 'A-301'),
          mk(id: 'b', name: '周二的课', day: 2, start: 1),
          mk(id: 'c', name: '单周课', day: 3, start: 3, week: WeekType.odd),
          mk(id: 'd', name: '指定周课', day: 3, start: 5, weeks: const <int>[1, 2]),
        ],
        effectiveWeek: 2, // 双周
      );
      // b 非当天；c 单周课在双周不显示；a、d 保留。
      expect(s.courses.map((WidgetCourseRow r) => r.name).toList(), <String>[
        '高等数学',
        '指定周课',
      ]);
      expect(s.total, 2);
      expect(s.dayLabel, '周三');
      expect(s.dateKey, '2026-09-09');
    });

    test('今日无课 → total 0 / isEmpty', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '别的天的课', day: 1, start: 1),
      ]);
      expect(s.total, 0);
      expect(s.isEmpty, isTrue);
      expect(s.overflow, 0);
      expect(s.courses, isEmpty);
    });
  });

  group('时间列', () {
    test('节次已启用 → 起止时刻', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '高等数学', day: 3, start: 1, len: 2),
      ]);
      expect(s.courses.single.time, '08:00-09:40');
    });

    test('节次未启用（时间缺失）→ 退化为节次文本，分钟数记 -1', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'b', name: '晚课', day: 3, start: 13),
      ]);
      expect(s.courses.single.time, '第13节');
      expect(s.courses.single.startMinutes, -1);
      expect(s.courses.single.endMinutes, -1);
    });

    test('课室：可为空（空串不占位），有值去首尾空格', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '无教室', day: 3, start: 1),
        mk(id: 'b', name: '有教室', day: 3, start: 2, location: '  B-202  '),
      ]);
      expect(s.courses[0].room, '');
      expect(s.courses[1].room, 'B-202');
    });
  });

  group('状态判定', () {
    test('09:00 → 第1节已过 / 第2节进行中 / 第3节未开始', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '第一节', day: 3, start: 1),
        mk(id: 'b', name: '第二节', day: 3, start: 2),
        mk(id: 'c', name: '第三节', day: 3, start: 3),
      ]);
      expect(s.courses.map((WidgetCourseRow r) => r.state).toList(), <String>[
        'past',
        'ongoing',
        'upcoming',
      ]);
    });

    test('时间缺失的课程按未开始处理（无法判定）', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '晚课', day: 3, start: 13),
      ]);
      expect(s.courses.single.state, 'upcoming');
    });
  });

  test('按开始时刻升序排序，与录入顺序无关', () {
    final WidgetSnapshot s = build(<Course>[
      mk(id: 'c', name: '第三节', day: 3, start: 3),
      mk(id: 'a', name: '第一节', day: 3, start: 1),
      mk(id: 'b', name: '第二节', day: 3, start: 2),
    ]);
    expect(s.courses.map((WidgetCourseRow r) => r.name).toList(), <String>[
      '第一节',
      '第二节',
      '第三节',
    ]);
  });

  test('overflow：超过 3 行时给出「… 等 N 门」的基数', () {
    final WidgetSnapshot s = build(<Course>[
      for (int i = 1; i <= 5; i++) mk(id: 'c$i', name: '课$i', day: 3, start: i),
    ]);
    expect(s.total, 5);
    expect(s.courses.length, 5); // 全部交给原生，由原生只渲染前 maxRows 行
    expect(s.overflow, 2);
    expect(WidgetSnapshot.maxRows, 3);
  });

  group('JSON 载荷', () {
    test('含原生渲染所需全部字段', () {
      final WidgetSnapshot s = build(<Course>[
        mk(
          id: 'a',
          name: '高等数学',
          day: 3,
          start: 1,
          len: 2,
          location: 'A-301',
          colorValue: 0xFFDA2828,
        ),
      ]);
      final Map<String, dynamic> j =
          jsonDecode(s.encode()) as Map<String, dynamic>;
      expect(j['v'], WidgetSnapshot.version);
      expect(j['dateKey'], '2026-09-09');
      expect(j['dayLabel'], '周三');
      expect(j['total'], 1);
      expect(j['isDark'], false);
      expect(j['updatedAt'], wed0900.millisecondsSinceEpoch);
      final Map<String, dynamic> row =
          (j['courses'] as List<dynamic>).first as Map<String, dynamic>;
      expect(row['name'], '高等数学');
      expect(row['time'], '08:00-09:40');
      expect(row['room'], 'A-301');
      // 09:00 落在第1-2节 08:00-09:40 区间内 → 进行中。
      expect(row['state'], 'ongoing');
      expect(row['color'], 0xFFDA2828);
      // 原生据此按当前墙钟重算状态（App 未运行时也能正确显示上课中/已结束）。
      expect(row['startMinutes'], 480); // 08:00
      expect(row['endMinutes'], 580); // 09:40
    });

    test('empty() 生成空态快照（无课 / 清空兜底）', () {
      final WidgetSnapshot s = WidgetSnapshot.empty(
        now: wed0900,
        isDark: true,
      );
      expect(s.isEmpty, isTrue);
      expect(s.total, 0);
      expect(s.dateKey, '2026-09-09');
      expect(s.dayLabel, '周三');
      expect(s.courses, isEmpty);
      expect(s.isDark, isTrue);
    });
  });

  group('Course.periodLabel（v1.51.0 修复跨节末节号）', () {
    test('单节 / 跨节末节号正确', () {
      expect(Course.periodLabel(3, 1), '第3节');
      expect(Course.periodLabel(3, 2), '第3-4节');
      expect(Course.periodLabel(1, 4), '第1-4节');
    });
  });
}
