// lib/domain/entities/daily_activity.dart
// 编号：A-03 数据模型（v1.19.0，S-05 每日活动时间）
// 说明：「每日活动时间」领域实体 —— 一周固定 7 天（weekday 1..7 = 周一..周日），
//   每天一段起止时间 + 启用开关；「今日剩余」按当天 weekday 取对应时段计算。
//   纯领域实体 + JSON 序列化（shared_preferences 存整体字符串，<1KB）。
import 'dart:convert';

/// 一周每天的活动时间配置。
/// [weekday]：1..7（DateTime.weekday 语义，周一=1 … 周日=7）。
/// [startMinutes] / [endMinutes]：当日 0 点起分钟数（0..1439），如 09:00=540。
class DailyActivityTime {
  const DailyActivityTime({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    this.isEnabled = true,
  });

  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final bool isEnabled;

  /// 起止总时长（分钟；end<=start 视为 0，避免负剩余）。
  int get totalMinutes =>
      isEnabled && endMinutes > startMinutes ? endMinutes - startMinutes : 0;

  /// 星期短标签（周一…周日）。
  String get label => _weekLabels[weekday - 1];

  static const List<String> _weekLabels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// 分钟数 → "HH:mm"（如 540 → "09:00"）。
  static String formatMinutes(int m) {
    final int h = (m ~/ 60) % 24;
    final int mm = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  DailyActivityTime copyWith({
    int? startMinutes,
    int? endMinutes,
    bool? isEnabled,
  }) {
    return DailyActivityTime(
      weekday: weekday,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'w': weekday,
    's': startMinutes,
    'e': endMinutes,
    'on': isEnabled,
  };

  factory DailyActivityTime.fromJson(Map<String, dynamic> json) {
    return DailyActivityTime(
      weekday: json['w'] as int? ?? 1,
      startMinutes: json['s'] as int? ?? 540,
      endMinutes: json['e'] as int? ?? 1080,
      isEnabled: json['on'] as bool? ?? true,
    );
  }

  /// 默认配置：周一~周五 09:00-18:00，周六日 10:00-18:00，全启用。
  static DailyActivityTime defaults(int weekday) {
    final bool weekend = weekday >= 6;
    return DailyActivityTime(
      weekday: weekday,
      startMinutes: 9 * 60,
      endMinutes: weekend ? 20 * 60 : 18 * 60,
    );
  }
}

/// 「今日剩余」完整数据：7 天配置 + 最后更新时间。
class DailyBalanceData {
  const DailyBalanceData({required this.activities, required this.lastUpdated});

  /// 按 weekday 1..7 排序的 7 条（缺省条由 UI 补默认，读侧保证 7 条）。
  final List<DailyActivityTime> activities;
  final DateTime lastUpdated;

  /// 取某天（weekday 1..7）配置；缺失返回该天默认（禁用？返回默认启用）。
  DailyActivityTime of(int weekday) {
    for (final DailyActivityTime a in activities) {
      if (a.weekday == weekday) return a;
    }
    return DailyActivityTime.defaults(weekday);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'a': activities.map((DailyActivityTime e) => e.toJson()).toList(),
    't': lastUpdated.millisecondsSinceEpoch,
  };

  factory DailyBalanceData.fromJson(Map<String, dynamic> json) {
    final List<dynamic> list = json['a'] as List<dynamic>? ?? const <dynamic>[];
    return DailyBalanceData(
      activities: list
          .map(
            (dynamic e) =>
                DailyActivityTime.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(json['t'] as int? ?? 0),
    );
  }

  /// 空记录 → 默认 7 天。
  factory DailyBalanceData.defaults() {
    return DailyBalanceData(
      activities: <DailyActivityTime>[
        for (int w = 1; w <= 7; w++) DailyActivityTime.defaults(w),
      ],
      lastUpdated: DateTime.now(),
    );
  }

  String encode() => jsonEncode(toJson());
  factory DailyBalanceData.decode(String raw) =>
      DailyBalanceData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
