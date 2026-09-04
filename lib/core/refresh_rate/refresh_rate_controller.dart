// lib/core/refresh_rate/refresh_rate_controller.dart
// 编号：S-16 高刷新率控制器（安卓 17 骁龙 8 Elite 兼容，v1.16.5）
// 职责：按全局帧活动动态请求/释放高刷新率 —— 帧活动（滚动/拖拽/动画）
//   → 请求最高刷新率（120Hz）；静止 idleTimeout 后 → 释放交还系统 LTPO
//   自适应省电。
// 背景：安卓 15+ 的 Frame Rate Velocity 会根据应用渲染帧率把刷新率压到
//   60Hz；本项目 v1.10.25 的被动帧方案（静止零帧）被系统误判为低帧率应用，
//   vsync 锁 60 → fps 上限 60（实测 64.2）。显式请求 preferredDisplayModeId
//   到最高刷新率模式，打破「vsync 锁 60 → 只出 60fps → 系统更确信只要 60」
//   的死锁。
// 功耗要点：
//   - 仅 addTimingsCallback（帧级轻量，与 S-14 PerfMonitor 互不干扰）；
//   - 静止零帧 → 零回调零开销，仅 Timer 兜底释放（3s 后降频省电）；
//   - v1.17.1：指针按下/移动立即升频（比帧回调快一帧）+ 释放延时 2s→3s；
//   - 请求/释放均 fire-and-forget（不阻塞 UI），失败自动回退下帧重试。
import 'dart:async';

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDownEvent, PointerEvent, PointerMoveEvent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 高刷新率控制器（进程级单例；仅 Android 调用 start()）。
class RefreshRateController {
  RefreshRateController._();
  static final RefreshRateController instance = RefreshRateController._();

  /// 与 MainActivity.kt 的 MethodChannel 名一致。
  static const MethodChannel _channel = MethodChannel('xiangjugong/refresh');

  /// 静止判定：连续无帧/无指针活动超过该时长后释放高刷（系统自适应降频省电）。
  /// v1.17.1：2s→3s（减少快速滚动中频繁升降频切换的抖动）。
  static const Duration idleTimeout = Duration(seconds: 3);

  Timer? _idleTimer;
  bool _highActive = false;
  bool _installed = false;

  /// 滚动中标记：true 期间持续持有高刷（不调度释放），仅滚动真正结束后
  /// 才启动释放计时（v1.17.2：根治滚动中 Frame Rate Velocity 降频波动）。
  bool _scrolling = false;

  /// 当前是否已请求高刷（供诊断/日志用）。
  bool get highActive => _highActive;

  /// 安装全局帧活动监听（幂等；仅 Android 调用）。
  void start() {
    if (_installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // v1.17.1：指针按下/移动立即升频（滚动瞬间即 120Hz，无需等首帧）。
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _poke();
    }
  }

  /// 帧结束回调（任何来源的帧都会触发）。
  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    _poke();
  }

  /// v1.17.2：滚动开始 —— 持续持有高刷，取消释放计时（滚动中不释放）。
  void notifyScrollStart() {
    _scrolling = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_highActive) _requestHigh();
  }

  /// v1.17.2：滚动结束 —— 启动释放计时，真正静止（无活动）后才释放。
  void notifyScrollEnd() {
    _scrolling = false;
    if (_highActive) {
      _idleTimer?.cancel();
      _idleTimer = Timer(idleTimeout, _release);
    }
  }

  /// 活动脉冲：重置静止计时器，并确保高刷已请求。滚动中不调度释放。
  void _poke() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_highActive) {
      _requestHigh();
    }
    if (!_scrolling) {
      _idleTimer = Timer(idleTimeout, _release);
    }
  }

  void _requestHigh() {
    _highActive = true;
    unawaited(
      _channel.invokeMethod<void>('setHigh').catchError((Object _) {
        // 请求失败回退：下次活动重试。
        _highActive = false;
      }),
    );
  }

  void _release() {
    if (!_highActive) return;
    _highActive = false;
    unawaited(
      _channel.invokeMethod<void>('setNormal').catchError((Object _) {
        // 释放失败可忽略：下次活动会重新 setHigh。
      }),
    );
  }
}
