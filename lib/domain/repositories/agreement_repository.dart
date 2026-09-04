// lib/domain/repositories/agreement_repository.dart
// 编号:S-20 用户协议状态服务(接口,v1.20.0)
// 说明:协议同意状态与版本号的仓储抽象 —— 实现位于 data/(shared_preferences,
//   单 key 读 <1KB,与 S-02 共用同一 prefs 实例)。
//   读取仅冷启动时一次(内存缓存),不做持续监听。
/// 当前协议版本(硬编码于应用内):协议文案/政策变更时**同步改本常量**,
/// 版本号不同 → 重置同意状态 → 老用户重新弹出协议卡。
const String kAgreementVersion = '2026.09.03';

abstract class AgreementRepository {
  /// 读取同意状态与已同意的协议版本(同步,内存缓存)。
  /// 返回 ([accepted] 是否同意过,[version] 同意时的版本号,无记录为 '')。
  ({bool accepted, String version}) load();

  /// 持久化同意结果(异步写盘):accepted=true 时同时记录当前版本号。
  Future<void> save({required bool accepted, required String version});
}
