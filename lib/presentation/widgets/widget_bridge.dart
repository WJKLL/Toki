// === 文件: lib/presentation/widgets/widget_bridge.dart ===
// 编号：S-26 · 桌面小组件常驻桥（v1.51.0）
// 说明：挂在 App 顶层（与 CourseReminderBridge 同级）的无 UI 桥（return child）：
//   课表 / 周次 / 节次设置变化 → 去抖 500ms → 算今日课程快照 → 写原生 → 桌面刷新。
//   另监听 currentClassProvider（由首页组合卡每分钟 invalidate 驱动）复核
//   「进行中 / 已结束」高亮；亮暗模式切换同样重写（卡片背景 drawable 随之切换）。
//   零常驻 Timer：去抖 Timer 仅在数据变更后短暂存在，静止时无任何占用。
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
// 仅为 Theme.of(context).brightness（App 实际生效主题，含 uiMode 强制亮/暗），
// 不使用任何 Material 组件（PROJECT_SPEC §1 UI 约束）。
import 'package:flutter/material.dart' show Brightness, Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widget/widget_bridge_service.dart';
import '../../core/widget/widget_snapshot.dart';
import '../../domain/entities/course.dart';
import '../providers/course_provider.dart';
import '../providers/settings_providers.dart';
import '../router/app_router.dart';

/// 顶层常驻桥：把今日课程快照投递到 Android 桌面小组件。
class WidgetBridge extends ConsumerStatefulWidget {
  const WidgetBridge({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetBridge> createState() => _WidgetBridgeState();
}

class _WidgetBridgeState extends ConsumerState<WidgetBridge>
    with WidgetsBindingObserver {
  /// 首次 build 完成监听注册与首帧投递（ref.listen 必须在 build 内调用）。
  bool _booted = false;

  /// 变更去抖（连续编辑课表不产生多次写入与桌面刷新）。
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // 热启动：App 已在运行时点击卡片 → 原生推来路由 → go_router 跳转。
    WidgetBridgeService.pendingRoute.addListener(_onOpenRoute);
    // v1.51.3：系统深浅色切换回调（App 保活时秒级刷新卡片配色）。
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetBridgeService.pendingRoute.removeListener(_onOpenRoute);
    _debounce?.cancel();
    super.dispose();
  }

  /// 消费一次热启动路由（**先清空再跳转**，避免重建时重复导航）。
  void _onOpenRoute() {
    final String? route = WidgetBridgeService.pendingRoute.value;
    if (route == null || route.isEmpty) return;
    WidgetBridgeService.pendingRoute.value = null;
    if (!mounted) return;
    try {
      ref.read(appRouterProvider).go(route);
    } catch (_) {
      // 路由不存在等异常不影响卡片链路。
    }
  }

  /// v1.51.3：系统深色模式切换。
  /// 原生侧已改为**每次渲染现读系统 uiMode**（因此 App 不在运行时，下一次任何
  /// 刷新入口 —— 课程闹钟、开机广播、30 分钟兜底 —— 都会自动纠正配色）；
  /// 本回调只负责让 App **正在运行时**立刻刷新，不必等兜底周期。
  @override
  void didChangePlatformBrightness() => _schedule();

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && !_booted) {
      _booted = true;
      // 课表 / 周次 / 节次设置变更 → 重算今日课程。
      ref.listen(courseListProvider, (_, _) => _schedule());
      ref.listen(scheduleMetaProvider, (_, _) => _schedule());
      ref.listen(
        appSettingsProvider.select((s) => s.classPeriods),
        (_, _) => _schedule(),
      );
      // 当前课程变化（含每分钟 invalidate）→ 复核 ongoing / past 高亮。
      ref.listen(currentClassProvider, (_, _) => _schedule());
      // 首帧后投递一次（覆盖「启动即有数据」冷启动场景）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _schedule();
      });
    }
    return widget.child;
  }

  /// 去抖 500ms 后投递。
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _flush);
  }

  /// 计算快照并写入原生（任何异常都不影响 App，故整段兜底）。
  void _flush() {
    if (!mounted) return;
    try {
      final DateTime now = DateTime.now();
      final List<Course> courses =
          ref.read(courseListProvider).value ?? const <Course>[];
      final ScheduleMeta? meta = ref.read(scheduleMetaProvider).value;
      final WidgetSnapshot snapshot = buildTodaySnapshot(
        courses: courses,
        periods: ref.read(appSettingsProvider).classPeriods,
        meta: meta ?? const ScheduleMeta(),
        now: now,
        isDark: Theme.of(context).brightness == Brightness.dark,
      );
      unawaited(WidgetBridgeService.writeTodayCourses(snapshot));
    } catch (_) {
      // 数据桥失败（Web / 原生缺失）时静默：UI 不受影响。
    }
  }
}
