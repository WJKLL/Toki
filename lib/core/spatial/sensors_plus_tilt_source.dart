// lib/core/spatial/sensors_plus_tilt_source.dart
// 编号：S-41 倾斜输入源（sensors_plus 实现）
//
// ★ 本文件是**主项目独有**：依赖 sensors_plus，而该包不支持 OpenHarmony。
//   鸿蒙镜像经 TiltInputSourceRegistry.register() 注入自己的实现；
//   未注册 → Registry.instance 为 null → 页面降级到自动晃动。
//
// ★ 为什么用【加速度计】而不是陀螺仪
//   陀螺仪给的是角速度，要积分才能得到角度，会随时间漂移 —— 静止放着
//   画面也会慢慢跑偏。加速度计给的是**重力方向**，直接就是"手机现在朝哪边
//   倾"的绝对姿态，正是视差需要的量。
//   代价：它对线性运动（走路、抖手）同样敏感，所以下面必须加低通 + 死区。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'tilt_input_source.dart';

/// S-41 的 sensors_plus 实现（加速度计 → 倾斜角）。
class SensorsPlusTiltSource implements TiltInputSource {
  SensorsPlusTiltSource();

  /// 满幅倾角：约 34°。超过它按满幅算。
  /// 取这个量级是因为"拿着手机看屏幕"时人手腕的自然活动范围就在 ±30° 上下。
  static const double _fullTilt = 0.6;

  /// 低通系数：越小越稳、越迟钝。重力方向本身很稳，取小值即可。
  static const double _alpha = 0.16;

  /// 死区：手抖落在 ±0.04 以内一律当 0 —— 否则静止时画面会一直微微抖。
  static const double _deadZone = 0.04;

  final StreamController<Offset> _out = StreamController<Offset>.broadcast();
  StreamSubscription<AccelerometerEvent>? _sub;

  /// 低通后的当前倾角；null = 还没收到过数据。
  Offset? _cur;

  /// 零位（首次采样自动建立，之后由 recalibrate() 更新）。
  Offset? _zero;

  @override
  Stream<Offset> get stream => _out.stream;

  @override
  Future<bool> isAvailable() async {
    try {
      // 传感器是不是真的存在，只能靠"有没有事件"判断 ——
      // 模拟器、部分平板、被禁用的设备都会静默不给数据。
      final AccelerometerEvent first = await accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).first.timeout(const Duration(milliseconds: 900));
      _consume(first);
      _sub ??= accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_consume, onError: (Object _) {});
      return true;
    } catch (e) {
      debugPrint('🟡 S-41 设备没有可用的加速度计，降级为自动晃动: $e');
      return false;
    }
  }

  void _consume(AccelerometerEvent e) {
    final double mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (mag < 1e-3) return; // 自由落体/异常值

    // 绕屏幕右轴的倾角（左右倾）与绕屏幕横轴的倾角（前后倾）。
    // 用 atan2(分量, 其余分量模) 而不是简单归一化 —— 后者在大角度时非线性。
    final double rx = math.atan2(e.x, math.sqrt(e.y * e.y + e.z * e.z));
    final double ry = math.atan2(e.y, math.sqrt(e.x * e.x + e.z * e.z));
    final Offset raw = Offset(rx, ry);

    final Offset? prev = _cur;
    _cur = prev == null
        ? raw
        : Offset(
            prev.dx + (raw.dx - prev.dx) * _alpha,
            prev.dy + (raw.dy - prev.dy) * _alpha,
          );
    final Offset cur = _cur!;
    final Offset zero = _zero ??= cur;

    double nx = (cur.dx - zero.dx) / _fullTilt;
    double ny = (cur.dy - zero.dy) / _fullTilt;
    if (nx.abs() < _deadZone) nx = 0;
    if (ny.abs() < _deadZone) ny = 0;
    _out.add(Offset(nx.clamp(-1.0, 1.0), ny.clamp(-1.0, 1.0)));
  }

  @override
  void recalibrate() {
    // 以【低通后】的当前值作零位，避免把一帧噪声当成零位。
    _zero = _cur;
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _out.close();
  }
}
