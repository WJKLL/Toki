// lib/domain/repositories/todo_repository.dart
// 编号：S-23 待办数据服务抽象（v1.43.0，P-10 待办 + P-12 回收站）
// 说明：领域层仓储抽象。实现位于 data/（shared_preferences + JSON）。
//   - 待办全量与归档全量各一个 key（含完成/未完成，主页按日过滤）；
//   - 流程图数据按 `flowchart_$todoId` 独立 key（v1.44.0 写入）；
//   - 过期清理：已完成任务超出「截止日次日 + 15 天」→ 删除其流程图数据。
import '../entities/todo_item.dart';

abstract class TodoRepository {
  /// 同步读取全部待办（内存缓存）。
  List<TodoItem> loadTodos();

  /// 持久化待办全量（异步写盘）。
  Future<void> saveTodos(List<TodoItem> todos);

  /// 同步读取归档精简列表。
  List<ArchivedTodo> loadArchived();

  /// 持久化归档列表（异步写盘）。
  Future<void> saveArchived(List<ArchivedTodo> archived);

  /// 过期清理：扫描已完成任务，超窗(截止日次日+15天)则删除对应
  /// flowchart_$todoId 数据（保留 TodoItem，回收站仍可恢复/永久删除）。
  Future<void> cleanupExpiredFlows();

  /// 读取任务流程图 JSON（v1.44.0 编辑器存储；无则 null）。
  String? loadFlowchart(String todoId);

  /// 保存任务流程图 JSON（异步写盘）。
  Future<void> saveFlowchart(String todoId, String json);

  /// 永久删除任务的流程图数据（无则忽略）。
  Future<void> deleteFlowchart(String todoId);
}
