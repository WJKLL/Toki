// lib/domain/repositories/settings_repository.dart
// 编号：S-02 设置存储服务（仓储接口）
// 说明：领域层仓储抽象。实现位于 data/（shared_preferences，读写合并 + 防抖落盘）。
import '../entities/app_settings.dart';
import '../entities/daily_quote.dart';

abstract interface class SettingsRepository {
  /// 同步读取内存缓存中的设置（SharedPreferences 在 getInstance 后为内存态）。
  AppSettings load();

  /// 保存设置：实现方必须做防抖合并（300ms 窗口）与异步写回（§11.6 / 2-5）。
  void save(AppSettings settings);

  /// v1.22.0/v1.23.1：读取首页网格卡顺序(竖屏/横屏各一套 id 列表)。
  /// 无记录/坏数据 → 对应方向 null(调用方用默认顺序);旧数组格式自动迁移
  /// (两方向共用同一套)。
  ({List<String>? portrait, List<String>? landscape}) loadCardOrder();

  /// v1.23.1：保存网格卡顺序(竖屏/横屏各自持久化,互不覆盖)。
  void saveCardOrder({
    required List<String> portrait,
    required List<String> landscape,
  });

  /// v1.26.0（S-21）：读取每日一言当日缓存；无记录/坏数据 → null。
  DailyQuote? loadQuoteCache();

  /// v1.26.0（S-21）：写入每日一言缓存（每日最多 1~2 次,直接落盘）。
  void saveQuoteCache(DailyQuote quote);

  /// v1.34.0(P-08):读取已加入首页的工具目录 id 列表(settings.homeToolItems)。
  /// 坏数据/无记录 → 空列表(首页不追加任何动态卡)。
  List<String> loadHomeToolItems();

  /// v1.34.0(P-08):保存已加入首页的工具 id 列表(低频操作,直接落盘)。
  void saveHomeToolItems(List<String> toolIds);

  /// 释放防抖 Timer 等资源（应用退出 / Provider 销毁时调用）。
  void dispose();
}
