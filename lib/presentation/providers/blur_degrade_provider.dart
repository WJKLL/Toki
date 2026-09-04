// lib/presentation/providers/blur_degrade_provider.dart
// 编号：S-19 模糊降级策略（v1.17.1，P3：极限滚动保帧）
// 职责：快速滚动时临时降低毛玻璃模糊强度（模糊半径 ×0.3），静止/慢速
//   滚动 400ms 后自动恢复。配合 C-27 预模糊（P0）与 U-03 平台门槛，
//   在 Impeller 下保护极限滚动场景的帧率。
// 功耗：仅滚动通知驱动（无 ticker）；降级期间 C-27 预模糊纹理按低半径
//   重建（快照采样节流不变），静止零开销。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 快速滚动降级状态（true = 毛玻璃降级）。
final fastScrollDegradeProvider =
    NotifierProvider<FastScrollDegradeController, bool>(
      FastScrollDegradeController.new,
    );

/// S-19 滚动降级控制器（Riverpod 3 Notifier）。
class FastScrollDegradeController extends Notifier<bool> {
  /// 速度阈值（逻辑像素/秒）：超过即判定快速滚动。
  static const double velocityThreshold = 2500;

  /// 恢复延时：速度回落后 400ms 恢复全强度模糊。
  static const Duration recoverDelay = Duration(milliseconds: 400);

  Timer? _recoverTimer;

  @override
  bool build() {
    ref.onDispose(() {
      _recoverTimer?.cancel();
      _recoverTimer = null;
    });
    return false;
  }

  /// 由滚动通知驱动（velocity 可为负，取绝对值）。
  void notifyScrollVelocity(double velocity) {
    if (velocity.abs() > velocityThreshold) {
      // 快速滚动：立即降级，取消恢复计时。
      _recoverTimer?.cancel();
      _recoverTimer = null;
      if (!state) state = true;
    } else if (state) {
      // 慢速/静止：延时恢复（避免快速滚动中频繁切换）。
      _recoverTimer ??= Timer(recoverDelay, () {
        _recoverTimer = null;
        state = false;
      });
    }
  }
}
