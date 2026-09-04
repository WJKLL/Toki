// lib/domain/entities/course.dart
// 编号：P-06 / S-15 数据模型（v1.16.0 重构）
// 说明：课程数据模型 —— 参考勾丰小站课程表（CSS Grid 周课表）：
//   day(1-7) × start(节次1-16) × len(节数1-4) 定位网格，week 三态单双周，
//   colorValue 课程块颜色（auto 分配或 7 预设色），location/teacher 选填。
//   序列化走 dart:convert；旧数据（time/day 文本）迁移兜底。
enum WeekType {
  /// 每周都上。
  every,

  /// 单周（第 1/3/5…周）。
  odd,

  /// 双周（第 2/4/6…周）。
  even,
}

class Course {
  const Course({
    required this.id,
    required this.name,
    required this.day,
    required this.start,
    this.len = 1,
    this.week = WeekType.every,
    this.colorValue = _kDefaultColor,
    this.location,
    this.teacher,
    this.weeks = const <int>[],
  });

  /// 唯一标识（毫秒时间戳 + 随机后缀）。
  final String id;

  /// 课程名称。
  final String name;

  /// 星期几（1=周一 .. 7=周日）。
  final int day;

  /// 起始节次（1..16）。
  final int start;

  /// 节数（1..4，跨节）。
  final int len;

  /// 周次（每周 / 单周 / 双周）。
  final WeekType week;

  /// 课程块颜色（Color.toARGB32）。
  final int colorValue;

  /// 上课地点（可选）。
  final String? location;

  /// 教师（可选；Excel 导入时班级信息也存入此字段）。
  final String? teacher;

  /// 具体周次集合（1..30，升序去重；v1.17.0 Excel 导入增强）。
  /// 空 = 未导入具体周次，显示走 [week] 三态逻辑；
  /// 非空 = 按周次精确显示（Excel 如 1-5,7-16）。
  final List<int> weeks;

  static const int _kDefaultColor = 0xFF0080FF;

  /// 预设颜色（参考勾丰小站 sched-color-row）。
  static const List<int> presetColors = <int>[
    0xFF0080FF, // 蓝
    0xFF8B00FF, // 紫
    0xFFFF1493, // 粉
    0xFF20B2AA, // 青
    0xFFFF8A00, // 橙
    0xFF00A86B, // 绿
    0xFF5A6BFF, // 靛
  ];

  /// auto 颜色分配：按课程名 hashCode 取预设色（稳定）。
  static int autoColor(String name) =>
      presetColors[name.hashCode.abs() % presetColors.length];

  /// 星期文本（1=周一 .. 7=周日）。
  static String dayLabel(int day) => const <String>[
    '',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ][day.clamp(1, 7)];

  /// 节次文本（「第 N 节」）。
  static String periodLabel(int start, int len) =>
      len <= 1 ? '第$start节' : '第$start-$start节';

  /// 周次文本（每周 / 单周 / 双周）。
  static String weekLabel(WeekType week) => switch (week) {
    WeekType.every => '每周',
    WeekType.odd => '单周',
    WeekType.even => '双周',
  };

  /// 该课程在当前周次是否显示（weeks 优先，否则单双周过滤）。
  bool showsOn(int currentWeek) {
    if (weeks.isNotEmpty) return weeks.contains(currentWeek);
    return switch (week) {
      WeekType.every => true,
      WeekType.odd => currentWeek.isOdd,
      WeekType.even => currentWeek.isEven,
    };
  }

  Course copyWith({
    String? name,
    int? day,
    int? start,
    int? len,
    WeekType? week,
    int? colorValue,
    String? location,
    bool clearLocation = false,
    String? teacher,
    bool clearTeacher = false,
    List<int>? weeks,
    bool clearWeeks = false,
  }) {
    return Course(
      id: id,
      name: name ?? this.name,
      day: day ?? this.day,
      start: start ?? this.start,
      len: len ?? this.len,
      week: week ?? this.week,
      colorValue: colorValue ?? this.colorValue,
      location: clearLocation ? null : (location ?? this.location),
      teacher: clearTeacher ? null : (teacher ?? this.teacher),
      weeks: clearWeeks ? const <int>[] : (weeks ?? this.weeks),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'day': day,
    'start': start,
    'len': len,
    'week': week.name,
    'colorValue': colorValue,
    'location': location,
    'teacher': teacher,
    'weeks': weeks,
  };

  factory Course.fromJson(Map<String, dynamic> json) {
    // 旧数据迁移：day 可能是文本（"周一"）或数字；start/len/week 缺失兜底。
    final Object? dayRaw = json['day'];
    final int day = dayRaw is int
        ? dayRaw.clamp(1, 7)
        : _dayTextToInt(dayRaw as String? ?? '周一');
    final WeekType week =
        WeekType.values.asNameMap()[json['week']] ?? WeekType.every;
    return Course(
      id: json['id'] as String,
      name: json['name'] as String,
      day: day,
      start: json['start'] as int? ?? 1,
      len: json['len'] as int? ?? 1,
      week: week,
      colorValue: json['colorValue'] as int? ?? _kDefaultColor,
      location: json['location'] as String?,
      teacher: json['teacher'] as String?,
      weeks: _parseWeeks(json['weeks']),
    );
  }

  /// weeks 字段解析（旧数据缺失/类型异常 → 空列表，行为不变）。
  static List<int> _parseWeeks(Object? raw) {
    if (raw is List) {
      final List<int> list = <int>[];
      for (final Object? v in raw) {
        if (v is int && v >= 1 && v <= 30) list.add(v);
      }
      return _normalizeWeeks(list);
    }
    return const <int>[];
  }

  /// 升序 + 去重 + 限幅 1..30。
  static List<int> _normalizeWeeks(List<int> input) {
    final List<int> out = <int>[];
    for (final int w in input) {
      if (w >= 1 && w <= 30 && !out.contains(w)) out.add(w);
    }
    out.sort();
    return out;
  }

  /// 周次集合 → 紧凑文本（如 [1,2,3,4,5,7,8,…,16] → "1-5,7-16"）；空 → ''。
  static String weeksLabel(List<int> weeks) {
    if (weeks.isEmpty) return '';
    final List<int> ws = _normalizeWeeks(weeks);
    final StringBuffer sb = StringBuffer();
    int i = 0;
    while (i < ws.length) {
      int j = i;
      while (j + 1 < ws.length && ws[j + 1] == ws[j] + 1) {
        j++;
      }
      if (sb.isNotEmpty) sb.write(',');
      if (j == i) {
        sb.write('${ws[i]}');
      } else {
        sb.write('${ws[i]}-${ws[j]}');
      }
      i = j + 1;
    }
    return sb.toString();
  }

  /// 「周一」→ 1 …「周日」→ 7（迁移兜底）。
  static int _dayTextToInt(String text) {
    const List<String> days = <String>[
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ];
    final int i = days.indexOf(text);
    return i < 0 ? 1 : i + 1;
  }
}

/// 学期信息（年级 / 学期 / 当前周次，参考勾丰小站 sched-meta）。
class ScheduleMeta {
  const ScheduleMeta({this.grade = '', this.term = 1, this.week = 1});

  /// 年级（如「大二」）。
  final String grade;

  /// 学期（1..8）。
  final int term;

  /// 当前周次（1..30）。
  final int week;

  ScheduleMeta copyWith({String? grade, int? term, int? week}) {
    return ScheduleMeta(
      grade: grade ?? this.grade,
      term: term ?? this.term,
      week: week ?? this.week,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'grade': grade,
    'term': term,
    'week': week,
  };

  factory ScheduleMeta.fromJson(Map<String, dynamic> json) {
    return ScheduleMeta(
      grade: json['grade'] as String? ?? '',
      term: json['term'] as int? ?? 1,
      week: json['week'] as int? ?? 1,
    );
  }
}
