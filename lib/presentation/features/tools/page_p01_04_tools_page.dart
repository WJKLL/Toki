// lib/presentation/features/tools/page_p01_04_tools_page.dart
// 编号：P-01-04 工具集页（F-04 工具集模块，v1.13.0 占位；v1.34.0 落地）
// 说明：一级页面（底栏第二项）—— 「🎮 游戏工具」分组 + 响应式入口网格:
//   - 分组标题 16sp w600 + 淡分割线(outlineVariant 语义,色板缺 token 时
//     以 outline 35% alpha 近似) + 入口按钮网格(48dp 高 / 12dp 间距 /
//     列数 = gridColumnsForWidth 与首页网格同源:<600→2 / 600-1099→3 /
//     ≥1100→4);
//   - 入口按钮 C-36:点按进工具页(R-11),长按 500ms 添加至首页(C-37);
//   - 目录数据 kToolCatalog(domain/entities/tool_item.dart)。
// 结构：与首页一致 —— C-25 顶部毛玻璃标题栏（MiuixTopAppBar 折叠 + 快照毛玻璃）、
//   C-26 顶部更多菜单、内容 MiuixLayerBackdropCapture 捕获（采样 6 帧 + surface 底色）。
// 功耗：静止零 ticker（CaptureHeartbeat 被动帧回调）；滚动时才采样。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../domain/entities/tool_item.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/c34_responsive_card_grid.dart';
import '../../widgets/c36_tool_entry_button.dart';

/// 工具页分组内边距(与 C03 组卡外边距一致,标题/网格对齐卡片边缘)。
const double _kGroupHorizontal = 12;

class PageP0104ToolsPage extends ConsumerStatefulWidget {
  const PageP0104ToolsPage({super.key});

  @override
  ConsumerState<PageP0104ToolsPage> createState() => _PageP0104ToolsPageState();
}

class _PageP0104ToolsPageState extends ConsumerState<PageP0104ToolsPage> {
  /// 顶栏按钮（build 外定义；一级页 leading 菜单占位）。
  late final Widget _navigationIcon = C21CapsuleIconButton(
    key: const ValueKey('tools.navigation'),
    icon: appIcon('sidebar'),
    tooltip: '菜单',
    onTap: _noop,
  );

  static void _noop() {}

  // ── C-25：顶部毛玻璃快照源 + 折叠滚动行为 ──
  MiuixLayerBackdrop? _topBackdrop;
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

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
    _topBackdrop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: ref.watch(appSettingsProvider.select((s) => s.blurEnabled)),
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);
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
        navigationIcon: _navigationIcon,
        actions: <Widget>[
          // C-26 顶部更多菜单（设置/关于入口）。
          C26MoreMenu(backdrop: _topBackdrop),
        ],
        scrollBehavior: _collapse,
        backdrop: _topBackdrop,
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
            // ── v1.34.0：🎮 游戏工具分组 ──
            _buildGameGroup(context),
          ],
        );
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MiuixScrollBehaviorListener(
                  behavior: _collapse,
                  child: captured,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 分组标题 + 分割线 + 自适应入口网格。
  Widget _buildGameGroup(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kGroupHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 分组标题(16sp w600)。
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: MiuixText(
              '🎮 游戏工具',
              style: textStyles.body1.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 分割线(outlineVariant 语义近似)。
          Container(height: 0.5, color: colors.outline.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          // 入口网格:列数与首页网格同源(<600→2 / 600-1099→3 / ≥1100→4)。
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double availW = constraints.maxWidth;
              final int cols = gridColumnsForWidth(availW);
              const double gap = kGridCardGap;
              final double cellW = (availW - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  for (final ToolItem item in kToolCatalog)
                    SizedBox(
                      width: cellW,
                      child: C36ToolEntryButton(item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
