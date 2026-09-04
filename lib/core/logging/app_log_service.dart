// lib/core/logging/app_log_service.dart
// 编号：S-13 日志服务（PROJECT_SPEC §6，v1.9.0 落地）
// 职责：统一日志门面（分级 + 内存环形缓冲 + 全局异常捕获）
// 功耗要点（§11.8 / §11.6）：
//   - enabled=false 时所有方法零成本直接 return（后台零开销）；
//   - 仅内存追加（O(1)），不落盘；导出时才序列化（避免高频 IO）。
import 'package:flutter/foundation.dart';

/// 日志级别（导出序列化用）。
enum LogLevel { debug, info, warn, error }

/// 单条日志记录。
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
}

/// S-13 日志服务（进程级单例；enabled 由 S-01 设置开关驱动）。
class AppLogService {
  AppLogService._();
  static final AppLogService instance = AppLogService._();

  /// 内存环形缓冲容量（防内存膨胀；导出时取快照）。
  static const int capacity = 500;

  bool _enabled = false;
  final List<LogEntry> _buffer = <LogEntry>[];

  /// 是否开启采集（默认关闭，零成本）。
  bool get enabled => _enabled;

  /// 进程启动时间（首次访问本服务时记录，≈ 应用启动；v1.10.3 补记用）。
  final DateTime bootTime = DateTime.now();

  /// 幂等开关（build 中反复调用安全）；开启瞬间记录基线日志。
  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) info('app', '日志采集已开启（进程启动于 $bootTime）');
  }

  /// 当前缓冲快照（副本，导出用）。
  List<LogEntry> snapshot() => List<LogEntry>.unmodifiable(_buffer);

  /// 清空缓冲。
  void clear() => _buffer.clear();

  void log(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    if (!_enabled) return; // ⚡ 关闭时零成本
    final List<LogEntry> buffer = _buffer;
    if (buffer.length >= capacity) buffer.removeAt(0); // 环形淘汰
    final StringBuffer sb = StringBuffer(message);
    if (error != null) sb.write('\n  → $error');
    if (stack != null) sb.write('\n$stack');
    buffer.add(
      LogEntry(
        time: DateTime.now(),
        level: level,
        tag: tag,
        message: sb.toString(),
      ),
    );
  }

  void debug(String tag, String message) => log(LogLevel.debug, tag, message);
  void info(String tag, String message) => log(LogLevel.info, tag, message);
  void warn(String tag, String message, [Object? e, StackTrace? s]) =>
      log(LogLevel.warn, tag, message, e, s);
  void error(String tag, String message, [Object? e, StackTrace? s]) =>
      log(LogLevel.error, tag, message, e, s);

  /// 注册全局异常捕获（崩溃日志入缓冲；zone 由 main() 的 runZonedGuarded 承担）。
  void installGlobalHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      error(
        'Flutter',
        details.exceptionAsString(),
        details.exception,
        details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (Object err, StackTrace st) {
      error('Platform', err.toString(), err, st);
      return true; // 已处理，不崩溃
    };
    _installDebugPrintBridge();
  }

  /// 原 debugPrint（幂等保存，避免重复桥接）。
  DebugPrintCallback? _originalDebugPrint;

  /// 桥接全局 debugPrint → AppLogService：所有现有 debugPrint 调用（C-22 组件等）
  /// 在采集开关开启时自动写入缓冲；开关关闭时仅保留原控制台输出、零额外开销。
  /// v1.10.3：按内容分级（🔴/error → error，🟢/warn → warn，其余 info），
  ///   避免所有日志统一 info 级、无法区分错误。
  void _installDebugPrintBridge() {
    if (_originalDebugPrint != null) return;
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        final String trimmed = message.trim();
        if (trimmed.contains('🔴') || trimmed.toLowerCase().contains('error')) {
          error('print', trimmed);
        } else if (trimmed.contains('🟢') ||
            trimmed.toLowerCase().contains('warn')) {
          warn('print', trimmed);
        } else {
          info('print', trimmed);
        }
      }
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    };
  }
}
