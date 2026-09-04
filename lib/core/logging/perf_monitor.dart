// lib/core/logging/perf_monitor.dart
// 编号：S-14 性能监控服务（PROJECT_SPEC §6 / §11.10，v1.9.0 落地）
// 职责：帧耗时采样（FrameTiming）→ fps / 平均 build·raster / P95 / 掉帧统计
// 功耗要点：
//   - 仅 enabled 时注册 addTimingsCallback，否则零回调零开销（§11.1）；
//   - 环形缓冲最近 600 帧（≈10s @60fps），内存固定、防膨胀。
import 'package:flutter/scheduler.dart';

/// 帧性能统计快照（导出用）。
class PerfStats {
  const PerfStats({
    required this.frameCount,
    required this.fps,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.p95BuildMs,
    required this.jankyFrames,
  });

  final int frameCount;
  final double fps;
  final double avgBuildMs;
  final double avgRasterMs;
  final double p95BuildMs;

  /// 掉帧数（单帧总耗时 ≥17ms，近似 >60fps 预算）。
  final int jankyFrames;
}

/// S-14 性能监控（进程级单例；enabled 由 S-01 设置开关驱动）。
class PerfMonitor {
  PerfMonitor._();
  static final PerfMonitor instance = PerfMonitor._();

  /// 环形缓冲窗口（帧数）。
  static const int windowFrames = 600;

  final List<DateTime> _timestamps = <DateTime>[];
  final List<Duration> _frameSpans = <Duration>[];
  final List<Duration> _buildDurations = <Duration>[];
  final List<Duration> _rasterDurations = <Duration>[];

  bool _enabled = false;
  bool _installed = false;

  bool get enabled => _enabled;

  /// 幂等开关：开启时注册帧回调，关闭即不再采样。
  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) _install();
  }

  void _install() {
    if (_installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    final DateTime now = DateTime.now();
    for (final FrameTiming t in timings) {
      _push(_timestamps, now);
      _push(_frameSpans, t.totalSpan);
      _push(_buildDurations, t.buildDuration);
      _push(_rasterDurations, t.rasterDuration);
    }
  }

  static void _push<T>(List<T> list, T value) {
    if (list.length >= windowFrames) list.removeAt(0);
    list.add(value);
  }

  /// 清空采样窗口。
  void clear() {
    _timestamps.clear();
    _frameSpans.clear();
    _buildDurations.clear();
    _rasterDurations.clear();
  }

  /// 当前窗口统计；样本不足返回 null。
  PerfStats? snapshot() {
    if (_frameSpans.length < 2) return null;
    final int n = _frameSpans.length;
    final Duration span = _timestamps.last.difference(_timestamps.first);
    final double seconds = span.inMicroseconds / 1e6;
    final double fps = seconds > 0 ? (n - 1) / seconds : 0;
    final int janky = _frameSpans
        .where((Duration d) => d.inMilliseconds >= 17)
        .length;
    return PerfStats(
      frameCount: n,
      fps: fps,
      avgBuildMs: _avgMs(_buildDurations),
      avgRasterMs: _avgMs(_rasterDurations),
      p95BuildMs: _percentileMs(_buildDurations, 0.95),
      jankyFrames: janky,
    );
  }

  static double _avgMs(List<Duration> list) {
    if (list.isEmpty) return 0;
    int us = 0;
    for (final Duration d in list) {
      us += d.inMicroseconds;
    }
    return us / list.length / 1000.0;
  }

  static double _percentileMs(List<Duration> list, double p) {
    if (list.isEmpty) return 0;
    final List<Duration> sorted = <Duration>[...list]..sort();
    final int idx = ((sorted.length - 1) * p).round();
    return sorted[idx].inMicroseconds / 1000.0;
  }
}
