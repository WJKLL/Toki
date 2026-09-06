// lib/core/lifecycle/app_lifecycle_controller.dart
// 编号：S-24 应用后台复位协调（v1.44.x 后台最小化）
// 说明：MainShell 检测「进入后台 ≥15s」→ 执行复位前经本控制器广播 resetTick：
//   - 持有打开态浮层的组件（C-43 日历 / P-10 弹层 / C-34 网格编辑态）
//     订阅后同步收拢；
//   - P-11 编辑器订阅后在复位 pop 前立即落盘（防抖窗内数据兜底）；
//   - C-50 开屏订阅：后台期间复位 → 挂起重播，回前台 resume 即播；
//     前台（resume 补判）复位 → 立即重播。
//   复位天然幂等：notifyReset 只递增计数器，订阅方按需处理。
import 'package:flutter/foundation.dart';

/// S-24 全 App 单例：后台超时复位的广播通道。
class AppLifecycleController extends ChangeNotifier {
  AppLifecycleController._();
  static final AppLifecycleController instance = AppLifecycleController._();

  int _resetTick = 0;

  /// 复位纪元：每次后台复位 +1；订阅方比对变化即可（无需解绑后重挂）。
  int get resetTick => _resetTick;

  /// 最近一次复位时间（null = 从未复位）——供 resume 判定本后台期是否复位。
  DateTime? lastResetAt;

  /// 广播一次后台复位（幂等；由 MainShell 在复位动作前调用）。
  void notifyReset() {
    _resetTick++;
    lastResetAt = DateTime.now();
    notifyListeners();
  }
}
