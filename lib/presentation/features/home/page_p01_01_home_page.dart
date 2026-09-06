// lib/presentation/features/home/page_p01_01_home_page.dart
// 编号：P-01-01 首页（F-02 首页模块）
// v1.13.1：清空首页内容（列表空），仅保留结构 —— 顶部 C-25 毛玻璃标题栏、
//   C-26 更多菜单、内容快照捕获；底栏 / 顶部不受影响。
// v1.49.0：删除右下占位「+」FAB(无功能入口;与工具/待办页一致不留占位钮)。
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
import '../../providers/drag_active_provider.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
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
  // v1.44.0(UI)：左上角不再放占位假按钮(无功能且多余背景),与待办页统一。
  // v1.49.0：右下占位「+」FAB 一并删除。

  // ── C-25（v1.12.0）：顶部折叠滚动行为（顶栏已纯蒙版,无快照采样）──
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  @override
  Widget build(BuildContext context) {
    // 🔧 v1.2.0（C-22 内容穿透）：悬浮底栏开启时，底部追加穿透安全间距。
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;
    final MiuixColors colors = MiuixTheme.of(context).colors;

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      // v1.12.0（C-25）：顶部标题栏（KernelSU TopAppBar 样式）。
      topBar: C25FrostedTopBar(
        title: '首页',
        largeTitle: AppConstants.appName,
        actions: const <Widget>[
          // v1.32.0（C-26 重构定稿）：右上角「更多」菜单 —— flutter_miuix
          //   组件实现（胶囊三点按钮 + MiuixOverlayDialog 弹层,窄屏底部/
          //   宽屏居中,响应式统一,与全部页面同一组件同一菜单项)。
          C26MoreMenu(),
        ],
        scrollBehavior: _collapse,
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
            // v1.44.x:暗色高光内建进 CardShadow,摘要卡自动获得。
            CardShadow(radius: 16, child: C27HomeSummary()),
            SizedBox(height: 16),
            C34ResponsiveCardGrid(),
          ],
        );
        // v1.12.2（功耗优化）：快照先画 surface 底色。
        // v1.42.0(④A):摘除页面级采样(C-28/心跳) —— 顶栏/菜单均不再消费
        //   快照,滚动零 toImageSync;shell 层采样(悬浮胶囊)唯一保留。
        final Widget listWithBg = ColoredBox(
          color: colors.surface,
          child: list,
        );
        return Material(
          type: MaterialType.transparency,
          // 🔧 v1.0.7（保留）：Column + MainAxisAlignment.start 强制顶格。
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // v1.12.0：MiuixScrollBehaviorListener 桥接滚动折叠。
                child: MiuixScrollBehaviorListener(
                  behavior: _collapse,
                  child: listWithBg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
