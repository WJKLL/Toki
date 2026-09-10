// === 文件: lib/domain/entities/course_span.dart ===
// 编号：S-15 内部件 · 课程整段计时（v1.51.0 提取）
// 说明：把「课程覆盖的启用节次」折算为当日整段起止分钟（0 点起）。
//   原实现是 course_reminder_bridge 的私有 _Span；v1.51.0 桌面小组件（S-26）
//   同样需要「开始-结束」时刻，故提取为共享纯函数，避免两处逻辑漂移。
//   纯领域逻辑，不依赖 UI。
import 'class_period.dart';
import 'course.dart';

/// 课程覆盖启用节次的整段计时（分钟；0 点起）。
class CourseSpan {
  const CourseSpan(this.start, this.end);

  /// 首个启用节次的开始分钟。
  final int start;

  /// 末个启用节次的结束分钟。
  final int end;

  /// 整段时长（分钟）。
  int get totalMinutes => end - start;
}

/// 该课覆盖节次的**整段起止分钟**；覆盖节次全未启用 → null（时间缺失）。
/// 与 course_reminder_bridge 原 `_spanOf` 算法逐字一致（首末节次 clamp 后
/// 取首个启用节的 start 与末个启用节的 end）。
CourseSpan? courseSpanOf(Course c, List<ClassPeriod> periods) {
  if (periods.isEmpty) return null;
  final int first = (c.start - 1).clamp(0, periods.length - 1);
  final int last = (c.start + c.len - 2).clamp(first, periods.length - 1);
  int? start;
  int end = 0;
  for (int i = first; i <= last; i++) {
    final ClassPeriod p = periods[i];
    if (p.enabled && p.endMinutes > p.startMinutes) {
      start ??= p.startMinutes;
      end = p.endMinutes;
    }
  }
  if (start == null || end <= start) return null;
  return CourseSpan(start, end);
}
