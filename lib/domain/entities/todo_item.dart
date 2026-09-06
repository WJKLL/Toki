// lib/domain/entities/todo_item.dart
// 编号：S-23 待办领域实体（v1.43.0，P-10 待办一级页 + P-12 回收站）
// 说明：待办任务（含归档态）与归档精简条目 —— 纯领域实体，不依赖 UI/存储。
//   - 日期仅存「日期部分」（DateTime(y,m,d)，本地时区毫秒序列化）；
//   - 优先级三档：0 低 / 1 中 / 2 高（与 UI 高/中/低一致）；
//   - progress 为流程图实时计算缓存的完成度（0.0~1.0，未建图默认 0）；
//   - isCompleted=true 即归档（archivedAt 非空，进回收站）；恢复仅翻回 false。
// 导出/清理窗口（v1.43.0 定稿）：截止日次日 00:00 起 15 天内可导出
//   PNG/JSON（已完成+未完成均适用）；仅「已完成」任务超窗删除流程图数据。

/// 导出窗口长度（截止日次日算起）。
const Duration kTodoExportWindow = Duration(days: 15);

/// 优先级档位标签（三档：低/中/高）。
const List<String> kTodoPriorityLabels = <String>['低', '中', '高'];

/// 待办任务。
class TodoItem {
  const TodoItem({
    required this.id,
    required this.title,
    required this.date,
    this.priority = 1,
    this.isCompleted = false,
    this.flowChartId,
    this.progress = 0.0,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  final String id;
  final String title;

  /// 截止日期（仅日期部分，DateTime(y,m,d)）。
  final DateTime date;

  /// 优先级（0 低 / 1 中 / 2 高）。
  final int priority;

  /// 是否已完成（= 已归档进回收站）。
  final bool isCompleted;

  /// 关联流程图 id（v1.44.0 编辑器落地后写入；预留）。
  final String? flowChartId;

  /// 完成度缓存（0.0~1.0；由流程图节点推进自动计算）。
  final double progress;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 归档时间（null = 未归档）。
  final DateTime? archivedAt;

  /// 是否在导出窗口内（截止日次日 00:00 ~ +15 天；不限归档态）。
  bool canExportNow() {
    final DateTime start = DateTime(date.year, date.month, date.day)
        .add(const Duration(days: 1));
    final DateTime end = start.add(kTodoExportWindow);
    final DateTime now = DateTime.now();
    return now.isAfter(start) && !now.isAfter(end);
  }

  TodoItem copyWith({
    String? title,
    DateTime? date,
    int? priority,
    bool? isCompleted,
    String? flowChartId,
    bool clearFlowChart = false,
    double? progress,
    DateTime? updatedAt,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return TodoItem(
      id: id,
      title: title ?? this.title,
      date: date ?? this.date,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      flowChartId: clearFlowChart ? null : (flowChartId ?? this.flowChartId),
      progress: progress ?? this.progress,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: clearArchivedAt
          ? null
          : (archivedAt ?? this.archivedAt),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'date': date.millisecondsSinceEpoch,
    'priority': priority,
    'isCompleted': isCompleted,
    'flowChartId': flowChartId,
    'progress': progress,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'archivedAt': archivedAt?.millisecondsSinceEpoch,
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      date: _dateOf(json['date']),
      priority: (json['priority'] as int?)?.clamp(0, 2) ?? 1,
      isCompleted: json['isCompleted'] as bool? ?? false,
      flowChartId: json['flowChartId'] as String?,
      progress: (json['progress'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0,
      createdAt: _dateOf(json['createdAt']),
      updatedAt: _dateOf(json['updatedAt']),
      archivedAt: _nullableDate(json['archivedAt']),
    );
  }

  static DateTime _dateOf(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }

  static DateTime? _nullableDate(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }
}

/// 归档精简条目（仅回收站展示；不含流程图数据）。
class ArchivedTodo {
  const ArchivedTodo({
    required this.id,
    required this.title,
    required this.originalDate,
    required this.completedAt,
  });

  final String id;
  final String title;
  final DateTime originalDate;
  final DateTime completedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'originalDate': originalDate.millisecondsSinceEpoch,
    'completedAt': completedAt.millisecondsSinceEpoch,
  };

  factory ArchivedTodo.fromJson(Map<String, dynamic> json) {
    return ArchivedTodo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      originalDate: TodoItem._dateOf(json['originalDate']),
      completedAt: TodoItem._dateOf(json['completedAt']),
    );
  }
}
