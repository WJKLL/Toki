// lib/presentation/features/settings/page_p01_02_01_theme_config_page.dart
// 编号：P-01-02-01 主题与色彩配置页（F-08 主题与 Monet 模块 / §10）
// 配置项：深色模式（S-01 状态机）· Monet 开关 · keyColor 种子色 · PaletteStyle
// 🔧 修改（v1.4.3 / T24）：接入 C-23 内容推动折叠标题栏（push 型二级页，
//   leading 为返回胶囊按钮），顶栏为 CustomScrollView 首个 sliver。
// 功耗要点：
//   - 色板由 S-01 / MiuixThemeController 一次性生成并缓存，本页 build 零计算（§10.3）。
//   - 实时预览区 RepaintBoundary 隔离；种子色切换为单次主题注入。
//   - 🔧 修复（v1.0.6）：本页为交互型页面（开关/分段/色板），**禁止**整体
//     TickerMode(enabled:false)，否则开关圆点/分段指示器动画被静音冻结
//     （"功能生效但视觉不变"根因）；0 网络、0 轮询（§11.6）。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Colors, Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/u02_color_utils.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/c03_group_card.dart';
import '../../../core/widgets/c05_warning_card.dart';
import '../../../domain/entities/app_settings.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';

class PageP010201ThemeConfigPage extends ConsumerStatefulWidget {
  const PageP010201ThemeConfigPage({super.key});

  @override
  ConsumerState<PageP010201ThemeConfigPage> createState() =>
      _PageP010201ThemeConfigPageState();
}

class _PageP010201ThemeConfigPageState
    extends ConsumerState<PageP010201ThemeConfigPage> {
  static const List<String> _styleLabels = <String>[
    'TonalSpot',
    'Vibrant',
    'Expressive',
    'Neutral',
  ];

  /// 🔧 修复：PaletteStyle 字符串 → 分段索引（未知键归一化回退 0，
  ///   与 S-01 色板映射 kPaletteStyleMap 的兜底一致，防止高亮错位）。
  static int _styleIndexFor(String style) {
    final int index = kPaletteStyleOptions.indexOf(style);
    return index < 0 ? 0 : index;
  }

  static const EdgeInsets _itemMargin = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );

  /// 🔧 修改（v1.4.3 / T24）：push 型二级页 leading = 返回。
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('theme.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  // ── C-25（v1.12.3）：顶部毛玻璃快照源 + 折叠滚动行为 ──
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
    // ⚡ 功耗优化：顶部快照释放。
    _topBackdrop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    final AppSettingsController controller = ref.read(
      appSettingsProvider.notifier,
    );
    final PlatformInfo platform = ref.watch(platformInfoProvider);

    final bool systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    // 深色模式开关展示值：显式模式取其值，跟随系统时取系统亮度。
    final bool darkNow = settings.uiMode == AppUiMode.system
        ? systemDark
        : settings.uiMode == AppUiMode.dark;

    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // v1.12.3（C-25）：顶部毛玻璃 U-03 裁决 + 快照幂等同步。
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: settings.blurEnabled,
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);

    // 🔧 修复（v1.0.6）：交互型页面不得整体 TickerMode(false)——否则 MiuixSwitch
    //   圆点动画与 MiuixTabRow 指示器被静音冻结（"功能生效但视觉不变"根因）。
    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      // v1.12.3（C-25）：顶部毛玻璃标题栏（KernelSU TopAppBar 样式）。
      topBar: C25FrostedTopBar(
        title: '主题与色彩',
        largeTitle: '主题与色彩',
        navigationIcon: _backButton, // 左 1 按钮（返回）
        actions: <Widget>[
          // v1.13.0（C-26）：顶部更多菜单。
          C26MoreMenu(backdrop: _topBackdrop),
        ],
        scrollBehavior: _collapse,
        backdrop: _topBackdrop,
      ),
      content: (padding) {
        // v1.12.3：内容避让顶栏；快照画 surface 底色 + 采样 6 帧。
        final Widget list = ListView(
          // v1.18.x（T1）：列表按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(top: 12 + padding.top, bottom: 24),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            // ── 深色模式（S-01 状态机）──
            C03GroupCard(
              children: [
                // 🔧 修复（P-01-02-01）：深色模式开关 value 绑定 darkNow（S-01 状态
                //   实时推导），点击 → setDarkOverride → ref.watch 重建 → 高亮/开关
                //   跟随；显式 Key 固化元素身份（见 P-01-02 switch.monet 注释）。
                MiuixSwitchPreference(
                  key: const ValueKey('switch.dark'),
                  title: '深色模式',
                  summary: settings.uiMode == AppUiMode.system
                      ? '跟随系统（当前${darkNow ? '深色' : '浅色'}）'
                      : (darkNow ? '已开启' : '已关闭'),
                  value: darkNow,
                  onChanged: (v) => controller.setDarkOverride(v),
                  insideMargin: _itemMargin,
                ),
                const C03IndentDivider(),
                MiuixSwitchPreference(
                  key: const ValueKey('switch.monetTheme'),
                  title: 'Monet 动态取色',
                  summary: platform.supportsWallpaperMonet
                      ? (settings.monetEnabled
                            ? '已启用 · Android 12+ 壁纸取色'
                            : '未启用（Android 12+ 可读取壁纸色）')
                      : (settings.monetEnabled
                            ? '已启用 · 使用手动种子色生成'
                            : '未启用（本平台仅支持手动种子色）'),
                  value: settings.monetEnabled,
                  onChanged: controller.setMonetEnabled,
                  insideMargin: _itemMargin,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── 取色种子色（keyColor，§10.2）──
            C03GroupCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: MiuixText('取色种子色（keyColor）', style: textStyles.title4),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  // 🔧 修复（P-01-02-01）：显式 Key 防止列表/分组元素复用时
                  //   StatefulWidget 内部状态残留导致选中环（高亮）不跟随。
                  child: _KeyColorSwatches(
                    key: const ValueKey('keyColorSwatches'),
                    selected: settings.keyColor ?? AppConstants.defaultKeyColor,
                    onSelected: controller.setKeyColor,
                  ),
                ),
                const C03IndentDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiuixText('取色风格（PaletteStyle）', style: textStyles.title4),
                      const SizedBox(height: 10),
                      // 🔧 修复（C-13 胶囊分段）：高亮索引 = 状态映射的归一化值，
                      //   点击 → setPaletteStyle → ref.watch(appSettingsProvider)
                      //   重建本页 → selectedTabIndex 更新 → 高亮跟随状态。
                      //   未知风格键归一化回退 0（与 S-01 色板映射一致），
                      //   杜绝旧持久化脏数据导致"功能已生效但高亮错位"。
                      MiuixTabRow(
                        key: const ValueKey('paletteStyle'),
                        tabs: _styleLabels,
                        selectedTabIndex: _styleIndexFor(settings.paletteStyle),
                        onTabSelected: (i) =>
                            controller.setPaletteStyle(kPaletteStyleOptions[i]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── 实时预览（RepaintBoundary 隔离）──
            C03GroupCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: MiuixText('当前色板预览', style: textStyles.title4),
                ),
                const RepaintBoundary(child: _PalettePreview()),
                const SizedBox(height: 12),
              ],
            ),
            const SizedBox(height: 12),

            if (settings.monetEnabled && !platform.supportsWallpaperMonet) ...[
              const C05WarningCard(
                message: '当前平台无法读取壁纸色，Monet 使用手动种子色生成静态色板（§10.2 降级）',
              ),
            ],
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
          // 🔧 v1.0.7（布局稳定性）：Column + MainAxisAlignment.start 强制顶格。
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // v1.12.3：MiuixScrollBehaviorListener 桥接滚动折叠。
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
}

/// keyColor 预置色板（U-02 十六进制标注；静态 const 色值表）。
class _KeyColorSwatches extends StatelessWidget {
  const _KeyColorSwatches({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = MiuixTheme.of(context).colors.onBackground;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final Color c in AppConstants.presetKeyColors)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(c),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == c ? borderColor : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 当前主题核心色板预览（只读 MiuixTheme，U-02 输出十六进制）。
class _PalettePreview extends StatelessWidget {
  const _PalettePreview();

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _roleRow(context, 'primary', colors.primary),
          const SizedBox(height: 8),
          _roleRow(context, 'secondary', colors.secondary),
          const SizedBox(height: 8),
          _roleRow(context, 'background', colors.background),
          const SizedBox(height: 8),
          _roleRow(context, 'surface', colors.surface),
          const SizedBox(height: 8),
          _roleRow(context, 'error', colors.error),
        ],
      ),
    );
  }

  Widget _roleRow(BuildContext context, String name, Color color) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: MiuixTheme.of(context).colors.outline
                  .withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        MiuixText(name, style: MiuixTheme.of(context).textStyles.body1),
        const Spacer(),
        // ⚡ 功耗优化：U-02 纯字符串拼接，无 Allocation 热点。
        MiuixText(
          U02ColorUtils.toHex(color),
          style: MiuixTheme.of(context).textStyles.body2,
          color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
        ),
      ],
    );
  }
}
