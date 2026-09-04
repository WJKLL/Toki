// lib/domain/repositories/daily_activity_repository.dart
// 编号：S-05 每日活动时间数据服务（v1.19.0）
// 说明：领域层仓储抽象 —— 读取/持久化「每日活动时间」整表（7 天）。
//       实现位于 data/（shared_preferences + JSON，单 key <1KB）。
//       读取仅应用启动/编辑保存时调用，不做持续监听。
import '../entities/daily_activity.dart';

abstract class DailyActivityRepository {
  /// 读取活动时间配置；无记录/损坏 → 默认 7 天。
  DailyBalanceData load();

  /// 持久化活动时间配置（异步写盘）。
  Future<void> save(DailyBalanceData data);
}
