// === 文件: lib/core/reminder/reminder_service.dart ===
// 编号：P-01-01 内部件 · 课程提醒服务桥（v1.36.0 开发中）
// 说明：Flutter → 原生「课程提醒」MethodChannel（"xiangjugong/reminder"）：
//   - scheduleAlert：AlarmManager 精确闹钟到点弹通知（App 进程不在也会弹）；
//   - start/update/stopCountdown：前台服务常驻圆环通知（仅课程进行时段）。
//   全部为静默异步调用（fire-and-forget），不阻塞 UI。
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;

/// 课程提醒原生桥（单例静态方法）。
abstract final class ReminderService {
  static const MethodChannel _channel = MethodChannel('xiangjugong/reminder');

  /// 幂等建通知渠道（启动时/发通知前调用）。
  static Future<void> ensureChannels() async {
    try {
      await _channel.invokeMethod<void>('ensureChannels');
    } catch (_) {/* 原生缺失（Web）时静默。 */}
  }

  /// 排一个到点提醒精确闹钟（[at] 到点弹「title/body」通知；同 [id] 覆盖）。
  /// 返回是否成功（原生异常会带日志，不再静默）。
  static Future<bool> scheduleAlert({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('scheduleAlert', <String, Object?>{
        'id': id,
        'atMillis': at.millisecondsSinceEpoch,
        'title': title,
        'body': body,
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('ReminderService.scheduleAlert 失败: ${e.message}');
      return false;
    } catch (_) {
      return false; // Web 等无原生通道。
    }
  }

  /// 取消到点闹钟。
  static Future<void> cancelAlert(int id) async {
    try {
      await _channel.invokeMethod<void>('cancelAlert', <String, Object?>{'id': id});
    } catch (_) {}
  }

  /// 清空全部课程闹钟（总开关关闭时）。
  static Future<void> cancelAllAlarms() async {
    try {
      await _channel.invokeMethod<void>('cancelAllAlarms');
    } catch (_) {}
  }

  /// 启动倒计时常驻通知（前台服务；仅课程进行时段调用）。
  /// **自治更新**：原生按 [endAt] 墙钟每 [updateIntervalMs] 自推算剩余/百分比，
  /// 不依赖本进程生命周期（页面关/UI 任务被杀仍持续更新，endAt 到自动停）。
  /// [endText] 如「第 3-4 节 · 11:30 结束」。返回是否成功。
  static Future<bool> startCountdown({
    required String title,
    required String endText,
    required int endAtMillis,
    required int totalMinutes,
    int updateIntervalMs = 60000,
  }) async {
    try {
      await _channel.invokeMethod<void>('startCountdown', <String, Object?>{
        'title': title,
        'endText': endText,
        'endAtMillis': endAtMillis,
        'totalMinutes': totalMinutes,
        'updateIntervalMs': updateIntervalMs,
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('ReminderService.startCountdown 失败: ${e.message}');
      return false;
    } catch (_) {
      return false; // Web 等无原生通道。
    }
  }

  /// 停止常驻通知。返回是否成功。
  static Future<bool> stopCountdown() async {
    try {
      await _channel.invokeMethod<void>('stopCountdown');
      return true;
    } on PlatformException catch (e) {
      debugPrint('ReminderService.stopCountdown 失败: ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 打开「省电策略/电池优化」系统设置（引导用户设无限制，保后台可靠）。
  static Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } catch (_) {}
  }

  /// 打开应用详情页（引导自启动/后台运行等）。
  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }

  /// 诊断：最近一次到点通知实际触发（原生 Receiver 记录；0 = 从未触发）。
  static Future<Map<Object?, Object?>?> getDiagnostics() async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>('getDiagnostics');
    } catch (_) {
      return null;
    }
  }

  /// 请求通知权限（Android 13+；低版本直接成功）。
  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  /// 是否允许精确闹钟。
  static Future<bool> canScheduleExactAlarm() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarm') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 打开精确闹钟系统设置。
  static Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod<void>('openExactAlarmSettings');
    } catch (_) {}
  }
}
