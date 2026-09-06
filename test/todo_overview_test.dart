// 待办卡统计单测(v1.49.0):computeTodoOverview 口径 —— 总任务/待办/
// 今日完成/已完成累计/逾期/今天/未来分组;边界含空列表与日期边界。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/domain/entities/todo_item.dart';
import 'package:xiangjugong/presentation/providers/todo_providers.dart';

DateTime _day(int y, int m, int d) => DateTime(y, m, d);

TodoItem _item(
  String id,
  DateTime date, {
  bool done = false,
}) {
  final DateTime now = DateTime(2026, 9, 7, 12);
  return TodoItem(
    id: id,
    title: id,
    date: date,
    isCompleted: done,
    createdAt: now,
    updatedAt: now,
    archivedAt: done ? now : null,
  );
}

void main() {
  // 固定"今天"= 2026-09-07。
  final DateTime now = DateTime(2026, 9, 7, 8);

  test('口径:总任务/待办/今日完成/分组', () {
    final List<TodoItem> todos = <TodoItem>[
      _item('done-old', _day(2026, 9, 1), done: true), // 已完成(历史)
      _item('done-today', _day(2026, 9, 7), done: true), // 已完成(今天截止)
      _item('overdue', _day(2026, 9, 5)), // 逾期未完成
      _item('today', _day(2026, 9, 7)), // 今天到期未完成
      _item('future', _day(2026, 9, 10)), // 未来未完成
    ];
    final List<ArchivedTodo> archived = <ArchivedTodo>[
      ArchivedTodo(
        id: 'done-old',
        title: 'done-old',
        originalDate: _day(2026, 9, 1),
        completedAt: DateTime(2026, 9, 6, 20), // 昨天完成
      ),
      ArchivedTodo(
        id: 'done-today',
        title: 'done-today',
        originalDate: _day(2026, 9, 7),
        completedAt: DateTime(2026, 9, 7, 9), // 今天完成
      ),
    ];
    final TodoOverview o = computeTodoOverview(
      todos: todos,
      archived: archived,
      now: now,
    );
    expect(o.total, 5); // 全量条目
    expect(o.doneAll, 2); // items.isCompleted
    expect(o.pending, 3); // 未完成:逾期+今天+未来
    expect(o.doneToday, 1); // archived completedAt 今天(9/7)
    expect(o.overdue, 1);
    expect(o.dueToday, 1);
    expect(o.upcoming, 1);
    // 四段权重顺序:已完成/逾期/今天/未来。
    expect(o.segments, <int>[2, 1, 1, 1]);
  });

  test('今日完成按 completedAt 跨日边界', () {
    final List<ArchivedTodo> archived = <ArchivedTodo>[
      ArchivedTodo(
        id: 'a',
        title: 'a',
        originalDate: _day(2026, 9, 6),
        completedAt: DateTime(2026, 9, 6, 23, 59), // 昨天 23:59
      ),
      ArchivedTodo(
        id: 'b',
        title: 'b',
        originalDate: _day(2026, 9, 6),
        completedAt: DateTime(2026, 9, 7, 0, 0), // 今天 00:00
      ),
    ];
    final TodoOverview o = computeTodoOverview(
      todos: const <TodoItem>[],
      archived: archived,
      now: now,
    );
    expect(o.doneToday, 1);
    expect(o.total, 0);
    expect(o.pending, 0);
  });

  test('空数据:全零且 segments 可展示', () {
    final TodoOverview o = computeTodoOverview(
      todos: const <TodoItem>[],
      archived: const <ArchivedTodo>[],
      now: now,
    );
    expect(o.total, 0);
    expect(o.pending, 0);
    expect(o.doneToday, 0);
    expect(o.segments.every((int w) => w == 0), isTrue);
  });
}
