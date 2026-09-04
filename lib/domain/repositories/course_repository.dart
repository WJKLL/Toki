// lib/domain/repositories/course_repository.dart
// 编号：S-15 课表数据服务（v1.15.0，P-06 大课表 + 首页迷你课表）
// 说明：领域层仓储抽象。实现位于 data/（shared_preferences + JSON 序列化）。
import '../entities/course.dart';

abstract class CourseRepository {
  /// 同步读取内存缓存中的课程列表（SharedPreferences getInstance 后为内存态）。
  List<Course> load();

  /// 持久化课程列表（异步写盘）。
  Future<void> save(List<Course> courses);

  /// 同步读取学期信息（年级/学期/当前周次）。
  ScheduleMeta loadMeta();

  /// 持久化学期信息。
  Future<void> saveMeta(ScheduleMeta meta);
}
