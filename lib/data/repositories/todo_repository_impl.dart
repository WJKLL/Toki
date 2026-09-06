// lib/data/repositories/todo_repository_impl.dart
// 编号：S-23 待办数据服务（实现：shared_preferences + JSON）
// 说明：与 course/settings repository 同模式 —— 读走内存缓存（同步），
//   写全量 JSON 串异步落盘。key：
//   - todo.items     待办全量（含完成/未完成）
//   - todo.archived  归档精简列表
//   - flowchart_$id  流程图 JSON（v1.44.0 写入；清理/删除按此 key 操作）
// 功耗：getString 为内存读零 IO；写由调用方（Provider）节流。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/todo_item.dart';
import '../../domain/repositories/todo_repository.dart';

class TodoRepositoryImpl implements TodoRepository {
  TodoRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  static const String _kTodos = 'todo.items';
  static const String _kArchived = 'todo.archived';
  static const String _kFlowPrefix = 'flowchart_';

  @override
  List<TodoItem> loadTodos() {
    final String? raw = _prefs.getString(_kTodos);
    if (raw == null || raw.isEmpty) return const <TodoItem>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return <TodoItem>[
        for (final Object? o in list)
          if (o is Map<String, dynamic>) TodoItem.fromJson(o),
      ];
    } on FormatException {
      return const <TodoItem>[];
    }
  }

  @override
  Future<void> saveTodos(List<TodoItem> todos) async {
    await _prefs.setString(
      _kTodos,
      jsonEncode(<Map<String, dynamic>>[
        for (final TodoItem t in todos) t.toJson(),
      ]),
    );
  }

  @override
  List<ArchivedTodo> loadArchived() {
    final String? raw = _prefs.getString(_kArchived);
    if (raw == null || raw.isEmpty) return const <ArchivedTodo>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return <ArchivedTodo>[
        for (final Object? o in list)
          if (o is Map<String, dynamic>) ArchivedTodo.fromJson(o),
      ];
    } on FormatException {
      return const <ArchivedTodo>[];
    }
  }

  @override
  Future<void> saveArchived(List<ArchivedTodo> archived) async {
    await _prefs.setString(
      _kArchived,
      jsonEncode(<Map<String, dynamic>>[
        for (final ArchivedTodo a in archived) a.toJson(),
      ]),
    );
  }

  @override
  Future<void> cleanupExpiredFlows() async {
    // 已完成且 now > 截止日次日 + 15 天 → 删流程图 key（保留 TodoItem）。
    final DateTime now = DateTime.now();
    for (final TodoItem t in loadTodos()) {
      if (!t.isCompleted) continue;
      final DateTime start = DateTime(t.date.year, t.date.month, t.date.day)
          .add(const Duration(days: 1));
      final DateTime end = start.add(kTodoExportWindow);
      if (now.isAfter(end)) {
        await _prefs.remove('$_kFlowPrefix${t.id}');
      }
    }
  }

  @override
  Future<void> deleteFlowchart(String todoId) async {
    await _prefs.remove('$_kFlowPrefix$todoId');
  }

  @override
  String? loadFlowchart(String todoId) {
    return _prefs.getString('$_kFlowPrefix$todoId');
  }

  @override
  Future<void> saveFlowchart(String todoId, String json) async {
    await _prefs.setString('$_kFlowPrefix$todoId', json);
  }
}
