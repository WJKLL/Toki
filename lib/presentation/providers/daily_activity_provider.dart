// lib/presentation/providers/daily_activity_provider.dart
// 编号：S-05 每日活动时间状态管理（v1.19.0）
// 说明：整表（7 天）配置 Riverpod AsyncNotifier —— 启动异步加载，保存后
//   即时更新内存态并异步持久化。派生「今日剩余」经 select 精确监听，
//   供首页卡片只取当日数据（其它天变化不重建卡片）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/daily_activity.dart';
import '../../domain/repositories/daily_activity_repository.dart';

/// 每日活动时间仓储（main.dart override 注入，与 S-02 共用 prefs 实例）。
final dailyActivityRepositoryProvider = Provider<DailyActivityRepository>(
  (ref) => throw UnimplementedError(
    'dailyActivityRepositoryProvider must be overridden in main()',
  ),
);

/// 整表活动时间配置（AsyncData 就绪后含 7 天）。
final dailyActivityProvider =
    AsyncNotifierProvider<DailyActivityNotifier, DailyBalanceData>(
      DailyActivityNotifier.new,
    );

/// 今日剩余（可空：数据未就绪时为 null）：today 时段 + 当前剩余分钟。
class TodayRemaining {
  const TodayRemaining({
    required this.activity,
    required this.totalMinutes,
    required this.leftMinutes,
    required this.nowMinutes,
  });

  final DailyActivityTime activity;
  final int totalMinutes;
  final int leftMinutes;
  final int nowMinutes;

  /// 剩余比例 0..1（total=0 → 0）。
  double get ratio =>
      totalMinutes <= 0 ? 0 : (leftMinutes / totalMinutes).clamp(0.0, 1.0);

  /// 剩余文本 "xx h xx m"。
  String get leftText {
    final int h = leftMinutes ~/ 60;
    final int m = leftMinutes % 60;
    return '$h h $m m';
  }

  /// 截止文本 "截止 HH:mm"。
  String get deadlineText =>
      '截止 ${DailyActivityTime.formatMinutes(activity.endMinutes)}';
}

class DailyActivityNotifier extends AsyncNotifier<DailyBalanceData> {
  @override
  Future<DailyBalanceData> build() async {
    return ref.read(dailyActivityRepositoryProvider).load();
  }

  /// 更新某天配置并持久化（防抖由调用方负责，本方法只做一次写）。
  Future<void> updateDay(DailyActivityTime updated) async {
    final DailyBalanceData cur = state.value ?? DailyBalanceData.defaults();
    final List<DailyActivityTime> list = <DailyActivityTime>[...cur.activities];
    final int i = list.indexWhere((DailyActivityTime a) {
      return a.weekday == updated.weekday;
    });
    if (i >= 0) {
      list[i] = updated;
    } else {
      list.add(updated);
    }
    list.sort((DailyActivityTime a, DailyActivityTime b) {
      return a.weekday.compareTo(b.weekday);
    });
    final DailyBalanceData next = DailyBalanceData(
      activities: list,
      lastUpdated: DateTime.now(),
    );
    state = AsyncData<DailyBalanceData>(next);
    await ref.read(dailyActivityRepositoryProvider).save(next);
  }

  /// 恢复默认 7 天配置并持久化。
  Future<void> resetDefaults() async {
    final DailyBalanceData next = DailyBalanceData.defaults();
    state = AsyncData<DailyBalanceData>(next);
    await ref.read(dailyActivityRepositoryProvider).save(next);
  }

  /// 整表一次写入（v1.19.6：编辑窗保存用 —— 7 天合并单次持久化,
  ///   避免逐条 updateDay 触发 7 次写盘导致"保存延迟/没反应"）。
  Future<void> saveAll(List<DailyActivityTime> activities) async {
    final DailyBalanceData next = DailyBalanceData(
      activities: <DailyActivityTime>[...activities],
      lastUpdated: DateTime.now(),
    );
    state = AsyncData<DailyBalanceData>(next);
    await ref.read(dailyActivityRepositoryProvider).save(next);
  }
}

/// 今日剩余派生（供卡片 select 监听：按当天 weekday 取时段 + 现算剩余）。
/// 边界：未启用 → 0；now < start（未开始）→ 全满 total；
///       start ≤ now < end → end − now；now ≥ end → 0。
final todayRemainingProvider = Provider<TodayRemaining?>((ref) {
  final DailyBalanceData? data = ref.watch(dailyActivityProvider).value;
  if (data == null) return null;
  final DateTime now = DateTime.now();
  final int weekday = now.weekday; // 1=周一..7=周日
  final DailyActivityTime activity = data.of(weekday);
  final int nowMinutes = now.hour * 60 + now.minute;
  final int total = activity.totalMinutes; // 未启用/end<=start → 0
  int left;
  if (!activity.isEnabled || total <= 0) {
    left = 0;
  } else if (nowMinutes < activity.startMinutes) {
    left = total; // 未开始：整段剩余
  } else {
    left = activity.endMinutes - nowMinutes;
    if (left < 0) left = 0; // 已过终止
  }
  return TodayRemaining(
    activity: activity,
    totalMinutes: total,
    leftMinutes: left,
    nowMinutes: nowMinutes,
  );
});
