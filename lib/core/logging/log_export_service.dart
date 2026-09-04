// lib/core/logging/log_export_service.dart
// 编号：S-13 导出子服务（v1.9.0）
// 职责：日志 + 性能摘要序列化为 .txt → 写应用临时文件（dart:io）→
//       原生 MethodChannel「saveToDownloads」经 MediaStore 复制到公共 Download/。
// 功耗要点：仅导出时一次性写盘 + 序列化，运行期零成本（§11.6）。
import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log_service.dart';
import 'perf_monitor.dart';

class LogExportService {
  LogExportService._();
  static final LogExportService instance = LogExportService._();

  /// 与 MainActivity.kt 的 MethodChannel 名一致。
  static const MethodChannel _channel = MethodChannel('xiangjugong/log');

  /// 导出日志 + 性能摘要到公共 Download/，返回保存的文件名。
  Future<String> export({
    required String appVersion,
    String? deviceInfo,
  }) async {
    final String content = _buildContent(appVersion, deviceInfo);
    // 应用临时文件（Android 上 Directory.systemTemp = 应用缓存目录，可写）。
    final String filename = 'xiangjugong_log_${_timestamp()}.txt';
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$filename',
    );
    await file.writeAsString(content, flush: true);

    // 原生 MediaStore 复制到公共 Download/（Android 10+ 免存储权限）。
    final String? savedName = await _channel.invokeMethod<String>(
      'saveToDownloads',
      <String, Object?>{
        'sourcePath': file.path,
        'fileName': filename,
        'mimeType': 'text/plain',
      },
    );
    if (savedName == null || savedName.isEmpty) {
      throw StateError('原生通道未返回保存文件名');
    }
    return savedName;
  }

  static String _timestamp() {
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  String _buildContent(String appVersion, String? deviceInfo) {
    final StringBuffer sb = StringBuffer();
    sb.writeln('══════════ Toki 运行日志 ══════════');
    sb.writeln('版本: $appVersion');
    if (deviceInfo != null) sb.writeln('设备: $deviceInfo');
    sb.writeln('导出时间: ${DateTime.now()}');
    sb.writeln('');

    // 性能摘要（S-14）
    final PerfStats? stats = PerfMonitor.instance.snapshot();
    if (stats != null) {
      sb.writeln('── 性能采样（近 ${stats.frameCount} 帧）──');
      sb.writeln('fps: ${stats.fps.toStringAsFixed(1)}');
      sb.writeln('平均 build: ${stats.avgBuildMs.toStringAsFixed(2)} ms');
      sb.writeln('平均 raster: ${stats.avgRasterMs.toStringAsFixed(2)} ms');
      sb.writeln('P95 build: ${stats.p95BuildMs.toStringAsFixed(2)} ms');
      sb.writeln('掉帧(≥17ms): ${stats.jankyFrames}');
    } else {
      sb.writeln('── 性能采样：无数据（需开启「日志采集」且产生过帧）──');
    }
    sb.writeln('');

    // 运行日志（S-13）
    final List<LogEntry> entries = AppLogService.instance.snapshot();
    sb.writeln('── 运行日志（${entries.length} 条，环形缓冲 ${AppLogService.capacity}）──');
    for (final LogEntry e in entries) {
      sb.writeln(
        '[${e.time.toIso8601String()}] [${e.level.name}] [${e.tag}] ${e.message}',
      );
    }
    return sb.toString();
  }
}
