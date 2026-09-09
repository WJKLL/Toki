// === 文件: lib/core/widgets/glow_tab_row.dart ===
// 编号:GLOW-04 分段选择器 + 选中项光感(2026-09-09)
// 说明:MiuixTabRow 的选中指示器由组件内部绘制(Squircle + 纯色),无法直接叠加
//   光感 → 此处用 Stack 在**选中项位置**叠一层同形状的纯绘制光感。
//
// 形状与系统一致:MiuixTabRowDefaults.tabRowCornerRadius = 12(Squircle)。
// 性能:纯 Canvas、零 blur;shouldRepaint 仅参数变化 → 静止零重绘;
//   档位「关」时完全不构造 Stack/CustomPaint。
//
// v1.50.1 修复两处:
//   1. **整条背景去色** —— MiuixTabRow 默认 `SizedBox(width: double.infinity)`
//      + `ColoredBox(colors.surface)`,即一条撑满宽度、直角的 surface 底色带;
//      在底部 sheet(底色 colors.background)等非 surface 容器里会呈现为一个
//      显眼的大方块 → 传 backgroundColor 透明,只保留选中项指示块。
//   2. **指示器几何对齐** —— 原实现按 `maxWidth / tabs.length` 定位,未扣除
//      MiuixTabRow 的 itemSpacing(9),项数越多偏差越大;改用与
//      `_calculateTabWidth` 一致的算法(minWidth 下限 76),并注意
//      SingleChildScrollView 横向内容为左对齐(非居中)。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'glow_material.dart';
import 'glow_tokens.dart';

/// 带选中项光感的 MiuixTabRow 包装。
class GlowTabRow extends StatelessWidget {
  const GlowTabRow({
    super.key,
    required this.tabs,
    required this.selectedTabIndex,
    required this.onTabSelected,
  });

  final List<String> tabs;
  final int selectedTabIndex;
  final ValueChanged<int> onTabSelected;

  /// 与 MiuixTabRowDefaults.tabRowCornerRadius 一致。
  static const double _cornerRadius = 12;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // v1.50.1：去掉整条 surface 底色（透明）—— 选中项仍用 surfaceContainer
    //   指示块，其余区域直接透出所在容器底色。
    final Widget row = MiuixTabRow(
      tabs: tabs,
      selectedTabIndex: selectedTabIndex,
      onTabSelected: onTabSelected,
      colors: MiuixTabRowColors(
        backgroundColor: const Color(0x00000000),
        contentColor: colors.onSurfaceVariantSummary,
        selectedBackgroundColor: colors.surfaceContainer,
        selectedContentColor: colors.onBackground,
      ),
    );
    final GlowScope? scope = GlowScope.maybeOf(context);
    final GlowLevel? level = scope == null ? GlowLevel.gentle : scope.level;
    if (level == null || tabs.isEmpty) {
      return row;
    }
    final bool dark = MiuixTheme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!constraints.hasBoundedWidth) {
          return row;
        }
        // 与 MiuixTabRow._calculateTabWidth 一致：扣除项间距后均分，
        // 低于 minWidth(76) 时取 minWidth（此时内容可横向滚动）。
        const double spacing = MiuixTabRowDefaults.tabRowItemSpacing;
        final double ideal =
            (constraints.maxWidth - spacing * (tabs.length - 1)) / tabs.length;
        final double tabWidth = ideal < MiuixTabRowDefaults.tabRowMinWidth
            ? MiuixTabRowDefaults.tabRowMinWidth
            : ideal;
        final int index = selectedTabIndex.clamp(0, tabs.length - 1);
        // 横向 SingleChildScrollView 的内容为左对齐（非居中）。
        final double left = index * (tabWidth + spacing);
        return Stack(
          children: <Widget>[
            row,
            Positioned(
              left: left,
              top: 0,
              bottom: 0,
              width: tabWidth,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: GlowIndicatorPainter(
                    dark: dark,
                    level: level,
                    shape: const MiuixSquircleBorder(
                      cornerRadius: _cornerRadius,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
