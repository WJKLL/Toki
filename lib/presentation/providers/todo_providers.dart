// lib/presentation/providers/todo_providers.dart
// 编号：S-23 待办状态管理（v1.43.0，P-10 待办 + P-12 回收站）
// 说明：待办全量 + 归档精简两路 Riverpod 状态 —— AsyncNotifier 加载 + CRUD；
//   任一处修改自动持久化（首页待办 / 回收站共享，自动同步）。
//   - 归档(完成) / 恢复 / 永久删除在 TodoListNotifier 统一收口；
//   - 归档列表变更后 invalidate(archivedListProvider) 重读（简单可靠）；
//   - build() 先跑过期流程图清理（已完成超窗 → 删 flowchart key）。
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/todo_item.dart';
import '../../domain/repositories/todo_repository.dart';

/// 待办统计快照(v1.49.0,首页 C-29 待办卡)。
/// 口径:总任务 = 全量条目;待办 = 未完成;今日完成 = 归档 completedAt 今天;
/// 逾期/今天/未来 = 未完成按截止日分组(今天=日期部分当天)。
class TodoOverview {
  const TodoOverview({
    required this.total,
    required this.pending,
    required this.doneToday,
    required this.doneAll,
    required this.overdue,
    required this.dueToday,
    required this.upcoming,
  });

  /// 总任务(items 全量)。
  final int total;

  /// 当前待办(未完成总数)。
  final int pending;

  /// 今日已完成(archived.completedAt 在今天)。
  final int doneToday;

  /// 已完成累计(items.isCompleted)。
  final int doneAll;

  /// 已逾期未完成(截止日 < 今天)。
  final int overdue;

  /// 今日到期未完成(截止日 == 今天)。
  final int dueToday;

  /// 未来未完成(截止日 > 今天)。
  final int upcoming;

  /// 四段进度权重(已完成/逾期/今天/未来;全零 = 无数据)。
  List<int> get segments => <int>[doneAll, overdue, dueToday, upcoming];
}

/// 纯计算(可单测;now 可注入)。
TodoOverview computeTodoOverview({
  required List<TodoItem> todos,
  required List<ArchivedTodo> archived,
  DateTime? now,
}) {
  final DateTime today = DateTime(
    now?.year ?? DateTime.now().year,
    now?.month ?? DateTime.now().month,
    now?.day ?? DateTime.now().day,
  );
  final DateTime tomorrow = today.add(const Duration(days: 1));
  int pending = 0;
  int doneAll = 0;
  int overdue = 0;
  int dueToday = 0;
  int upcoming = 0;
  for (final TodoItem t in todos) {
    if (t.isCompleted) {
      doneAll++;
      continue;
    }
    pending++;
    final DateTime d = DateTime(t.date.year, t.date.month, t.date.day);
    if (d.isBefore(today)) {
      overdue++;
    } else if (d.isBefore(tomorrow)) {
      dueToday++;
    } else {
      upcoming++;
    }
  }
  int doneToday = 0;
  for (final ArchivedTodo a in archived) {
    final DateTime c = DateTime(
      a.completedAt.year,
      a.completedAt.month,
      a.completedAt.day,
    );
    if (!c.isBefore(today) && c.isBefore(tomorrow)) doneToday++;
  }
  return TodoOverview(
    total: todos.length,
    pending: pending,
    doneToday: doneToday,
    doneAll: doneAll,
    overdue: overdue,
    dueToday: dueToday,
    upcoming: upcoming,
  );
}

/// 首页 C-29 待办卡统计(实时联动:待办/归档任一变化自动刷新)。
final todoOverviewProvider = Provider<TodoOverview>((ref) {
  final List<TodoItem> todos =
      ref.watch(todoListProvider).value ?? const <TodoItem>[];
  final List<ArchivedTodo> archived =
      ref.watch(archivedListProvider).value ?? const <ArchivedTodo>[];
  return computeTodoOverview(todos: todos, archived: archived);
});

/// 待办仓储（main.dart override 注入，与 courseRepositoryProvider 同模式）。
final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => throw UnimplementedError(
    'todoRepositoryProvider must be overridden in main()',
  ),
);

/// 待办全量状态。
final todoListProvider =
    AsyncNotifierProvider<TodoListNotifier, List<TodoItem>>(
      TodoListNotifier.new,
    );

class TodoListNotifier extends AsyncNotifier<List<TodoItem>> {
  @override
  Future<List<TodoItem>> build() async {
    // 启动即清理：已完成且超窗任务删流程图数据（保留 TodoItem）。
    await ref.read(todoRepositoryProvider).cleanupExpiredFlows();
    return ref.read(todoRepositoryProvider).loadTodos();
  }

  TodoRepository get _repo => ref.read(todoRepositoryProvider);

  /// 新增待办（未完成；日期仅日期部分）。
  Future<void> add({
    required String title,
    required DateTime date,
    int priority = 1,
  }) async {
    final DateTime now = DateTime.now();
    final TodoItem item = TodoItem(
      id: _genId(),
      title: title,
      date: DateTime(date.year, date.month, date.day),
      priority: priority.clamp(0, 2),
      isCompleted: false,
      createdAt: now,
      updatedAt: now,
    );
    await _persist(<TodoItem>[...?state.value, item]);
  }

  /// 标记完成（= 归档：isCompleted + archivedAt，并生成归档精简条目）。
  Future<void> complete(String id) async {
    final List<TodoItem> list = <TodoItem>[...?state.value];
    final int i = list.indexWhere((TodoItem t) => t.id == id);
    if (i < 0) return;
    final TodoItem old = list[i];
    if (old.isCompleted) return;
    final DateTime now = DateTime.now();
    list[i] = old.copyWith(
      isCompleted: true,
      archivedAt: now,
      updatedAt: now,
    );
    await _persist(list);
    // 归档精简条目（回收站展示）。
    final List<ArchivedTodo> archived = <ArchivedTodo>[
      ..._repo.loadArchived(),
      ArchivedTodo(
        id: old.id,
        title: old.title,
        originalDate: old.date,
        completedAt: now,
      ),
    ];
    await _repo.saveArchived(archived);
    ref.invalidate(archivedListProvider);
  }

  /// 恢复（回收站 → 待办：翻回未完成，移除归档条目）。
  Future<void> restore(String id) async {
    final List<TodoItem> list = <TodoItem>[...?state.value];
    final int i = list.indexWhere((TodoItem t) => t.id == id);
    if (i < 0) return;
    final TodoItem old = list[i];
    final DateTime now = DateTime.now();
    list[i] = old.copyWith(
      isCompleted: false,
      archivedAt: null,
      clearArchivedAt: true,
      updatedAt: now,
    );
    await _persist(list);
    final List<ArchivedTodo> archived = <ArchivedTodo>[
      for (final ArchivedTodo a in _repo.loadArchived())
        if (a.id != id) a,
    ];
    await _repo.saveArchived(archived);
    ref.invalidate(archivedListProvider);
  }

  /// 永久删除（从待办 + 回收站移除，连带删除流程图数据）。
  Future<void> permanentlyDelete(String id) async {
    final List<TodoItem> list = <TodoItem>[
      for (final TodoItem t in state.value ?? const <TodoItem>[])
        if (t.id != id) t,
    ];
    await _persist(list);
    await _repo.saveArchived(<ArchivedTodo>[
      for (final ArchivedTodo a in _repo.loadArchived())
        if (a.id != id) a,
    ]);
    ref.invalidate(archivedListProvider);
    await _repo.deleteFlowchart(id);
  }

  /// 更新整条（标题/日期/优先级/进度等）。
  Future<void> updateItem(TodoItem item) async {
    final List<TodoItem> list = <TodoItem>[...?state.value];
    final int i = list.indexWhere((TodoItem t) => t.id == item.id);
    if (i < 0) return;
    list[i] = item;
    await _persist(list);
  }

  Future<void> _persist(List<TodoItem> todos) async {
    state = AsyncData<List<TodoItem>>(todos);
    await _repo.saveTodos(todos);
  }

  static String _genId() =>
      '${DateTime.now().millisecondsSinceEpoch}'
      '${math.Random().nextInt(0xFFFF).toRadixString(16)}';
}

/// 归档精简列表（回收站 P-12；写操作经 TodoListNotifier 收口后 invalidate）。
final archivedListProvider =
    AsyncNotifierProvider<ArchivedListNotifier, List<ArchivedTodo>>(
      ArchivedListNotifier.new,
    );

class ArchivedListNotifier extends AsyncNotifier<List<ArchivedTodo>> {
  @override
  Future<List<ArchivedTodo>> build() async {
    return ref.read(todoRepositoryProvider).loadArchived();
  }
}
