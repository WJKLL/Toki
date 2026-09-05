// lib/main.dart
// 编号：F-01 应用外壳（MaterialApp 壳 + 主题注入 + go_router 挂载）
// 说明：
//   - ProviderScope 挂载 S-02 仓储实现（启动时同步注入，避免异步 Loading UI）。
//   - MiuixThemeController（S-01 状态机）：uiMode × monetEnabled × keyColor ×
//     paletteStyle 组合决定最终色板；色板一次性生成并缓存（§10.3），build 零重复计算。
//   - 仅保留 MaterialApp 作为 Flutter 壳；界面全部使用 flutter_miuix 组件。
// 功耗要点：冷启动仅一次 SharedPreferences 读取 + 零网络（§11.6.5）。
import 'dart:async';

import 'package:flutter/material.dart'
    show MaterialApp, ThemeData, ThemeMode, ColorScheme, Brightness;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/logging/app_log_service.dart';
import 'core/logging/perf_monitor.dart';
import 'core/refresh_rate/refresh_rate_controller.dart';
import 'core/tools/tool_catalog_store.dart';
import 'core/utils/u04_platform_utils.dart';
import 'core/widgets/app_scroll_behavior.dart';
import 'data/repositories/agreement_repository_impl.dart';
import 'data/repositories/course_repository_impl.dart';
import 'data/repositories/daily_activity_repository_impl.dart';
import 'data/repositories/settings_repository_impl.dart';
import 'domain/entities/app_settings.dart';
import 'presentation/providers/agreement_provider.dart';
import 'presentation/providers/course_provider.dart';
import 'presentation/providers/daily_activity_provider.dart';
import 'presentation/providers/scroll_activity_provider.dart';
import 'presentation/providers/settings_providers.dart';
import 'presentation/router/app_router.dart';
import 'presentation/widgets/course_reminder_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 冷启动仅一次内存化读取（shared_preferences 内存缓存，零 IO 帧耗）。
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsRepositoryImpl repository = SettingsRepositoryImpl(prefs);
  // v1.15.0（S-15）：课表仓储复用同一 prefs 实例（零额外 IO）。
  final CourseRepositoryImpl courseRepository = CourseRepositoryImpl(prefs);
  // v1.19.0（S-05）：每日活动时间仓储（与设置共用 prefs 实例）。
  final DailyActivityRepositoryImpl dailyActivityRepository =
      DailyActivityRepositoryImpl(prefs);
  // v1.20.0（S-20）：用户协议同意状态仓储（与设置共用 prefs 实例）。
  final AgreementRepositoryImpl agreementRepository = AgreementRepositoryImpl(
    prefs,
  );

  // 🐛 修复（BUG-001 / T12）：UI 首帧前一次性探测真实 Android API Level
  //   （澎湃OS 4 / Android 17 误识别为 12 的修正），结果缓存于 U-04；
  //   S-01 派生 Provider（effectiveBlurProvider）、U-03 毛玻璃裁决、
  //   Monet 可用性、C-21/C-22 模糊门控全部经 platformInfoProvider.androidSdkInt
  //   读取，自动获得修正值。仅 Android 调用，Web 零开销（§11.8 禁止帧内探测）。
  if (U04PlatformUtils.isAndroid) {
    await U04PlatformUtils.realAndroidSdkInt();
    // v1.16.5（S-16 高刷）：启动高刷新率控制器（帧活动→120Hz，静止→省电）。
    RefreshRateController.instance.start();
  }

  // v1.9.0（S-13）：注册全局异常捕获（FlutterError + PlatformDispatcher），
  //   崩溃日志入环形缓冲；zone 兜底未捕获异步异常。
  AppLogService.instance.installGlobalHandlers();

  // v1.35.0（P-09）：工具目录 JSON 预加载 —— 本地 asset 读（非网络，几 KB），
  //   解析进内存缓存后 runApp，首页工具卡对账（byIdSync）同步可用；
  //   读/解析异常 → 降级内置 Steam 单工具（P-08 入口保底）+ 写日志。
  try {
    final String catalogJson =
        await rootBundle.loadString('assets/tools/tools.json');
    if (!ToolCatalogStore.instance.seedFromJsonString(catalogJson)) {
      AppLogService.instance.error(
        'catalog',
        '工具目录解析失败，降级内置目录',
        null,
        StackTrace.current,
      );
      ToolCatalogStore.instance.seedFallback();
    }
  } catch (e) {
    AppLogService.instance.error(
      'catalog',
      '工具目录加载失败：$e',
      e,
      StackTrace.current,
    );
    ToolCatalogStore.instance.seedFallback();
  }

  runZonedGuarded(
    () => runApp(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          // v1.15.0（S-15）：课表仓储注入（与设置共用 prefs 实例）。
          courseRepositoryProvider.overrideWithValue(courseRepository),
          // v1.19.0（S-05）：每日活动时间仓储注入。
          dailyActivityRepositoryProvider.overrideWithValue(
            dailyActivityRepository,
          ),
          // v1.20.0（S-20）：用户协议状态仓储注入。
          agreementRepositoryProvider.overrideWithValue(agreementRepository),
        ],
        child: const XiangJuGongApp(),
      ),
    ),
    (Object error, StackTrace stack) {
      AppLogService.instance.error('Zone', error.toString(), error, stack);
    },
  );
}

class XiangJuGongApp extends ConsumerWidget {
  const XiangJuGongApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚡ 功耗优化：只订阅主题相关最小切片（blurEnabled/pageScale 等变更
    //   不重建主题注入层，§11.2.2 精确监听）。
    final ({
      AppUiMode uiMode,
      bool monetEnabled,
      Color? keyColor,
      String paletteStyle,
      bool logCaptureEnabled,
    })
    settings = ref.watch(
      appSettingsProvider.select(
        (s) => (
          uiMode: s.uiMode,
          monetEnabled: s.monetEnabled,
          keyColor: s.keyColor,
          paletteStyle: s.paletteStyle,
          logCaptureEnabled: s.logCaptureEnabled,
        ),
      ),
    );
    // v1.9.0（S-13/S-14）：开关状态同步到采集服务（幂等；关闭时零成本）。
    AppLogService.instance.setEnabled(settings.logCaptureEnabled);
    PerfMonitor.instance.setEnabled(settings.logCaptureEnabled);
    final GoRouter router = ref.watch(appRouterProvider);

    return MiuixThemeController(
      // S-01 状态机 → MiuixColorSchemeMode（§10.3 组合决定最终色板）。
      colorSchemeMode: _resolveColorSchemeMode(
        uiMode: settings.uiMode,
        monetEnabled: settings.monetEnabled,
        keyColor: settings.keyColor,
        paletteStyle: settings.paletteStyle,
      ),
      keyColor: settings.monetEnabled ? settings.keyColor : null,
      paletteStyle:
          kPaletteStyleMap[settings.paletteStyle] ??
          MiuixThemePaletteStyle.tonalSpot,
      child: Builder(
        builder: (context) {
          final MiuixThemeData theme = MiuixTheme.of(context);
          // v1.18.x（采样自适应）：根部全局捕获一切滚动（含 PageView 切页
          // 动画、push 二级页滚动）→ scrollActivityProvider 置活动态 →
          // CaptureHeartbeat 活动档每 2 帧采样（跟手防拖影）、静止回 4 帧省电。
          return NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              final ScrollActivityController c = ref.read(
                scrollActivityProvider.notifier,
              );
              if (n is ScrollStartNotification ||
                  n is ScrollUpdateNotification) {
                c.notifyActivity(true);
              } else if (n is ScrollEndNotification) {
                c.notifyActivity(false);
              }
              return false; // 不拦截，继续冒泡给上层（main_shell S-16 等）。
            },
            child: MaterialApp.router(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              // v1.18.x（T1+D1）：全局滚动物理（Bouncing 回弹）。
              scrollBehavior: const AppScrollBehavior(),
              themeMode: _resolveThemeMode(
                uiMode: settings.uiMode,
                monetEnabled: settings.monetEnabled,
                keyColor: settings.keyColor,
                paletteStyle: settings.paletteStyle,
              ),
              theme: _shellTheme(theme, dark: false),
              darkTheme: _shellTheme(theme, dark: true),
              routerConfig: router,
              // ── v1.0.1 修复（R-01 路由入口）：Android 系统字体缩放问题 ──
              // 系统 textScaleFactor > 1.0 时 Miuix 组件布局溢出（列表行高、卡片换行）。
              // 在 MaterialApp 壳的 Navigator 之上强制 textScaler = noScaling
              // （等价于 textScaleFactor: 1.0），覆盖 Navigator 之下全部路由
              // 继承的 MediaQuery 文本缩放（含系统字体设置变化）。
              builder: (context, child) {
                // v1.31.0：根部垫主题表面色 —— 二级页转场（右滑入/让位/弹出）
                // 期间可能出现「无页面覆盖」的瞬时区域，Navigator 底层原本透黑
                // （页面切换不连贯、短暂黑帧）；垫 surface 后与页面底色一致，
                // 新/旧页衔接处观感连贯。
                final Color backdrop = MiuixTheme.of(context).colors.surface;
                return ColoredBox(
                  color: backdrop,
                  child: DefaultTextStyle.merge(
                    // v1.32.1：文本默认去下划线（继承装饰兜底,参考 C-26/
                    //   底栏 v1.28.1 修复的根因 —— MiuixText 会继承祖先
                    //   DefaultTextStyle 的 decoration）。放在 Navigator 之上：
                    //   一切继承默认样式的文本不再出现下划线;显式 decoration
                    //   （如协议卡链接 TextSpan underline）不受影响。
                    style: const TextStyle(decoration: TextDecoration.none),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.noScaling, // ⚡ 功耗优化：恒定 1.0，无逐帧换算
                      ),
                      // v1.36.0：课程提醒常驻桥（课表→到点闹钟 / 上课→常驻通知；
                      //   Android 生效，Web 空转透传）。
                      child: CourseReminderBridge(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// S-01：uiMode × monetEnabled → MiuixColorSchemeMode。
  static MiuixColorSchemeMode _resolveColorSchemeMode({
    required AppUiMode uiMode,
    required bool monetEnabled,
    required Color? keyColor,
    required String paletteStyle,
  }) {
    final bool? dark = switch (uiMode) {
      AppUiMode.system => null,
      AppUiMode.light => false,
      AppUiMode.dark => true,
    };
    if (monetEnabled) {
      return dark == null
          ? MiuixColorSchemeMode.monetSystem
          : (dark
                ? MiuixColorSchemeMode.monetDark
                : MiuixColorSchemeMode.monetLight);
    }
    return dark == null
        ? MiuixColorSchemeMode.system
        : (dark ? MiuixColorSchemeMode.dark : MiuixColorSchemeMode.light);
  }

  static ThemeMode _resolveThemeMode({
    required AppUiMode uiMode,
    required bool monetEnabled,
    required Color? keyColor,
    required String paletteStyle,
  }) {
    return switch (uiMode) {
      AppUiMode.system => ThemeMode.system,
      AppUiMode.light => ThemeMode.light,
      AppUiMode.dark => ThemeMode.dark,
    };
  }

  /// Material 壳主题：仅从 Miuix 色板桥接 primary/brightness（纯壳，无 Material 组件）。
  static ThemeData _shellTheme(MiuixThemeData theme, {required bool dark}) {
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: theme.colors.primary,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
    );
  }
}
