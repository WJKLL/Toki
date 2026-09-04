// lib/presentation/features/home/page_p01_01_home_page.dart
// 编号：P-01-01 首页（F-02 首页模块）
// v1.13.1：清空首页内容（列表空），仅保留结构 —— 顶部 C-25 毛玻璃标题栏、
//   C-26 更多菜单、C-24 FAB、内容快照捕获；底栏 / 顶部不受影响。
// 功耗要点：
//   - 顶部毛玻璃（C-25）：MiuixTopAppBar + scrollBehavior 折叠（静止零 ticker）；
//     MiuixLayerBackdrop 捕获内容（CaptureHeartbeat 被动采样、静止零采样）；
//   - 空列表零内容（addAutomaticKeepAlives: false）。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../providers/drag_active_provider.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c24_frosted_fab.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/c34_responsive_card_grid.dart';
import '../../widgets/cards/card_shell.dart';
import '../../widgets/cards/card_summary.dart';

class PageP0101HomePage extends ConsumerStatefulWidget {
  const PageP0101HomePage({super.key});

  @override
  ConsumerState<PageP0101HomePage> createState() => _PageP0101HomePageState();
}

class _PageP0101HomePageState extends ConsumerState<PageP0101HomePage> {
  /// 左侧菜单按钮（leading 占位；v1.13.0 起右侧仅保留 C-26 更多菜单）。
  late final Widget _navigationIcon = C21CapsuleIconButton(
    key: const ValueKey('c21.navigation'),
    icon: appIcon('sidebar'),
    tooltip: '菜单',
    onTap: _noop,
  );

  static void _noop() {}

  // ── C-25（v1.12.0）：顶部毛玻璃快照源 + 折叠滚动行为 ──
  /// 页面级顶部快照（U-03 门控创建/释放；null = 降级纯 surface）。
  MiuixLayerBackdrop? _topBackdrop;

  /// 顶部折叠滚动行为（MiuixTopAppBar + MiuixScrollBehaviorListener 联动）。
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  /// U-03 裁决创建/释放顶部快照（build 中调用，幂等）。
  void _syncTopBackdrop(bool enabled) {
    if (enabled && _topBackdrop == null) {
      _topBackdrop = MiuixLayerBackdrop();
    } else if (!enabled && _topBackdrop != null) {
      _topBackdrop!.dispose();
      _topBackdrop = null;
    }
  }

  @override
  void dispose() {
    // ⚡ 功耗优化：顶部快照释放（U-03 关闭时已置 null，此处兜底）。
    _topBackdrop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    // 🔧 v1.2.0（C-22 内容穿透）：悬浮底栏开启时，底部追加穿透安全间距。
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;
    final MiuixColors colors = MiuixTheme.of(context).colors;

    // v1.12.0（C-25）：顶部毛玻璃 U-03 裁决 + 快照幂等同步。
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: ref.watch(appSettingsProvider.select((s) => s.blurEnabled)),
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      // v1.12.0（C-25）：顶部毛玻璃标题栏（KernelSU TopAppBar 样式）。
      topBar: C25FrostedTopBar(
        title: '首页',
        largeTitle: AppConstants.appName,
        navigationIcon: _navigationIcon,
        actions: const <Widget>[
          // v1.32.0（C-26 重构定稿）：右上角「更多」菜单 —— flutter_miuix
          //   组件实现（胶囊三点按钮 + MiuixOverlayDialog 弹层,窄屏底部/
          //   宽屏居中,响应式统一,与全部页面同一组件同一菜单项)。
          C26MoreMenu(),
        ],
        scrollBehavior: _collapse,
        backdrop: _topBackdrop,
      ),
      content: (padding) {
        // v1.12.1：内容避让顶栏（padding.top = topBar 高度）。
        // v1.14.0：填充首页卡片布局（C-27~C-30，响应式）。
        // v1.17.4：左右 16dp 外边距（Miuix/HyperOS 卡片列表标准，卡片不再顶屏边）。
        // v1.22.0（C-34）：摘要区(C-27)固定顶置整宽 + 下方响应式卡片网格。
        final Widget list = ListView(
          // v1.18.x（T1）：列表按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          // v1.23.0:拖拽排序进行中 → 禁用滚动(避免手势冲突),结束恢复全局 Bouncing。
          physics: ref.watch(dragActiveProvider)
              ? const NeverScrollableScrollPhysics()
              : null,
          padding: EdgeInsets.fromLTRB(
            16,
            12 + padding.top,
            16,
            24 + throughInset, // 🔧 C-22 内容穿透底部安全间距
          ),
          addAutomaticKeepAlives: false,
          children: const <Widget>[
            // 摘要区:固定顶置、不参与网格/排序。
            // v1.25.0:阴影圆角对齐内层 MiuixCard(16)。
            // v1.26.0:内容动态化(问候语 S-22 + 每日一言 S-21,组件内部订阅)。
            CardShadow(radius: 16, child: C27HomeSummary()),
            SizedBox(height: 16),
            C34ResponsiveCardGrid(),
          ],
        );
        // v1.12.2（功耗优化，参考 KernelSU）：快照先画 surface 底色 + 采样 6 帧。
        final Widget listWithBg = ColoredBox(
          color: colors.surface,
          child: list,
        );
        final Widget captured = _topBackdrop != null
            ? C28DownsampledCapture(
                backdrop: _topBackdrop!,
                child: CaptureHeartbeat(everyNFrames: 4, child: listWithBg),
              )
            : list;
        return Material(
          type: MaterialType.transparency,
          // 🔧 v1.0.7（保留）：Column + MainAxisAlignment.start 强制顶格。
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    // v1.12.0：MiuixScrollBehaviorListener 桥接滚动折叠。
                    child: MiuixScrollBehaviorListener(
                      behavior: _collapse,
                      child: captured,
                    ),
                  ),
                ],
              ),
              // ✨ v1.5.0 / T30 避让：C-24 毛玻璃 FAB（右下角，动态避让底栏）。
              C24FrostedFab(
                onPressed: _noop,
                child: MiuixIcon(
                  vector: appIcon('add'),
                  size: 24,
                  tint: colors.onSurface,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
