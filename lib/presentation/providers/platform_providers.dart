// lib/presentation/providers/platform_providers.dart
// 编号：S-04 平台信息服务（Riverpod Provider 分发）
// 说明：U-04 平台检测的快照 Provider；只读、惰性求值、零网络零 IO。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/u04_platform_utils.dart';

/// 平台信息快照（S-04）。应用启动时一次性求值，之后保持不变。
class PlatformInfo {
  const PlatformInfo({
    required this.isWeb,
    required this.isAndroid,
    required this.androidSdkInt,
    required this.supportsWallpaperMonet,
    required this.osDescription,
  });

  final bool isWeb;
  final bool isAndroid;

  /// Android API 级别；非 Android 为 null。
  final int? androidSdkInt;

  /// Android 12+ 可读取壁纸色（§10.2）。
  final bool supportsWallpaperMonet;

  final String osDescription;
}

final platformInfoProvider = Provider<PlatformInfo>((ref) {
  return PlatformInfo(
    isWeb: U04PlatformUtils.isWeb,
    isAndroid: U04PlatformUtils.isAndroid,
    androidSdkInt: U04PlatformUtils.androidSdkInt,
    supportsWallpaperMonet: U04PlatformUtils.supportsWallpaperMonet,
    osDescription: U04PlatformUtils.osDescription(),
  );
});

/// 应用版本信息（与 pubspec / AppConstants 同步）。
final appVersionProvider = Provider<String>((ref) {
  return '${AppConstants.appVersion}+${AppConstants.buildNumber}';
});
