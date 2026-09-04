// lib/presentation/providers/agreement_provider.dart
// 编号:S-20 用户协议状态管理(v1.20.0)
// 说明:启动需弹协议卡判定 —— 同步读仓储(内存态):未同意过 **或**
//   已同意版本 ≠ kAgreementVersion(协议文案更新)→ 需要展示;
//   同意后单次持久化(accepted + 当前版本号)并复位状态(整树卸载浮层)。
// 性能:冷启动一次 O(1) 读取,无监听、无网络(§11.6.5)。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/agreement_repository.dart';

/// 用户协议仓储(main.dart override 注入,与 S-02 共用 prefs 实例)。
final agreementRepositoryProvider = Provider<AgreementRepository>(
  (ref) => throw UnimplementedError(
    'agreementRepositoryProvider must be overridden in main()',
  ),
);

/// 是否需要展示协议卡(true = 首启或版本变更,false = 已同意当前版本)。
/// gate 在 MaterialApp 根部 watch 本值:false 时整树零开销直通 child。
final agreementProvider = NotifierProvider<AgreementController, bool>(
  AgreementController.new,
);

class AgreementController extends Notifier<bool> {
  @override
  bool build() {
    final AgreementRepository repo = ref.watch(agreementRepositoryProvider);
    final ({bool accepted, String version}) record = repo.load();
    return !(record.accepted && record.version == kAgreementVersion);
  }

  /// 点击「同意并继续」:持久化(accepted=true + 当前版本号)后复位状态。
  /// 写盘异步非阻塞;失败不阻塞进入(下次启动仍会弹,属可接受降级)。
  Future<void> accept() async {
    await ref
        .read(agreementRepositoryProvider)
        .save(accepted: true, version: kAgreementVersion);
    state = false;
  }
}
