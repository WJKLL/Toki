// lib/data/repositories/course_repository_impl.dart
// 编号：S-15 课表数据服务（实现：shared_preferences + JSON 序列化）
// 说明：课程列表持久化 —— 整体 JSON 字符串存 SharedPreferences（key course.list）。
//       读走内存缓存零 IO；写一次性 setString（课程量小，无需防抖）。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/course.dart';
import '../../domain/repositories/course_repository.dart';

class CourseRepositoryImpl implements CourseRepository {
  CourseRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  static const String _kCourseList = 'course.list';
  static const String _kCourseMeta = 'course.meta';

  @override
  List<Course> load() {
    final String? raw = _prefs.getString(_kCourseList);
    if (raw == null || raw.isEmpty) return const <Course>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((dynamic e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 数据损坏兜底：返回空列表（下次保存覆盖）。
      return const <Course>[];
    }
  }

  @override
  Future<void> save(List<Course> courses) async {
    final String raw = jsonEncode(
      courses.map((Course e) => e.toJson()).toList(),
    );
    await _prefs.setString(_kCourseList, raw);
  }

  @override
  ScheduleMeta loadMeta() {
    final String? raw = _prefs.getString(_kCourseMeta);
    if (raw == null || raw.isEmpty) return const ScheduleMeta();
    try {
      return ScheduleMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ScheduleMeta();
    }
  }

  @override
  Future<void> saveMeta(ScheduleMeta meta) async {
    await _prefs.setString(_kCourseMeta, jsonEncode(meta.toJson()));
  }
}
