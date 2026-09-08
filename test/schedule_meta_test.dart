// test/schedule_meta_test.dart
// ScheduleMeta.effectiveWeek(v1.49.3):自动周次派生 —— 无起始日回落手填;
// 有起始日按自然周推算(第 1 周 = 起始日窗口,每过 7 天 +1)。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/domain/entities/course.dart';

void main() {
  group('ScheduleMeta.effectiveWeek', () {
    test('无起始日 → 回落手填周次', () {
      const ScheduleMeta meta = ScheduleMeta(week: 3);
      expect(meta.effectiveWeek(DateTime(2026, 9, 8)), 3);
    });

    test('起始日当天 = 第 1 周', () {
      const ScheduleMeta meta = ScheduleMeta(
        week: 1,
        weekStartDate: '2026-09-01',
      );
      expect(meta.effectiveWeek(DateTime(2026, 9, 1)), 1);
      expect(meta.effectiveWeek(DateTime(2026, 9, 7)), 1);
    });

    test('过 7 天自动 +1(9/8 → 第 2 周)', () {
      const ScheduleMeta meta = ScheduleMeta(
        week: 1,
        weekStartDate: '2026-09-01',
      );
      expect(meta.effectiveWeek(DateTime(2026, 9, 8)), 2);
      expect(meta.effectiveWeek(DateTime(2026, 9, 14)), 2);
      expect(meta.effectiveWeek(DateTime(2026, 9, 15)), 3);
    });

    test('跨月/跨年自然滚动', () {
      const ScheduleMeta meta = ScheduleMeta(
        week: 1,
        weekStartDate: '2026-09-01',
      );
      expect(meta.effectiveWeek(DateTime(2027, 1, 1)), 18);
    });

    test('起始日非法 → 回落手填', () {
      const ScheduleMeta meta = ScheduleMeta(
        week: 5,
        weekStartDate: 'not-a-date',
      );
      expect(meta.effectiveWeek(DateTime(2026, 9, 8)), 5);
    });

    test('json 往返保留 weekStartDate', () {
      const ScheduleMeta meta = ScheduleMeta(
        grade: '大三',
        term: 5,
        week: 2,
        weekStartDate: '2026-09-01',
      );
      final ScheduleMeta back = ScheduleMeta.fromJson(meta.toJson());
      expect(back.grade, '大三');
      expect(back.term, 5);
      expect(back.weekStartDate, '2026-09-01');
      expect(back.effectiveWeek(DateTime(2026, 9, 8)), 2);
    });
  });
}
