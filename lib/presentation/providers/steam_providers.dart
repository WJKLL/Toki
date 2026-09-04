// lib/presentation/providers/steam_providers.dart
// 编号：P-08 Steam 查询 · 服务注入与凭证状态（v1.34.0 新增）
// 说明：联网服务与凭证存储的注入点(单元测试可 override 为 fixture);
//   steamApiKeyProvider 为凭证状态(AsyncValue<String?>),保存/清除后
//   invalidate 自动刷新 —— UI 订阅此状态显示「未配置/已配置」。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tools/steam_api_service.dart';
import '../../core/tools/steam_auth_service.dart';

/// S-21 同款模式:联网服务注入点(测试 override)。
final steamApiServiceProvider = Provider<SteamApiService>((ref) {
  return SteamApiService();
});

/// 凭证存储注入点(默认按平台工厂;测试 override 内存假件)。
final steamAuthServiceProvider = Provider<SteamAuthService>((ref) {
  return createSteamAuthService();
});

/// 当前已保存的 UAPI key(AsyncValue:loading=读取中,null=未配置)。
final steamApiKeyProvider = FutureProvider<String?>((ref) {
  return ref.watch(steamAuthServiceProvider).readApiKey();
});

/// 从 AsyncValue 安全取 key(loading/error → null;避免 .value 重抛)。
String? steamApiKeyOrNull(AsyncValue<String?> v) {
  return switch (v) {
    AsyncData<String?>(:final value) => value,
    _ => null,
  };
}

/// 保存 key 并刷新凭证状态(空输入视为清除)。
Future<void> saveSteamApiKey(WidgetRef ref, String key) async {
  await ref.read(steamAuthServiceProvider).saveApiKey(key);
  ref.invalidate(steamApiKeyProvider);
}

/// 清除 key 并刷新凭证状态。
Future<void> clearSteamApiKey(WidgetRef ref) async {
  await ref.read(steamAuthServiceProvider).clearApiKey();
  ref.invalidate(steamApiKeyProvider);
}
