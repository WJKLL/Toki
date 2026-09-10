// === 文件: test/widget_snapshot_test.dart ===
// 编号：S-26 · 桌面小组件快照构建单测（v1.51.1 焦点卡契约）
// 说明：buildTodaySnapshot 是纯函数（无 IO / 无通道），覆盖：
//   周次过滤（单双周 / 指定周）、节次时间缺失跳过、「上课中 / 下一节课 /
//   全天课程结束」三分支判定与文案、教室空值、无课表空态、JSON 载荷字段。
//   另回归 Course.periodLabel 跨节末节号（v1.51.0 修复的既有笔误）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/widget/widget_snapshot.dart';
import 'package:xiangjugong/domain/entities/class_period.dart';
import 'package:xiangjugong/domain/entities/course.dart';

void main() {
  // 2026-09-09 为周三。默认节次模板：第1节 08:00-08:45、第2节 08:55-09:40、
  // 第3节 09:50-10:35；第13-16 节默认 enabled=false。
  final DateTime wed0900 = DateTime(2026, 9, 9, 9, 0);
  const List<ClassPeriod> periods = ClassPeriod.defaults;
  const ScheduleMeta meta = ScheduleMeta(week: 12, term: 1);

  Course mk({
    required String id,
    required String name,
    required int day,
    required int start,
    int len = 1,
    WeekType week = WeekType.every,
    String? location,
    List<int> weeks = const <int>[],
  }) => Course(
    id: id,
    name: name,
    day: day,
    start: start,
    len: len,
    week: week,
    location: location,
    weeks: weeks,
  );

  WidgetSnapshot build(
    List<Course> courses, {
    DateTime? now,
    bool isDark = false,
    ScheduleMeta m = meta,
  }) => buildTodaySnapshot(
    courses: courses,
    periods: periods,
    meta: m,
    now: now ?? wed0900,
    isDark: isDark,
  );

  test('基准日前提：2026-09-09 是周三', () {
    expect(wed0900.weekday, 3);
  });

  group('空态', () {
    test('无课表 → 暂无课程 / 点击卡片去添加', () {
      final WidgetSnapshot s = build(<Course>[]);
      expect(s.curTag, '');
      expect(s.curName, '暂无课程');
      expect(s.nextLine, '点击卡片去添加');
      expect(s.curRoom, '');
      expect(s.remainText, '');
      expect(s.weekText, '第 12 周 · 第 1 学期');
      expect(s.dateKey, '2026-09-09');
    });

    test('今天没课（课程在别的星期）→ 同为暂无课程', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '周一的课', day: 1, start: 1),
      ]);
      expect(s.curName, '暂无课程');
    });

    test('节次时间缺失的课程被跳过（与鸿蒙版 CourseCardSync 一致）', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '晚课', day: 3, start: 13), // 第 13 节默认未启用
      ]);
      expect(s.curName, '暂无课程');
    });
  });

  group('上课中', () {
    test('09:00 落在第1-2节(08:00-09:40)内 → 当前课程 + 剩余 40 分钟', () {
      final WidgetSnapshot s = build(<Course>[
        mk(
          id: 'a',
          name: '高等数学',
          day: 3,
          start: 1,
          len: 2,
          location: 'A-301',
        ),
      ]);
      expect(s.curTag, '当前课程');
      expect(s.curName, '高等数学');
      expect(s.curRoom, '教室:A-301');
      expect(s.remainText, '剩余 40 分钟');
      expect(s.nextLine, '今天没有更多课了');
    });

    test('有后续课程 → 末行给出下一节', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '高等数学', day: 3, start: 1, len: 2),
        mk(id: 'b', name: '大学英语', day: 3, start: 3),
      ]);
      expect(s.curTag, '当前课程');
      expect(s.curName, '高等数学');
      expect(s.nextLine, '下一节课是:大学英语 09:50');
    });

    test('无教室 → curRoom 为空串（原生隐藏该行）', () {
      final WidgetSnapshot s = build(<Course>[
        mk(id: 'a', name: '高等数学', day: 3, start: 1, len: 2),
      ]);
      expect(s.curRoom, '');
    });
  });

  group('课前（下一节课）', () {
    test('07:00 尚未上课 → 下一节课 + 再下一节', () {
      final WidgetSnapshot s = build(
        <Course>[
          mk(
            id: 'a',
            name: '高等数学',
            day: 3,
            start: 1,
            len: 2,
            location: 'A-301',
          ),
          mk(id: 'b', name: '大学英语', day: 3, start: 3),
        ],
        now: DateTime(2026, 9, 9, 7, 0),
      );
      expect(s.curTag, '下一节课');
      expect(s.curName, '高等数学');
      expect(s.curRoom, '教室:A-301');
      expect(s.remainText, '');
      expect(s.nextLine, '再下一节:大学英语 09:50');
    });

    test('只有一节 → 末行为今天没有更多课了', () {
      final WidgetSnapshot s = build(
        <Course>[mk(id: 'a', name: '高等数学', day: 3, start: 1)],
        now: DateTime(2026, 9, 9, 7, 0),
      );
      expect(s.curTag, '下一节课');
      expect(s.nextLine, '今天没有更多课了');
    });
  });

  test('全天课程结束 → 休息中 + 明天也要好好上课 ✨', () {
    final WidgetSnapshot s = build(
      <Course>[mk(id: 'a', name: '高等数学', day: 3, start: 1)],
      now: DateTime(2026, 9, 9, 23, 0),
    );
    expect(s.curTag, '全天课程结束');
    expect(s.curName, '休息中');
    expect(s.curRoom, '');
    expect(s.remainText, '');
    expect(s.nextLine, '明天也要好好上课 ✨');
  });

  group('周次过滤', () {
    test('双周：单周课不参与', () {
      final WidgetSnapshot s = build(
        <Course>[
          mk(id: 'a', name: '单周课', day: 3, start: 1, week: WeekType.odd),
        ],
        m: const ScheduleMeta(week: 2, term: 1),
      );
      expect(s.curName, '暂无课程');
      expect(s.weekText, '第 2 周 · 第 1 学期');
    });

    test('指定周：weeks 命中才参与', () {
      final WidgetSnapshot s = build(
        <Course>[
          mk(
            id: 'a',
            name: '指定周课',
            day: 3,
            start: 1,
            len: 2,
            weeks: const <int>[11, 12, 13],
          ),
        ],
        m: const ScheduleMeta(week: 12, term: 1),
      );
      expect(s.curName, '指定周课');
      expect(s.curTag, '当前课程');
    });

    test('指定周：不在集合内 → 暂无课程', () {
      final WidgetSnapshot s = build(
        <Course>[
          mk(
            id: 'a',
            name: '指定周课',
            day: 3,
            start: 1,
            len: 2,
            weeks: const <int>[1, 2],
          ),
        ],
        m: const ScheduleMeta(week: 12, term: 1),
      );
      expect(s.curName, '暂无课程');
    });
  });

  group('JSON 载荷', () {
    test('含原生渲染所需的全部字段（契约 v2）', () {
      final WidgetSnapshot s = build(<Course>[
        mk(
          id: 'a',
          name: '高等数学',
          day: 3,
          start: 1,
          len: 2,
          location: 'A-301',
        ),
      ]);
      final Map<String, dynamic> j =
          jsonDecode(s.encode()) as Map<String, dynamic>;
      expect(j['v'], WidgetSnapshot.version);
      expect(j['v'], 2);
      expect(j['dateKey'], '2026-09-09');
      expect(j['weekText'], '第 12 周 · 第 1 学期');
      expect(j['curTag'], '当前课程');
      expect(j['curName'], '高等数学');
      expect(j['curRoom'], '教室:A-301');
      expect(j['remainText'], '剩余 40 分钟');
      expect(j['nextLine'], '今天没有更多课了');
      expect(j['isDark'], false);
      expect(j['updatedAt'], wed0900.millisecondsSinceEpoch);
    });

    test('empty() 生成空态快照', () {
      final WidgetSnapshot s = WidgetSnapshot.empty(
        now: wed0900,
        isDark: true,
        meta: meta,
      );
      expect(s.curName, '暂无课程');
      expect(s.nextLine, '点击卡片去添加');
      expect(s.dateKey, '2026-09-09');
      expect(s.weekText, '第 12 周 · 第 1 学期');
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
