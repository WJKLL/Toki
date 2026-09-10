// === 文件: lib/core/widget/widget_bridge_service.dart ===
// 编号：S-26 · 桌面小组件数据桥（v1.51.0）
// 说明：Flutter → 原生 MethodChannel（"xiangjugong/widget"）：
//   - writeTodayCourses：写入今日课程快照（原生随即刷新桌面卡片）；
//   - clear：清空快照；
//   - getInitialRoute：取小组件点击带来的启动深链（一次性）；
//   - requestPin：请求把卡片添加到桌面（不支持的 ROM 返回 supported=false）。
//   全部为静默异步调用（fire-and-forget），不阻塞 UI；Web / 鸿蒙镜像版
//   无此通道时零开销地降级为 no-op。
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException;

import 'widget_snapshot.dart';

/// 桌面小组件原生桥（单例静态方法）。
abstract final class WidgetBridgeService {
  static const MethodChannel _channel = MethodChannel('xiangjugong/widget');

  /// 热启动：小组件点击时由原生推来的目标路由（App 已在运行）。
  /// [WidgetBridge] 常驻桥监听本值并执行 go_router 跳转；冷启动路径不走
  /// 这里，而由 [getInitialRoute] 在 runApp 前取走。
  static final ValueNotifier<String?> pendingRoute = ValueNotifier<String?>(
    null,
  );

  /// 安装「原生 → Dart」的调用处理（App 启动时调用一次，幂等）。
  /// 仅处理热启动跳转 `openRoute`。
  static void install() {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'openRoute') {
        final Object? arg = call.arguments;
        if (arg is String && arg.isNotEmpty) pendingRoute.value = arg;
      }
      return null;
    });
  }

  /// 写入今日课程快照并触发桌面刷新。返回是否成功。
  static Future<bool> writeTodayCourses(WidgetSnapshot snapshot) async {
    try {
      await _channel.invokeMethod<void>('writeTodayCourses', <String, Object?>{
        'json': snapshot.encode(),
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('WidgetBridgeService.writeTodayCourses 失败: ${e.message}');
      return false;
    } catch (_) {
      return false; // Web 等无原生通道。
    }
  }

  /// 清空快照（卡片转空态）。
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {}
  }

  /// 取小组件点击带来的启动深链（如 `/timetable`）。
  /// **一次性**：原生读取后即清空，重复调用返回 null。
  static Future<String?> getInitialRoute() async {
    try {
      final String? route = await _channel.invokeMethod<String>(
        'getInitialRoute',
      );
      return (route == null || route.isEmpty) ? null : route;
    } catch (_) {
      return null;
    }
  }

  /// 请求把卡片添加到桌面。
  /// [supported] = 系统是否支持 requestPin（不支持时调用方给手动引导）；
  /// [launched] = 是否已成功弹出系统确认框。
  static Future<({bool supported, bool launched})> requestPin() async {
    try {
      final Map<Object?, Object?>? r = await _channel
          .invokeMapMethod<Object?, Object?>('requestPin');
      return (
        supported: r?['supported'] == true,
        launched: r?['launched'] == true,
      );
    } catch (_) {
      return (supported: false, launched: false);
    }
  }
}
