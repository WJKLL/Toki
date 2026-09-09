// lib/domain/repositories/ledger_repository.dart
// 编号：S-25 记账数据服务抽象（v1.50.0，P-20 记账一级页）
// 说明：领域层仓储抽象。实现位于 data/（shared_preferences + JSON）。
//   - 账目全量一个 key、分类全量一个 key（读走内存缓存同步返回，写全量异步落盘）；
//   - 首次启动（分类 key 为空）由实现层播种内置预设分类。
import '../entities/ledger_category.dart';
import '../entities/ledger_entry.dart';

abstract class LedgerRepository {
  /// 同步读取全部账目（内存缓存）。
  List<LedgerEntry> loadEntries();

  /// 持久化账目全量（异步写盘）。
  Future<void> saveEntries(List<LedgerEntry> entries);

  /// 同步读取全部分类（首次读取自动播种内置预设）。
  List<LedgerCategory> loadCategories();

  /// 持久化分类全量（异步写盘）。
  Future<void> saveCategories(List<LedgerCategory> categories);

  /// 恢复内置预设分类（丢弃用户自定义分类）。
  Future<void> resetCategories();

  /// 月度预算（分；0 = 未设置）。
  int loadBudgetCents();

  /// 保存月度预算（分；负数按 0 处理）。
  Future<void> saveBudgetCents(int cents);
}
