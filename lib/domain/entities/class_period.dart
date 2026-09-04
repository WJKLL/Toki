// lib/domain/entities/class_period.dart
// 编号:S-02 · P-06 节次时间表数据模型(v1.21.0)
// 说明:全局「节次时间表」单条 —— 第 N 节课的开始/结束分钟与启用开关。
//   纯领域实体,不依赖 UI;默认模板与课表网格对齐(_maxPeriod=16),
//   默认启用前 12 节(08:00 起,45 分钟 + 10 分钟课间),13-16 节默认关闭。
//   序列化走 dart:convert(整表单 key 存 SharedPreferences,<1KB)。
import 'package:flutter/foundation.dart' show immutable;

/// 单个节次时间段(第 N 节,索引 0 对应第 1 节)。
@immutable
class ClassPeriod {
  const ClassPeriod({
    required this.startMinutes,
    required this.endMinutes,
    this.enabled = true,
  });

  /// 当日 0 点起分钟数(0..1439),如 08:00 = 480。
  final int startMinutes;

  /// 结束分钟(0..1439),如 08:45 = 525;须 > startMinutes。
  final int endMinutes;

  /// 是否启用该节次(默认 true;13-16 节默认 false,用户按需打开)。
  final bool enabled;

  /// 节次上限(与 P-06 课表网格 _maxPeriod=16 对齐)。
  static const int maxPeriods = 16;

  /// 默认模板启用的节次数(第 13-16 节默认关闭)。
  static const int defaultEnabledCount = 12;

  /// 默认节次时长(分钟)。
  static const int periodMinutes = 45;

  /// 课间(分钟)。
  static const int breakMinutes = 10;

  /// 默认模板(16 项,第 1 节 08:00 起,每 55 分钟一格;13-16 节 disabled)。
  /// const 字面量(48+55n 起步,00:00-00:00 不存在):
  /// 第1节 08:00-08:45 … 第12节 18:05-18:50;第13节起 19:00 后,默认关闭。
  static const List<ClassPeriod> defaults = <ClassPeriod>[
    ClassPeriod(startMinutes: 480, endMinutes: 525),
    ClassPeriod(startMinutes: 535, endMinutes: 580),
    ClassPeriod(startMinutes: 590, endMinutes: 635),
    ClassPeriod(startMinutes: 645, endMinutes: 690),
    ClassPeriod(startMinutes: 700, endMinutes: 745),
    ClassPeriod(startMinutes: 755, endMinutes: 800),
    ClassPeriod(startMinutes: 810, endMinutes: 855),
    ClassPeriod(startMinutes: 865, endMinutes: 910),
    ClassPeriod(startMinutes: 920, endMinutes: 965),
    ClassPeriod(startMinutes: 975, endMinutes: 1020),
    ClassPeriod(startMinutes: 1030, endMinutes: 1075),
    ClassPeriod(startMinutes: 1085, endMinutes: 1130),
    ClassPeriod(startMinutes: 1140, endMinutes: 1185, enabled: false),
    ClassPeriod(startMinutes: 1195, endMinutes: 1240, enabled: false),
    ClassPeriod(startMinutes: 1250, endMinutes: 1295, enabled: false),
    ClassPeriod(startMinutes: 1305, endMinutes: 1350, enabled: false),
  ];

  /// 分钟数 → "HH:mm"(如 540 → "09:00")。
  static String formatMinutes(int m) {
    final int h = (m ~/ 60) % 24;
    final int min = m % 60;
    final String hh = h.toString().padLeft(2, '0');
    final String mm = min.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// 列表归一化:长度固定 [maxPeriods](截断/用模板尾部补齐),防御旧数据。
  static List<ClassPeriod> normalize(List<ClassPeriod> input) {
    if (input.length >= maxPeriods) {
      return List<ClassPeriod>.of(input.sublist(0, maxPeriods));
    }
    final List<ClassPeriod> out = List<ClassPeriod>.of(input);
    for (int i = out.length; i < maxPeriods; i++) {
      out.add(defaults[i]);
    }
    return out;
  }

  ClassPeriod copyWith({int? startMinutes, int? endMinutes, bool? enabled}) {
    return ClassPeriod(
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    's': startMinutes,
    'e': endMinutes,
    'on': enabled,
  };

  /// JSON → 模型(坏数据 → 禁用空段,由调用方 normalize 兜底)。
  factory ClassPeriod.fromJson(Map<String, dynamic> json) {
    return ClassPeriod(
      startMinutes: (json['s'] as int?) ?? 0,
      endMinutes: (json['e'] as int?) ?? 0,
      enabled: (json['on'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ClassPeriod &&
            other.startMinutes == startMinutes &&
            other.endMinutes == endMinutes &&
            other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes, enabled);
}
