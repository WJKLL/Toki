// lib/presentation/providers/scroll_activity_provider.dart
// 编号：C-22 辅助件（v1.18.x，不占编号）
// 职责：全局「滚动/切页活动态」—— 由 main.dart 根部 NotificationListener 捕获
//   **所有路由内**的 ScrollNotification（含 PageView 切页动画、push 二级页滚动，
//   不受 main_shell NotificationListener 覆盖范围限制），驱动 CaptureHeartbeat
//   采样率自适应：滚动/切页中每 2 帧采样快照（跟手、消除拖影），静止 200ms 后
//   回每 4 帧（省电）。静止无帧 → 心跳本就停，采样零成本。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 滚动/切页活动态（true = 正在滚动或 PageView 动画）。
final scrollActivityProvider = NotifierProvider<ScrollActivityController, bool>(
  ScrollActivityController.new,
);

/// S-16 采样联动控制器（Riverpod 3 Notifier）。
class ScrollActivityController extends Notifier<bool> {
  /// 滚动结束后延迟多久回到「静止档」（避免快速滚动中频繁切换）。
  static const Duration settleDelay = Duration(milliseconds: 200);

  Timer? _idle;

  @override
  bool build() {
    ref.onDispose(() {
      _idle?.cancel();
      _idle = null;
    });
    return false;
  }

  /// 滚动活动脉冲：true = 正在滚动（立即进活动档，幂等）；
  /// false = 滚动结束（延时后回静止档）。
  void notifyActivity(bool active) {
    _idle?.cancel();
    _idle = null;
    if (active) {
      if (!state) state = true;
    } else {
      _idle = Timer(settleDelay, () {
        _idle = null;
        if (state) state = false;
      });
    }
  }
}
