// lib/data/repositories/daily_activity_repository_impl.dart
// 编号：S-05 每日活动时间数据服务（实现：shared_preferences + JSON）
// 说明：整表（7 天配置）JSON 字符串存 SharedPreferences（key daily.activity），
//       单次读写 <1KB（约 300B）。同步读（prefs 内存态）+ 异步写。
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/daily_activity.dart';
import '../../domain/repositories/daily_activity_repository.dart';

class DailyActivityRepositoryImpl implements DailyActivityRepository {
  DailyActivityRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  static const String _kDailyActivity = 'daily.activity';

  @override
  DailyBalanceData load() {
    final String? raw = _prefs.getString(_kDailyActivity);
    if (raw == null || raw.isEmpty) return DailyBalanceData.defaults();
    try {
      return DailyBalanceData.decode(raw);
    } catch (_) {
      // 数据损坏兜底：返回默认 7 天（下次保存覆盖）。
      return DailyBalanceData.defaults();
    }
  }

  @override
  Future<void> save(DailyBalanceData data) async {
    await _prefs.setString(_kDailyActivity, data.encode());
  }
}
