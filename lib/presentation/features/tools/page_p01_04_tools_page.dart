// === 文件: lib/presentation/features/tools/page_p01_04_tools_page.dart ===
// 编号：P-01-04 工具集页（F-04 工具集模块，v1.13.0 占位；v1.34.0 落地；
//   v1.35.0 目录 JSON 化 + 分类折叠）
// 说明：一级页面（底栏第二项）—— 「按 UAPI 实测分类分组」折叠面板：
//   - 数据源 toolCatalogProvider（assets/tools/tools.json 启动预加载）;
//   - 每组 = C-42 分类折叠面板(默认折叠、点击展开、展开才渲染)：
//     头部(分类图标+名+工具数+箭头) + 分割线 + 自适应入口网格
//     (列数 gridColumnsForWidth:<600→2 / 600-1099→3 / ≥1100→4);
//   - 入口按钮 C-36:点按进工具(定制路由或 /tool/:id),长按 500ms 添加首页;
//   - Steam 工具仍走定制页 /steam（customRoute），其余走通用页。
// 结构：与首页一致 —— C-25 顶部毛玻璃标题栏、C-26 更多菜单、快照毛玻璃。
// 功耗：静止零 ticker;分组默认折叠(懒渲染);滚动时才采样。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/tool_config.dart';
import '../../providers/settings_providers.dart';
import '../../providers/tool_items_provider.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/c42_tool_category_panel.dart';

/// 工具页分组内边距(与 C03 组卡外边距一致,面板对齐卡片边缘)。
const double _kGroupHorizontal = 12;

class PageP0104ToolsPage extends ConsumerStatefulWidget {
  const PageP0104ToolsPage({super.key});

  @override
  ConsumerState<PageP0104ToolsPage> createState() => _PageP0104ToolsPageState();
}

class _PageP0104ToolsPageState extends ConsumerState<PageP0104ToolsPage> {
  // v1.44.0(UI)：左上角不再放占位假按钮,与待办页统一。

  // ── C-25：顶部折叠滚动行为(v1.42.0:顶栏纯蒙版,无页面级快照采样)──
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '工具',
        largeTitle: '工具集',
        actions: const <Widget>[
          // C-26 顶部更多菜单（设置/关于入口）。
          C26MoreMenu(),
        ],
        scrollBehavior: _collapse,
      ),
      content: (padding) {
        final Widget list = ListView(
          // v1.18.x（T1）：列表按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(
            top: 12 + padding.top,
            bottom: 24 + throughInset,
          ),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            // ── v1.35.0：分类折叠面板（默认折叠;懒渲染）──
            for (final ToolCategoryNode node in _groups()) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _kGroupHorizontal,
                ),
                child: C42ToolCategoryPanel(node: node),
              ),
              const SizedBox(height: 18),
            ],
          ],
        );
        // v1.42.0(④A):摘除页面级采样(C-28/心跳) — 滚动零 toImageSync。
        final Widget listWithBg = ColoredBox(
          color: colors.surface,
          child: list,
        );
        return Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
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

  /// 工具目录分组（启动已预加载;同步读 Store,永不 loading）。
  List<ToolCategoryNode> _groups() =>
      ref.watch(toolCatalogProvider);
}
