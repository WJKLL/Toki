// lib/presentation/features/palette/page_p02_color_palette_page.dart
// 编号：P-02 色彩调色板页（F-05 色彩调色板模块）
// 说明：展示当前主题（Miuix / Monet 模式）生成的完整色板角色（只读，§10.3 缓存色板）。
// 🔧 修改（v1.4.3 / T24）：接入 C-23 内容推动折叠标题栏（push 型二级页，
//   leading 为返回胶囊按钮），顶栏为 CustomScrollView 首个 sliver。
// 功耗要点：
//   - SliverGrid + mainAxisExtent 固定行高（§11.3 固定高度条目）；零逐项测量。
//   - 每格 RepaintBoundary 隔离；色板数据为 const 表，build 零对象创建。
//   - 静态页 0 ticker（TickerMode(false) 保留，C-23 无动画控制器）。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/u02_color_utils.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';

class PageP02ColorPalettePage extends ConsumerStatefulWidget {
  const PageP02ColorPalettePage({super.key});

  @override
  ConsumerState<PageP02ColorPalettePage> createState() =>
      _PageP02ColorPalettePageState();
}

class _PageP02ColorPalettePageState
    extends ConsumerState<PageP02ColorPalettePage> {
  /// 展示的 MiuixColors 语义角色（const 表，§11.2 静态配置）。
  static const List<(String, String)> _roles = <(String, String)>[
    ('primary', 'primary'),
    ('onPrimary', 'onPrimary'),
    ('primaryVariant', 'primaryVariant'),
    ('primaryContainer', 'primaryContainer'),
    ('secondary', 'secondary'),
    ('secondaryContainer', 'secondaryContainer'),
    ('tertiaryContainer', 'tertiaryContainer'),
    ('background', 'background'),
    ('onBackground', 'onBackground'),
    ('surface', 'surface'),
    ('onSurface', 'onSurface'),
    ('surfaceVariant', 'surfaceVariant'),
    ('surfaceContainer', 'surfaceContainer'),
    ('surfaceContainerHigh', 'surfaceContainerHigh'),
    ('surfaceContainerHighest', 'surfaceContainerHighest'),
    ('error', 'error'),
    ('errorContainer', 'errorContainer'),
    ('outline', 'outline'),
    ('dividerLine', 'dividerLine'),
    ('sliderBackground', 'sliderBackground'),
  ];

  /// 🔧 修改（v1.4.3 / T24）：push 型二级页 leading = 返回。
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('palette.back'),
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
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    // v1.12.3（C-25）：顶部毛玻璃 U-03 裁决 + 快照幂等同步。
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: ref.watch(appSettingsProvider.select((s) => s.blurEnabled)),
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);
    final MiuixColors colors = MiuixTheme.of(context).colors;

    // v1.12.3：移除 TickerMode(false) —— MiuixTopAppBar 内部有小标题弹簧
    //   AnimationController，静音会冻结折叠动画；静止零 ticker。
    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      // v1.12.3（C-25）：顶部毛玻璃标题栏（KernelSU TopAppBar 样式）。
      topBar: C25FrostedTopBar(
        title: '色彩调色板',
        largeTitle: '色彩调色板',
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
        final Widget grid = GridView.builder(
          // v1.18.x（T1）：网格按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(top: 12 + padding.top, bottom: 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 84,
          ),
          itemCount: _roles.length,
          itemBuilder: (context, index) {
            final (String label, String field) = _roles[index];
            return RepaintBoundary(
              child: _RoleTile(label: label, field: field),
            );
          },
        );
        final Widget gridWithBg = ColoredBox(
          color: colors.surface,
          child: grid,
        );
        final Widget captured = _topBackdrop != null
            ? C28DownsampledCapture(
                backdrop: _topBackdrop!,
                child: CaptureHeartbeat(everyNFrames: 4, child: gridWithBg),
              )
            : grid;
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

/// 单个色板角色格：角色名 + 色值（U-02）+ 色块。
class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.label, required this.field});

  final String label;
  final String field;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // 通过镜像字段名读取角色色（仅本页使用的固定角色集合）。
    final Color color = _read(colors, field);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.outline.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiuixText(
                  label,
                  style: MiuixTheme.of(context).textStyles.body1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          MiuixText(
            U02ColorUtils.toArgbHex(color), // ⚡ 功耗优化：U-02 纯函数拼接
            style: MiuixTheme.of(context).textStyles.body2,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  static Color _read(MiuixColors colors, String field) {
    return switch (field) {
      'primary' => colors.primary,
      'onPrimary' => colors.onPrimary,
      'primaryVariant' => colors.primaryVariant,
      'primaryContainer' => colors.primaryContainer,
      'secondary' => colors.secondary,
      'secondaryContainer' => colors.secondaryContainer,
      'tertiaryContainer' => colors.tertiaryContainer,
      'background' => colors.background,
      'onBackground' => colors.onBackground,
      'surface' => colors.surface,
      'onSurface' => colors.onSurface,
      'surfaceVariant' => colors.surfaceVariant,
      'surfaceContainer' => colors.surfaceContainer,
      'surfaceContainerHigh' => colors.surfaceContainerHigh,
      'surfaceContainerHighest' => colors.surfaceContainerHighest,
      'error' => colors.error,
      'errorContainer' => colors.errorContainer,
      'outline' => colors.outline,
      'dividerLine' => colors.dividerLine,
      'sliderBackground' => colors.sliderBackground,
      _ => colors.primary,
    };
  }
}
