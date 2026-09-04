// lib/core/greeting/s22_greeting_service.dart
// 编号：S-22 问候语生成服务（v1.26.0 新增）
// 说明：首页摘要区动态问候语 —— 纯本地离线，零网络、零 ticker、零依赖。
//   优先级：节日（精确日） > 节气（±1 天容差，取最近） > 时段（随机池）。
//   数据表：2026 年（丙午）。农历节日公历日期已核对（来源：国务院办公厅
//   2026 年部分节假日安排 + 万年历；春节 2/17、元宵 3/3、端午 6/19、
//   中秋 9/25、除夕 2/16；七夕/重阳为农历推算值，如与当年万年历有出入
//   仅影响当日文案，不崩溃 —— 允许 ±0 天即精确日命中，错配自然跳过）。
//   节气日期为北京时间常用表，命中容差 ±1 天吸收精度偏差。
// 测试：clock/random 可注入，保证确定性（test/greeting_service_test.dart）。
// ignore_for_file: prefer_initializing_formals — 私有字段 _clock/_random
// 需以公共命名参数暴露给库外测试注入,无法使用 this._ 初始化形参。
import 'dart:math' as math;

/// 问候语生成服务（S-22）。
///
/// [clock] 可注入当前时间（测试锚定日期）；[random] 可注入随机源；
/// 未注入时按「月×日×时」确定性 seed —— 同一小时内结果稳定
/// （摘要卡反复重建不闪变文案），跨小时自动换新。
class GreetingService {
  GreetingService({DateTime Function()? clock, math.Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random;

  /// 生产默认实例（服务无状态；测试用注入构造另建）。
  static final GreetingService instance = GreetingService();

  final DateTime Function() _clock;
  final math.Random? _random;

  // ── 2026 年节日表（dayOfYear；文案池随机取一条）──────────────────
  // dayOfYear: 1/1=1、2/1=32、3/1=60、4/1=91、5/1=121、6/1=152、
  //            7/1=182、8/1=213、9/1=244、10/1=274、11/1=305、12/1=335。
  static const List<({int day, List<String> lines})> _festivals =
      <({int day, List<String> lines})>[
        // 1/1 元旦
        (day: 1, lines: <String>['元旦快乐，新的一年万事胜意', '新年快乐，元旦欢愉']),
        // 2/14 情人节
        (day: 45, lines: <String>['情人节快乐，甜甜蜜蜜', '今天也要甜一点']),
        // 2/16 除夕
        (day: 47, lines: <String>['除夕团圆，辞旧迎新', '除夕夜，阖家欢乐']),
        // 2/17 春节（正月初一，已核对）
        (day: 48, lines: <String>['春节快乐，马年大吉', '新年好，恭喜发财']),
        // 3/3 元宵节（正月十五，已核对）
        (day: 62, lines: <String>['元宵节快乐，团团圆圆', '花好月圆，元宵安康']),
        // 3/8 妇女节
        (day: 67, lines: <String>['女神节快乐', '妇女节快乐']),
        // 3/12 植树节
        (day: 71, lines: <String>['植树节，种下希望', '今日植树节']),
        // 4/5 清明节（节日命中优先于节气「清明」）
        (day: 95, lines: <String>['清明安康', '清明时节，慎终追远']),
        // 5/1 劳动节
        (day: 121, lines: <String>['劳动节快乐', '劳动最光荣，假期愉快']),
        // 5/4 青年节
        (day: 124, lines: <String>['青年节快乐，正青春', '愿你永远年轻热忱']),
        // 6/1 儿童节
        (day: 152, lines: <String>['儿童节快乐，童心未泯', '今天也是大朋友的小朋友']),
        // 6/19 端午节（五月初五，已核对）
        (day: 170, lines: <String>['端午安康，粽香四溢', '端午快乐，平安顺遂']),
        // 7/1 建党节
        (day: 182, lines: <String>['七一建党节']),
        // 8/19 七夕节（七月初七，农历推算）
        (day: 231, lines: <String>['七夕快乐，星河长明', '今日七夕，愿有情人终成眷属']),
        // 9/10 教师节
        (day: 253, lines: <String>['教师节快乐', '感念师恩，教师节快乐']),
        // 9/25 中秋节（八月十五，已核对）
        (day: 268, lines: <String>['中秋快乐，花好月圆', '月圆人团圆，中秋安康']),
        // 10/1 国庆节
        (day: 274, lines: <String>['国庆快乐', '盛世华诞，举国同庆']),
        // 10/18 重阳节（九月初九，农历推算）
        (day: 291, lines: <String>['重阳安康，登高望远', '重阳节，敬老安康']),
        // 12/25 圣诞节
        (day: 359, lines: <String>['圣诞快乐', 'Merry Christmas']),
      ];

  // ── 2026 年二十四节气（dayOfYear + 名称）───────────────────────
  static const List<({int day, String name})> _solarTerms =
      <({int day, String name})>[
        (day: 5, name: '小寒'),
        (day: 20, name: '大寒'),
        (day: 35, name: '立春'),
        (day: 50, name: '雨水'),
        (day: 64, name: '惊蛰'),
        (day: 79, name: '春分'),
        (day: 95, name: '清明'),
        (day: 110, name: '谷雨'),
        (day: 125, name: '立夏'),
        (day: 141, name: '小满'),
        (day: 156, name: '芒种'),
        (day: 172, name: '夏至'),
        (day: 188, name: '小暑'),
        (day: 204, name: '大暑'),
        (day: 219, name: '立秋'),
        (day: 235, name: '处暑'),
        (day: 250, name: '白露'),
        (day: 266, name: '秋分'),
        (day: 281, name: '寒露'),
        (day: 296, name: '霜降'),
        (day: 311, name: '立冬'),
        (day: 326, name: '小雪'),
        (day: 341, name: '大雪'),
        (day: 355, name: '冬至'),
      ];

  /// 节气容差（天）：日期表精度偏差吸收，±1 天内命中。
  static const int _termToleranceDays = 1;

  // ── 时段问候语池（hour 区间 + 文案池）──────────────────────────
  static const List<({int from, int to, List<String> lines})>
  _periods = <({int from, int to, List<String> lines})>[
    // 5:00-7:59 清晨
    (from: 5, to: 7, lines: <String>['早起的鸟儿有虫吃', '晨光正好，宜开启今日', '新的一天，早安']),
    // 8:00-10:59 上午
    (from: 8, to: 10, lines: <String>['上午好，元气满满', '今天也要精神百倍', '一日之计在于晨']),
    // 11:00-12:59 中午
    (from: 11, to: 12, lines: <String>['午安，记得好好吃饭', '午饭时间到，休息一下', '中午好，养足精神']),
    // 13:00-16:59 下午
    (from: 13, to: 16, lines: <String>['下午好，继续加油', '午后时光，效率满满', '忙里偷闲，喝口水吧']),
    // 17:00-18:59 傍晚
    (from: 17, to: 18, lines: <String>['傍晚好，辛苦一天啦', '夕阳正好，放松片刻', '快下班了，再坚持一下']),
    // 19:00-22:59 晚上
    (from: 19, to: 22, lines: <String>['晚上好，今天辛苦啦', '夜色温柔，好好休息', '睡前记得放松一下']),
    // 23:00-4:59 深夜
    (from: 23, to: 4, lines: <String>['夜深了，早点休息', '熬夜伤身，晚安', '夜深人静，愿你安眠']),
  ];

  /// 生成问候语：`「文案，{userName}」`（userName 默认 'XX'）。
  /// 优先级：节日 > 节气（±1 天） > 时段。
  String greetingFor({String userName = 'XX'}) {
    final DateTime now = _clock();
    // 确定性 seed:同一小时结果稳定(避免摘要卡重建时文案闪变)。
    final math.Random rng =
        _random ?? math.Random(now.month * 100 + now.day * 10 + now.hour);
    final int doy = _dayOfYear(now);
    final String? text =
        _festivalText(doy, rng) ??
        _solarTermText(doy) ??
        _periodText(now.hour, rng);
    if (text == null) return '你好，$userName'; // 理论不可达兜底
    return '$text，$userName';
  }

  /// 节日命中（精确日）→ 池内随机一条。
  String? _festivalText(int doy, math.Random rng) {
    for (final ({int day, List<String> lines}) f in _festivals) {
      if (f.day == doy) return _pick(f.lines, rng);
    }
    return null;
  }

  /// 节气命中：与当日距离 ≤ [_termToleranceDays] 取最近者。
  /// 窗口语义为「日期表精度容差」——窗口内输出该节气文案（误差最多一天）。
  String? _solarTermText(int doy) {
    String? name;
    int bestDist = _termToleranceDays + 1;
    for (final ({int day, String name}) t in _solarTerms) {
      final int d = (t.day - doy).abs();
      if (d < bestDist) {
        bestDist = d;
        name = t.name;
      }
    }
    if (name == null || bestDist > _termToleranceDays) return null;
    return '今日$name';
  }

  /// 时段命中（按小时）→ 池内随机一条。
  String? _periodText(int hour, math.Random rng) {
    for (final ({int from, int to, List<String> lines}) p in _periods) {
      final bool match = p.from <= p.to
          ? (hour >= p.from && hour <= p.to)
          : (hour >= p.from || hour <= p.to); // 深夜跨零点区间 23-4
      if (match) return _pick(p.lines, rng);
    }
    return null;
  }

  String _pick(List<String> pool, math.Random rng) =>
      pool[rng.nextInt(pool.length)];

  /// 非闰年 dayOfYear（2026 平年）。
  static int _dayOfYear(DateTime d) {
    const List<int> monthStart = <int>[
      1,
      32,
      60,
      91,
      121,
      152,
      182,
      213,
      244,
      274,
      305,
      335,
    ];
    return monthStart[d.month - 1] + d.day - 1;
  }
}
