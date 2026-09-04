// lib/kernel/damped_drag.dart
// 1:1 复刻 KernelSU 参考项目 DampedDragAnimation.kt（原始参数，非主项目克制版）。
// 弹簧参数（DampedDragAnimation.kt:34-42）：
//   value: spring(1, 1000) / velocity: spring(0.5, 300) / press: spring(1, 1000)
//   scaleX: spring(0.6, 250) / scaleY: spring(0.7, 250)
// 按压缩放 pressedScale = 78/56（FloatingBottomBar.kt:229）。
import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// 阻尼拖拽动画控制器（等价 DampedDragAnimation）。
class DampedDragController extends ChangeNotifier {
  DampedDragController({
    required TickerProvider vsync,
    required this._tabCount,
  }) {
    _value = AnimationController.unbounded(vsync: vsync);
    _press = AnimationController.unbounded(vsync: vsync);
    _scaleX = AnimationController.unbounded(vsync: vsync)..value = 1;
    _scaleY = AnimationController.unbounded(vsync: vsync)..value = 1;
    _velocity = AnimationController.unbounded(vsync: vsync);
    _velTicker = vsync.createTicker(_onVelTick);
    _addListeners();
  }

  final int _tabCount;

  late final AnimationController _value;
  late final AnimationController _press;
  late final AnimationController _scaleX;
  late final AnimationController _scaleY;
  late final AnimationController _velocity;

  /// velocity 弹簧的连续积分状态（参考项目 DampedDragAnimation.kt 的
  /// SpringAnimation：状态延续、每帧只改 target —— Flutter SpringSimulation
  /// 每次 animateWith 都重置初速 0，8ms 级 move 事件下永远追不上手速，故自实现）。
  late final Ticker _velTicker;
  Duration _lastVelTick = Duration.zero;
  double _velTarget = 0; // 弹簧目标（= 当前手速估算，value/秒）
  double _velSpringV = 0; // 弹簧当前速度（内部状态，非输入）
  bool _velTicking = false;

  /// velocity 弹簧 spring(0.5, 300)：ω=√300≈17.32，ζ=0.5 → c=2ζω≈17.32。
  static const double _velK = 300;
  static final double _velC = 0.5 * 2 * math.sqrt(300);

  /// 按压缩放 = 78/56（参考项目原始值，非主项目 1.12）。
  static const double pressedScale = 78.0 / 56.0;

  static SpringDescription _spring(double dampingRatio, double stiffness) =>
      SpringDescription(
        mass: 1,
        stiffness: stiffness,
        damping: dampingRatio * 2 * math.sqrt(stiffness),
      );

  static final SpringDescription _valueSpring = _spring(1, 1000);
  static final SpringDescription _pressSpring = _spring(1, 1000);
  // scaleX/scaleY 参考项目原始阻尼比 0.6/0.7（欠阻尼，会过冲振荡）。
  // 快速拖拽时 press→release 快速切换，过冲叠加产生"贴边鼓出再弹回"的反弹。
  // 提到 1.0（临界阻尼）消除振荡：保留 78/56 按压缩放，但单调无过冲。
  static final SpringDescription _scaleXSpring = _spring(1, 250);
  static final SpringDescription _scaleYSpring = _spring(1, 250);

  double get value => _value.value;
  double get pressProgress => _press.value;
  double get scaleX => _scaleX.value;
  double get scaleY => _scaleY.value;
  double get velocity => _velocity.value;
  double get maxValue => (_tabCount - 1).toDouble();

  void _addListeners() {
    for (final AnimationController c in <AnimationController>[
      _value,
      _press,
      _scaleX,
      _scaleY,
      _velocity,
    ]) {
      c.addListener(notifyListeners);
    }
  }

  /// 按下：press→1、缩放→pressedScale（78/56）。
  /// 新一轮按压开始：先取消上一轮吸附的 close 监听（防上一轮 value 尾段
  /// 恰好落入阈值而误排 release，造成"刚按下又缩回"闪烁）。
  void press() {
    _disarmReleaseWhenClose();
    _press.animateWith(SpringSimulation(_pressSpring, _press.value, 1, 0));
    _scaleX.animateWith(
      SpringSimulation(_scaleXSpring, _scaleX.value, pressedScale, 0),
    );
    _scaleY.animateWith(
      SpringSimulation(_scaleYSpring, _scaleY.value, pressedScale, 0),
    );
  }

  /// 释放：等位置到位后 press→0、缩放→1。
  void release() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _press.animateWith(SpringSimulation(_pressSpring, _press.value, 0, 0));
      _scaleX.animateWith(SpringSimulation(_scaleXSpring, _scaleX.value, 1, 0));
      _scaleY.animateWith(SpringSimulation(_scaleYSpring, _scaleY.value, 1, 0));
    });
  }

  /// 拖拽更新位置（钳制 [0, maxValue]）。
  void updateValue(double next) {
    final double target = next.clamp(0.0, maxValue);
    _value.animateWith(SpringSimulation(_valueSpring, _value.value, target, 0));
  }

  /// 拖拽即时跟手：直接设值（非弹簧），精确跟随手指；松手再用 animateToValue 吸附。
  void updateValueDirect(double next) {
    _disarmReleaseWhenClose(); // 拖拽跟手打断吸附：取消 close 监听，防误 release
    _value.value = next.clamp(0.0, maxValue);
  }

  bool _releaseScheduled = false;

  /// 当前吸附动画的"接近即 release"监听器（可移除）。
  VoidCallback? _releaseWhenClose;

  /// 吸附到目标（点击/松手）：press → 位置滑动 → 接近目标即 release。
  ///
  /// release 阈值 = range×2.5%（对齐参考 DampedDragAnimation.release()：
  /// `abs(value − targetValue) < range×0.025` 就缩回），让"回位尾段"与
  /// "缩回落下"重叠 → 一次连贯动画；避免旧版 whenComplete 等 value 100%
  /// 到位才 release 的"先回位、停顿、再落下"两段式割裂感。
  ///
  /// 用可移除监听而非 whenCompleteOrCancel：拖动中 updateValueDirect 会取消
  /// value 弹簧，若走 cancel 分支会误触发 release、清掉 press（updateValueDirect
  /// 已先 _disarmReleaseWhenClose 取消监听，拖拽中保持按压，由下一次
  /// animateToValue 的 close 统一收尾 release）。
  void animateToValue(double target) {
    press();
    final double t = target.clamp(0.0, maxValue);
    unawaited(
      _value
          .animateWith(SpringSimulation(_valueSpring, _value.value, t, 0))
          .whenComplete(() {
            // 兜底：动画正常跑完（未被打断）时若阈值监听尚未触发（如起点已
            // 在阈值内/瞬间完成），保证 release；已由监听提前触发则去抖吞掉。
            _scheduleRelease();
          }),
    );
    _armReleaseWhenClose(t);
  }

  /// 位置接近目标时 release（阈值 = maxValue×2.5%，对齐参考 release()）。
  /// 监听 _value 直到 |value−target| ≤ 阈值 → 移除监听并 release。
  void _armReleaseWhenClose(double target) {
    _disarmReleaseWhenClose(); // 上一轮吸附未完成时先取消
    final double threshold = (maxValue * 0.025).clamp(0.02, 0.2);
    void check() {
      if ((_value.value - target).abs() <= threshold) {
        _disarmReleaseWhenClose();
        _scheduleRelease();
      }
    }

    _releaseWhenClose = check;
    _value.addListener(check);
  }

  void _disarmReleaseWhenClose() {
    final VoidCallback? c = _releaseWhenClose;
    _releaseWhenClose = null;
    if (c != null) _value.removeListener(c);
  }

  /// release 去抖：一次手势只排一个 postFrame 回调。
  void _scheduleRelease() {
    if (_releaseScheduled) return;
    _releaseScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _releaseScheduled = false;
      release();
    });
  }

  /// 拖拽中更新速度（形变绑定速度）。
  ///
  /// 连续弹簧：每次调用只改 target 并启动积分 Ticker（状态延续），而非
  /// animateWith 重置。半隐式欧拉每帧积分：
  ///   a = k·(target − x) − c·v；v += a·dt；x += v·dt
  /// 这样 velocity 能追上手速（v1 效果不明显即因 SpringSimulation 追不上），
  /// 且 0.5 阻尼回 0 时自然过冲 → 松手果冻回弹。
  void updateVelocity(double v) {
    _velTarget = v;
    if (_velTicking) return;
    _velTicking = true;
    _lastVelTick = Duration.zero;
    _velTicker.start();
  }

  void _onVelTick(Duration elapsed) {
    // 首次 tick 或长时间停摆后重启：dt 取小值/钳制，避免跳变。
    double dt;
    if (_lastVelTick == Duration.zero) {
      dt = 0.001;
    } else {
      dt = (elapsed - _lastVelTick).inMicroseconds / 1e6;
      if (dt > 1 / 30) dt = 1 / 30; // 帧率下限 30fps，防大步长失稳
    }
    _lastVelTick = elapsed;

    final double acc =
        _velK * (_velTarget - _velocity.value) - _velC * _velSpringV;
    _velSpringV += acc * dt;
    _velocity.value += _velSpringV * dt;

    // 接近目标且几乎静止 → 停止积分（避免常驻 Ticker 空转）。
    if ((_velocity.value - _velTarget).abs() < 0.005 &&
        _velSpringV.abs() < 0.02) {
      _velocity.value = _velTarget;
      _velSpringV = 0;
      _velTicking = false;
      _velTicker.stop();
    }
  }

  @override
  void dispose() {
    _velTicker.dispose();
    for (final AnimationController c in <AnimationController>[
      _value,
      _press,
      _scaleX,
      _scaleY,
      _velocity,
    ]) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    super.dispose();
  }
}
