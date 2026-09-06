// lib/presentation/shell/main_shell_page.dart
// 编号：P-01 主框架（F-01 应用外壳与导航，700px 响应式断点）
// 组件：C-01 底部导航栏（<700px 竖屏）、C-02 侧边导航栏（≥700px 横屏/Web）、
//       C-12 悬浮底栏（可选形态）、C-15 页面缩放容器。
// T64（v1.10.0 一级页面横滑）：一级页面用 PageView + PageController（≈ 参考
//   HorizontalPager）；页索引由 URL query「page」承载（单一事实源），深链
//   /home /settings /about 经 app_router redirect 映射为 /?page=N。
// 联动（严格 1:1 离散，参考 MainActivity.kt:200-208 + BottomBar.kt:267-275）：
//   - 页面手势横滑 → onPageChanged → 更新 URL → currentIndex 变 → C-22 指示器
//     didUpdateWidget 弹簧吸附（仅翻页瞬间，非连续跟随）；
//   - 指示器拖拽松手 / 点击标签 → onDestinationSelected → animateToPage
//     （tween 100·|d|+100 EaseInOut，参考 BottomBar.kt:46/57）。
// 功耗要点：
//   - 导航栏静态无 ticker；PageController 仅切换时动画，静止零 ticker；
//   - C-12 悬浮底栏 RepaintBoundary 隔离（§11.2.3）；T50 快照心跳仅悬浮模式
//     挂载（v1.10.21 起需毛玻璃开关同开；v1.10.25 起为被动帧回调、无 Ticker，
//     静止零帧请求 → 适配系统自适应刷新率；采样率 3 帧/次）。
import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/lifecycle/app_lifecycle_controller.dart';
import '../../core/logging/app_log_service.dart';
import '../../core/refresh_rate/refresh_rate_controller.dart';
import '../../core/utils/u03_blur_policy.dart';
import '../../core/utils/u04_platform_utils.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/c15_page_scale_container.dart';
import '../../domain/entities/app_settings.dart';
import '../features/home/page_p01_01_home_page.dart';
import '../features/todo/page_p10_todo_page.dart';
import '../features/tools/page_p01_04_tools_page.dart';
import '../providers/blur_degrade_provider.dart';
import '../providers/drag_active_provider.dart';
import '../providers/nav_items_providers.dart';
import '../providers/platform_providers.dart';
import '../providers/settings_providers.dart';
import '../widgets/c22_backdrop_heartbeat.dart';
import '../widgets/c28_downsampled_capture.dart';
import '../widgets/c22_content_through_floating_bottom_bar.dart';
import '../widgets/c22_visual_params.dart';
import '../widgets/agreement_gate.dart';

class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// C-02 侧边导航栏状态（可折叠）。仅在宽屏布局使用；生命周期随本 State。
  late final MiuixNavigationRailState _railState = MiuixNavigationRailState(
    initialValue: MiuixNavigationRailValue.expanded,
  );

  /// T64：一级页面 PageController（≈ 参考 HorizontalPager 的 PagerState）。
  late final PageController _pageController = PageController();

  /// 深链首次同步标志：didChangeDependencies 后一次性把 PageView 跳到 URL 页。
  bool _pageSynced = false;

  /// v1.49.0:路由实例(运行中外部跳页监听,dispose 解绑)。
  GoRouter? _router;

  /// 当前页索引（State 字段，显式 setState 管理）。v1.10.1 修复：不可依赖
  ///   GoRouterState.of(context) 的隐式重建 —— query 变化（/?page=N）不会重建
  ///   const MainShellPage，导致 currentIndex 冻结、指示器 didUpdateWidget 不触发。
  int _currentIndex = 0;

  // ── v1.43.0：窄/宽布局切换校正 ──
  /// 上次布局分支（窄屏底栏 / 宽屏侧栏）。切换会重建 PageView（树结构不同），
  /// 新 ScrollPosition 落回 initialPage 0（待办）→ 帧后跳回用户所在页。
  bool? _lastWide;
  bool _needsPageResync = false;

  /// v1.10.31：程序化翻页动画进行中标志 —— animateToPage 跨页会经过中间页
  ///   触发 onPageChanged，若不忽略，中间页会覆盖 currentIndex → 指示器
  ///   didUpdateWidget 反复弹簧到中间页再弹回目标（"反方向弹动"根因）。
  bool _programmaticPageChange = false;

  // ── T50（P1 采样卡死修复）：页面级毛玻璃快照 ──
  /// 仅悬浮模式 + 毛玻璃开关（v1.10.21）+ Android 13+（U-03）创建；
  /// 任一关闭/降级即释放 → 零捕获成本。
  MiuixLayerBackdrop? _backdrop;

  /// T50：按 U-03 裁决幂等同步创建/释放页面级 backdrop（build 中调用）。
  ///   v1.10.21：模糊开关绑定设置页「毛玻璃效果」→ userEnabled 需与悬浮开关
  ///   同真（AND），任一切换即重建/释放快照（设置页开关变化触发本组件重建）。
  void _syncBackdrop(bool enabled) {
    if (enabled && _backdrop == null) {
      _backdrop = MiuixLayerBackdrop();
    } else if (!enabled && _backdrop != null) {
      _backdrop!.dispose();
      _backdrop = null;
    }
  }

  // ── P3（v1.17.1）：滚动速度检测 → 快速滚动降级毛玻璃（S-19）；
  //    v1.17.2：滚动起止通知 S-16（滚动中锁定 120Hz、静止才释放）──
  DateTime _lastScrollAt = DateTime.now();

  /// 由滚动通知驱动：
  ///   - ScrollStart/End → S-16 锁定/释放高刷（滚动中持续 120Hz）；
  ///   - ScrollUpdate → 速度检测（>阈值降级毛玻璃，S-19）。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      RefreshRateController.instance.notifyScrollStart();
    } else if (notification is ScrollEndNotification) {
      RefreshRateController.instance.notifyScrollEnd();
    } else if (notification is ScrollUpdateNotification) {
      final double? delta = notification.scrollDelta;
      if (delta != null && delta != 0) {
        final DateTime now = DateTime.now();
        final double dtSec = now.difference(_lastScrollAt).inMicroseconds / 1e6;
        _lastScrollAt = now;
        final double velocity = dtSec > 0 ? delta / dtSec : 0;
        ref
            .read(fastScrollDegradeProvider.notifier)
            .notifyScrollVelocity(velocity);
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // v1.10.3（S-13 覆盖增强）：生命周期日志。
    WidgetsBinding.instance.addObserver(this);
  }

  // ── v1.44.x（S-24）：后台最小化 —— 15s 复位 + resume 按时间戳补判 ──
  /// 进入后台时刻（null = 前台）。
  DateTime? _bgAt;

  /// 本次后台期是否已执行过复位（幂等：单后台期只复位一次）。
  bool _bgResetDone = false;

  /// 后台 15s 提前复位计时（引擎冻结时不触发 → resume 按时间戳补判）。
  Timer? _bgResetTimer;

  /// S-24 后台复位：广播收拢浮层（pop 前，编辑器先落盘）→ pop 二级页 →
  /// 回默认首页（page=1，与冷启动一致）。只保留必要状态，开屏重播由
  /// C-50 订阅 S-24 处理。
  void _performBgReset() {
    if (!mounted || _bgResetDone) return;
    _bgResetDone = true;
    _bgResetTimer?.cancel();
    // 1) 广播复位：浮层收拢、P-11 编辑器立即落盘（须在 pop 前，页面仍挂树）。
    AppLifecycleController.instance.notifyReset();
    // 2) 收起全部二级页（流程图编辑器/回收站/设置/工具…），回到 shell 根。
    final NavigatorState? nav = Navigator.maybeOf(context);
    nav?.popUntil((Route<dynamic> r) => r.isFirst);
    // 3) 回默认首页 tab（page=1；jumpToPage 无中间页动画，指示器直落位）。
    if (_currentIndex != 1) {
      setState(() => _currentIndex = 1);
      if (_pageController.hasClients) _pageController.jumpToPage(1);
      context.go('/?page=1');
    }
    AppLogService.instance.info('lifecycle', '后台≥15s 复位完成(回首页)');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogService.instance.info('lifecycle', '应用状态: $state');
    // v1.44.x（S-24 后台最小化）：
    //   - paused：记后台时刻，15s 计时（引擎存活 → 后台提前复位收拢）；
    //   - resumed：取消计时；若本次后台期 ≥15s 且未复位（引擎被冻结、
    //     计时未触发）→ 此刻补判复位。C-50 收到 S-24 广播后在 resume 态
    //     立即重播开屏，呈现「像新开但秒开」的原生体验。
    switch (state) {
      case AppLifecycleState.paused:
        _bgAt = DateTime.now();
        _bgResetDone = false;
        _bgResetTimer?.cancel();
        _bgResetTimer = Timer(const Duration(seconds: 15), () {
          if (!mounted || _bgAt == null) return;
          _performBgReset();
        });
        break;
      case AppLifecycleState.resumed:
        _bgResetTimer?.cancel();
        final DateTime? at = _bgAt;
        _bgAt = null;
        if (at != null &&
            !_bgResetDone &&
            DateTime.now().difference(at) >= const Duration(seconds: 15)) {
          _performBgReset();
        }
        break;
      default:
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // v1.49.0:运行中响应外部 go('/?page=N')(如首页 C-29 待办卡点击跳待办页)。
    //   URL query「page」为单一事实源 —— 内部翻页(_onDestinationSelected/
    //   onPageChanged)已 setState+go,listener 幂等跳过;外部 go 在此同步。
    final GoRouter router = GoRouter.of(context);
    if (!identical(router, _router)) {
      _router?.routerDelegate.removeListener(_onExternalPageChange);
      _router = router;
      router.routerDelegate.addListener(_onExternalPageChange);
    }
    // 深链首帧：URL ?page=N → 初始化 _currentIndex 并把 PageView 跳到该页。
    if (!_pageSynced) {
      _pageSynced = true;
      final int idx = _pageIndex(context);
      _currentIndex = idx;
      if (idx != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pageController.jumpToPage(idx);
        });
      }
    }
  }

  /// v1.49.0:外部跳页同步(无动画 jump,防与手势/指示器动画竞争;
  /// S-24 复位 jump 同先例)。
  void _onExternalPageChange() {
    final GoRouter? router = _router;
    if (router == null || !mounted) return;
    final String? page = router.state.uri.queryParameters['page'];
    final int? raw = int.tryParse(page ?? '');
    if (raw == null) return;
    final int maxPage = ref.read(bottomBarItemsProvider).length - 1;
    final int idx = raw.clamp(0, maxPage);
    if (idx == _currentIndex) return;
    setState(() => _currentIndex = idx);
    _pageController.jumpToPage(idx);
  }

  @override
  void dispose() {
    // ⚡ 功耗优化：导航状态必须释放，防止状态泄漏。
    _router?.routerDelegate.removeListener(_onExternalPageChange);
    _router = null;
    WidgetsBinding.instance.removeObserver(this);
    _bgResetTimer?.cancel(); // S-24：后台复位计时兜底释放。
    _pageController.dispose();
    _railState.dispose();
    // T50：页面级 backdrop 释放（悬浮模式关闭时已置 null，此处兜底）。
    _backdrop?.dispose();
    super.dispose();
  }

  /// 当前页索引（URL query「page」为单一事实源）。
  /// v1.13.0：页数随底栏项数（bottomBarItemsProvider）动态派生。
  int _pageIndex(BuildContext context) {
    final String? page = GoRouterState.of(context).uri.queryParameters['page'];
    final int idx = int.tryParse(page ?? '') ?? 0;
    final int maxPage = ref.read(bottomBarItemsProvider).length - 1;
    return idx.clamp(0, maxPage);
  }

  /// 切换一级页面（指示器拖拽松手 / 点击标签 / 宽屏侧栏）。
  /// T66：animateToPage tween「100×|d|+100」ms EaseInOut（参考 BottomBar.kt:46/57），
  ///   同步 URL（?page=N）→ 重建 → C-22 currentIndex 更新 → 指示器 didUpdateWidget
  ///   弹簧吸附（离散 1:1 联动）。
  void _onDestinationSelected(int index) {
    if (index == _currentIndex) return;
    final int prevIndex = _currentIndex; // 记录旧值（setState 前）
    final int distance = (index - prevIndex).abs();
    final Duration duration = Duration(
      milliseconds:
          C22VisualParams.pageSwitchBaseMs +
          C22VisualParams.pageSwitchPerDistanceMs * distance,
    );
    // v1.10.31：标记程序化翻页，动画经过中间页的 onPageChanged 将被忽略，
    //   避免中间页覆盖 currentIndex 导致指示器反方向弹动。
    _programmaticPageChange = true;
    unawaited(
      _pageController
          .animateToPage(index, duration: duration, curve: Curves.easeInOut)
          .whenComplete(() {
            if (mounted) _programmaticPageChange = false;
          }),
    );
    // v1.10.1：显式 setState 更新 currentIndex（不依赖路由隐式重建）→ C-22
    //   指示器 didUpdateWidget 弹簧吸附；context.go 仅同步 URL（深链/刷新）。
    setState(() => _currentIndex = index);
    context.go('/?page=$index');
    // v1.10.3（S-13 覆盖增强）：点击/拖拽切换日志。
    AppLogService.instance.info('nav', '点击切换 $prevIndex → $index');
  }

  /// 页面手势横滑完成 → 同步 URL + 显式 setState（严格 1:1：指示器仅此刻吸附）。
  void _onPageChanged(int index) {
    // v1.10.31：程序化翻页动画（animateToPage）经过中间页时忽略 ——
    //   currentIndex / URL 已由 _onDestinationSelected 一次性设为目标，
    //   中间页覆盖会导致指示器弹簧到中间页再弹回（反方向弹动）。
    if (_programmaticPageChange) return;
    setState(() => _currentIndex = index);
    context.go('/?page=$index');
    // v1.10.3（S-13 覆盖增强）：页面滑动切换日志。
    AppLogService.instance.info('nav', '页面滑动 → $index');
  }

  @override
  Widget build(BuildContext context) {
    // 🔧 修复（P-01 / C-01·C-12）：ref.watch 订阅 S-01 全部设置切片，
    //    设置页开关变化 → appSettingsProvider 通知 → 本组件重建 → 底栏形态随之切换。
    final AppSettings settings = ref.watch(appSettingsProvider);
    final bool isWide = U04PlatformUtils.isWideScreen(
      MediaQuery.sizeOf(context).width,
    );
    // v1.43.0：窄/宽分支切换 → PageView 重建落回 initialPage → 帧后校正回
    //   当前页（旋转后用户不应被丢回待办/首页另一页）。
    if (_lastWide != null && isWide != _lastWide) {
      _needsPageResync = true;
    }
    _lastWide = isWide;
    if (_needsPageResync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _needsPageResync = false;
        final double? p = _pageController.page;
        if (p != null && p.round() != _currentIndex) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    }
    final int currentIndex = _currentIndex; // State 字段（v1.10.1 显式管理）
    // v1.13.0：底栏项 / PageView 页数同源（bottomBarItemsProvider，动态 2→N）。
    final List<C22BarItemData> items = ref.watch(bottomBarItemsProvider);

    // v1.20.0（P-07 协议卡）：backdrop 同步提前到 build 顶层 —— AgreementGate
    //   在本 build 外层取 _backdrop,必须先裁决并创建(否则首帧拿到 null,
    //   协议卡毛玻璃降级且不会自动重建);窄屏悬浮 + 毛玻璃开关 + Android 13+
    //   才允许(U-03),宽屏一律 null(卡片降级半透明,Web 兼容)。
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    final bool blurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: settings.blurEnabled && settings.floatingBarEnabled,
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncBackdrop(!isWide && blurAllowed);

    // v1.0.1：移动端（Android）页面缩放已禁用（设置页拉条置灰），
    // 此处强制 1.0 直通（C-15 零开销短路），残留设置不生效。
    final double pageScale = U04PlatformUtils.isAndroid
        ? 1.0
        : settings.pageScale;

    // T64：一级页面 PageView（页数与底栏项同源：待办/首页/工具）。
    // v1.43.0(P-10)：待办加在首页左边(index 0)；默认启动仍落首页(page=1,
    //   由 initialLocation /?page=1 保证,见 app_router)。
    //   PageView 内建横滑手势；onPageChanged 仅在翻页完成后触发（离散联动）。
    final Widget content = C15PageScaleContainer(
      scale: pageScale, // ⚡ 功耗优化：1.0 时直通零开销
      child: PageView(
        controller: _pageController,
        // v1.23.1:卡片拖拽排序中 → 禁一级页横滑(防止拖拽被误判为切页)。
        physics: ref.watch(dragActiveProvider)
            ? const NeverScrollableScrollPhysics()
            : null,
        // v1.18.x（T1）：切页按下即跟手（DragStartBehavior.down）。
        dragStartBehavior: DragStartBehavior.down,
        onPageChanged: _onPageChanged,
        children: const <Widget>[
          PageP10TodoPage(),
          PageP0101HomePage(),
          PageP0104ToolsPage(),
        ],
      ),
    );

    // ⚡ 功耗优化：静态导航栏整体用 RepaintBoundary 隔离，
    //   页面内容滚动/重建不触发导航栏重绘。
    // v1.20.0（P-07）：外层包 AgreementGate —— 需弹协议卡时叠加 C-31 浮层
    //   （同意前屏蔽交互;已同意则直通零开销）。backdrop 供卡片毛玻璃采样。
    return AgreementGate(
      backdrop: _backdrop,
      child: RepaintBoundary(
        child: MiuixScaffold(
          // 系统栏 insets 由分支页各自处理（每页自带顶栏）；此处只托管导航框架。
          contentWindowInsets: EdgeInsets.zero,
          content: (padding) => isWide
              ? _buildWideLayout(content, currentIndex, items)
              : _buildNarrowLayout(content, settings, currentIndex, items),
        ),
      ),
    );
  }

  /// 窄屏（<700px）：内容 + 底部导航（C-22 双模式：液态玻璃 / 蒙版选择框）。
  Widget _buildNarrowLayout(
    Widget content,
    AppSettings settings,
    int currentIndex,
    List<C22BarItemData> items,
  ) {
    // backdrop 裁决/同步已在 build 顶层完成(v1.20.0,见 build 注释)。

    // C-22 底栏（内部按 floatingBarEnabled 切换液态玻璃可拖动 / 普通蒙版，§5 C-22）。
    // v1.13.0：items 来自 bottomBarItemsProvider（动态项数，2→N）。
    final Widget bar = C22ContentThroughFloatingBottomBar(
      currentIndex: currentIndex,
      onDestinationSelected: _onDestinationSelected,
      items: items,
      backdrop: _backdrop, // T50：页面级快照源（悬浮胶囊采样）
    );

    // T50（P1 采样卡死修复）：回迁 MiuixLayerBackdropCapture 快照机制。
    //   仅悬浮模式挂载，关闭即整树卸载 → 零 ticker。
    //   v1.10.25：心跳改为被动帧回调（无 Ticker）→ 内容静止零帧请求，
    //     系统自适应刷新率可降频省电；采样率 everyNFrames 4→3
    //     （120Hz 内容 40Hz 采样），模糊度不变（12dp）。
    final Widget captured = _backdrop != null
        ? C28DownsampledCapture(
            backdrop: _backdrop!,
            child: CaptureHeartbeat(everyNFrames: 4, child: content),
          )
        : content;
    // P3（v1.17.1）：滚动速度检测 → 快速滚动降级毛玻璃；v1.17.2 滚动起止锁定高刷。
    final Widget scrollCaptured = NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: captured,
    );

    // 🔧 v1.2.0（C-22 内容穿透）：悬浮底栏开启时，内容铺满全屏（滚动可滑入
    //   胶囊下方），胶囊以 Stack 悬浮叠加 —— 等价 Material Scaffold.extendBody 语义。
    if (settings.floatingBarEnabled) {
      return Stack(
        children: [
          Positioned.fill(child: scrollCaptured),
          // ⚡ 功耗优化：底栏独立 RepaintBoundary（C-22 内部），滚动零重绘。
          Positioned(left: 0, right: 0, bottom: 0, child: bar),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: scrollCaptured),
        // ⚡ 功耗优化：底栏独立 RepaintBoundary（C-22 内部），滚动零重绘。
        RepaintBoundary(child: bar),
      ],
    );
  }

  /// 宽屏（≥700px）：左侧导航（C-02）+ 内容。
  Widget _buildWideLayout(
    Widget content,
    int currentIndex,
    List<C22BarItemData> items,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          child: MiuixNavigationRail(
            state: _railState,
            iconSize: 22,
            expandedItemVerticalPadding: 10,
            expandedLabelFontSize: 14,
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                _railItem(i, items[i].iconName, items[i].label, currentIndex),
            ],
          ),
        ),
        const _RailDivider(),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: content,
          ),
        ),
      ],
    );
  }

  MiuixNavigationRailItem _railItem(
    int index,
    String iconName,
    String label,
    int currentIndex,
  ) {
    return MiuixNavigationRailItem(
      selected: currentIndex == index,
      onPressed: () => _onDestinationSelected(index),
      icon: MiuixIcon(vector: appIcon(iconName), size: 22),
      label: label,
    );
  }
}

/// 侧边栏与内容区的 1px 分隔线（静态 const，避免布局抖动）。
class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return ColoredBox(
      color: colors.dividerLine,
      child: const SizedBox(width: 0.5),
    );
  }
}
