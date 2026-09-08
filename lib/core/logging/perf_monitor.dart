// lib/core/logging/perf_monitor.dart
// 编号：S-14 性能监控服务（PROJECT_SPEC §6 / §11.10，v1.9.0 落地）
// 职责：帧耗时采样（FrameTiming）→ fps / 平均 build·raster / P95 / 掉帧统计
// 功耗要点：
//   - 仅 enabled 时注册 addTimingsCallback，否则零回调零开销（§11.1）；
//   - 环形缓冲最近 600 帧（≈10s @60fps），内存固定、防膨胀。
// v1.49.2（切页诊断）：窗口聚合 —— beginWindow/endWindow 期间的帧单独统计，
//   用于定位页面切换卡顿来源（ui 首建 build vs raster 快照/合成；参考华为
//   性能 FAQ：libapp.so 耗时=业务 Dart，libflutter.so 耗时=渲染库）。
import 'package:flutter/scheduler.dart';

import 'app_log_service.dart';

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

/// 切页窗口统计（beginWindow…endWindow 期间；用于定位切页卡顿）。
class PerfWindowStats {
  const PerfWindowStats({
    required this.frameCount,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.p95BuildMs,
    required this.p95RasterMs,
    required this.maxBuildMs,
    required this.maxRasterMs,
    required this.maxTotalMs,
    required this.jankyFrames,
    required this.janky120Frames,
  });

  final int frameCount;
  final double avgBuildMs;
  final double avgRasterMs;
  final double p95BuildMs;
  final double p95RasterMs;
  final double maxBuildMs;
  final double maxRasterMs;
  final double maxTotalMs;

  /// 掉帧数（≥17ms，60fps 预算）。
  final int jankyFrames;

  /// 掉帧数（≥8.33ms，120Hz 设备预算，MatePad Air 适用）。
  final int janky120Frames;
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
      if (_windowName != null) {
        _push(_winTimestamps, now);
        _push(_winSpans, t.totalSpan);
        _push(_winBuilds, t.buildDuration);
        _push(_winRasters, t.rasterDuration);
      }
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

  // ── v1.49.2 切页诊断窗口：beginWindow/endWindow 期间帧单独聚合 ──
  /// 活动窗口名（null = 无窗口；仅 enabled 时生效）。
  String? _windowName;
  final List<DateTime> _winTimestamps = <DateTime>[];
  final List<Duration> _winSpans = <Duration>[];
  final List<Duration> _winBuilds = <Duration>[];
  final List<Duration> _winRasters = <Duration>[];

  /// 开启切页诊断窗口（幂等：已有活动窗口时忽略；未 enabled 时忽略）。
  void beginWindow(String name) {
    if (!_enabled || _windowName != null) return;
    _windowName = name;
    _winTimestamps.clear();
    _winSpans.clear();
    _winBuilds.clear();
    _winRasters.clear();
  }

  /// 关闭窗口并输出统计（AppLogService「perf」标签；样本 <2 帧跳过）。
  void endWindow() {
    final String? name = _windowName;
    if (name == null) return;
    _windowName = null;
    final PerfWindowStats? ws = _windowStats();
    if (ws == null) return;
    AppLogService.instance.info(
      'perf',
      '[perf][$name] frames=${ws.frameCount} '
      'buildAvg=${_fmt(ws.avgBuildMs)} buildP95=${_fmt(ws.p95BuildMs)} '
      'buildMax=${_fmt(ws.maxBuildMs)} '
      'rasterAvg=${_fmt(ws.avgRasterMs)} rasterP95=${_fmt(ws.p95RasterMs)} '
      'rasterMax=${_fmt(ws.maxRasterMs)} '
      'totalMax=${_fmt(ws.maxTotalMs)} '
      'jank17=${ws.jankyFrames} jank8=${ws.janky120Frames}',
    );
    // 背景参照：全局 600 帧窗口，判断卡顿是否常态（非切页专属）。
    final PerfStats? bg = snapshot();
    if (bg != null) {
      AppLogService.instance.info(
        'perf',
        '[perf][bg] frames=${bg.frameCount} fps=${_fmt(bg.fps)} '
        'buildAvg=${_fmt(bg.avgBuildMs)} rasterAvg=${_fmt(bg.avgRasterMs)} '
        'buildP95=${_fmt(bg.p95BuildMs)} jank17=${bg.jankyFrames}',
      );
    }
  }

  PerfWindowStats? _windowStats() {
    if (_winSpans.length < 2) return null;
    final int n = _winSpans.length;
    final int janky17 = _winSpans
        .where((Duration d) => d.inMilliseconds >= 17)
        .length;
    final int janky120 = _winSpans
        .where((Duration d) => d.inMicroseconds >= 8333)
        .length;
    return PerfWindowStats(
      frameCount: n,
      avgBuildMs: _avgMs(_winBuilds),
      avgRasterMs: _avgMs(_winRasters),
      p95BuildMs: _percentileMs(_winBuilds, 0.95),
      p95RasterMs: _percentileMs(_winRasters, 0.95),
      maxBuildMs: _maxMs(_winBuilds),
      maxRasterMs: _maxMs(_winRasters),
      maxTotalMs: _maxMs(_winSpans),
      jankyFrames: janky17,
      janky120Frames: janky120,
    );
  }

  static double _maxMs(List<Duration> list) {
    if (list.isEmpty) return 0;
    Duration max = list.first;
    for (final Duration d in list) {
      if (d > max) max = d;
    }
    return max.inMicroseconds / 1000.0;
  }

  static String _fmt(double v) => v.toStringAsFixed(2);

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
