// lib/core/utils/u04_platform_utils.dart
// 编号：U-04 平台检测工具（isWeb / isAndroid / SDK 版本 / 断点判定）
// 🐛 修复（BUG-001）：真实 Android API Level 探测 —— 澎湃OS 4 / Android 17
//   上 Build.VERSION.SDK_INT 可能被厂商 ROM 覆盖为兼容层数值（如 32），
//   导致毛玻璃（API 33+）、Monet（API 31+）等系统能力判断错误降级。
//   探测优先级（一次、缓存）：RELEASE 字符串解析 → PREVIEW_SDK_INT → SDK_INT 降级。
// 说明：kIsWeb 为编译期常量，Web 构建时 Platform / DeviceInfoPlugin 分支被整段
//       tree-shake，不会产生运行时异常（§11.9 Web 专项）。
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../constants/app_constants.dart';

abstract final class U04PlatformUtils {
  /// 是否 Web 平台。
  static bool get isWeb => kIsWeb;

  /// 是否 Android 平台。
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 🐛 修复（BUG-001）：已解析的真实 API Level 缓存（main() 启动探测后写入；
  ///   探测未完成/失败时为 null → androidSdkInt 回退 SDK_INT）。
  static int? _realSdkInt;

  /// 🐛 修复（BUG-001）：一次性探测 Future（并发去重，只发起一次平台通道调用）。
  static Future<int>? _realSdkFuture;

  /// 版本号 → API Level 映射表（截至 2026 年；Android 17 = API 37 ✅）。
  /// 注意：Android 13 = API 33（非 32；32 为 Android 12L）。
  static const Map<int, int> _releaseToApiLevel = <int, int>{
    10: 29, // Android 10 (Q)
    11: 30, // Android 11 (R)
    12: 31, // Android 12 (S)
    13: 33, // Android 13 (T)
    14: 34, // Android 14 (U)
    15: 35, // Android 15 (V)
    16: 36, // Android 16 (W)
    17: 37, // Android 17（澎湃OS 4 基座）
  };

  /// 🐛 修复（BUG-001）：Android SDK 版本（API 级别）；非 Android 返回 null。
  ///   优先返回已解析的真实 API Level（澎湃OS 4 修正），否则回退
  ///   Platform.operatingSystemVersion（即 SDK_INT，可能被厂商覆盖）。
  static int? get androidSdkInt {
    if (!isAndroid) return null;
    if (_realSdkInt != null) return _realSdkInt;
    return int.tryParse(Platform.operatingSystemVersion);
  }

  /// 🐛 修复（BUG-001）：探测真实 Android API Level（仅 Android 调用；Web 返回 0）。
  ///
  /// 优先级（T11 探测表）：
  /// 1️⃣ Build.VERSION.RELEASE 字符串解析（如 "17" → 37）；
  /// 2️⃣ PREVIEW_SDK_INT（开发者预览版：SDK_INT + 1）；
  /// 3️⃣ 降级 SDK_INT（至少可用）。
  /// 结果缓存（内存），全程 ≤1 次平台通道调用；异常时降级不崩溃。
  /// 必须在 UI 首帧前调用（main()），避免 UI 线程帧内探测（§11.8）。
  static Future<int> realAndroidSdkInt() {
    if (!isAndroid) return Future<int>.value(0);
    return _realSdkFuture ??= _probeRealSdkInt();
  }

  static Future<int> _probeRealSdkInt() async {
    try {
      final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
      final int sdkInt = info.version.sdkInt;

      // 1️⃣ RELEASE 解析（厂商 ROM 覆盖 SDK_INT 时 RELEASE 通常仍真实）。
      final int? byRelease = apiLevelFromRelease(info.version.release);
      if (byRelease != null) {
        _realSdkInt = byRelease;
        return byRelease;
      }
      // 2️⃣ PREVIEW_SDK_INT（开发者预览）。
      if (info.version.previewSdkInt != null &&
          info.version.previewSdkInt! > 0) {
        _realSdkInt = sdkInt + 1;
        return _realSdkInt!;
      }
      // 3️⃣ 降级 SDK_INT。
      _realSdkInt = sdkInt;
      return sdkInt;
    } catch (_) {
      // 异常降级：不崩溃，返回 SDK_INT。
      _realSdkInt = int.tryParse(Platform.operatingSystemVersion) ?? 0;
      return _realSdkInt!;
    }
  }

  /// 🐛 修复（BUG-001）：RELEASE 字符串 → API Level（可测纯函数）。
  ///   如 "17" → 37、"13" → 33、"12L"/"12.1" → 32；无法识别返回 null。
  static int? apiLevelFromRelease(String release) {
    final String s = release.trim();
    final Match? m = RegExp(r'^(\d+)(?:\.(\d+))?([A-Za-z]*)$').firstMatch(s);
    if (m == null) return null;
    final int major = int.parse(m.group(1)!);
    final String? minor = m.group(2);
    final String suffix = (m.group(3) ?? '').toUpperCase();
    // 特殊：Android 12L（12.1 / 12L）→ API 32。
    if (major == 12 && (suffix.contains('L') || minor == '1')) return 32;
    return _releaseToApiLevel[major];
  }

  /// Monet 动态取色可用性：Android 12+（API 31+）读取壁纸色（§10.2）。
  /// 🐛 修复（BUG-001）：经 androidSdkInt（真实值优先）判断。
  static bool get supportsWallpaperMonet {
    final int? sdk = androidSdkInt;
    return sdk != null && sdk >= 31;
  }

  /// 是否宽屏布局（断点判定，§1 响应式断点 700px）。
  static bool isWideScreen(double width) =>
      width >= AppConstants.breakpointWidth;

  /// 操作系统描述（设置页 / 首页系统信息展示）。
  static String osDescription() {
    if (isWeb) return 'Web';
    if (isAndroid) {
      final int? sdk = androidSdkInt;
      return 'Android${sdk == null ? '' : ' $sdk'}';
    }
    return defaultTargetPlatform.name;
  }
}
