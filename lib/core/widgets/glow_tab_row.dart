// === 文件: lib/core/widgets/glow_tab_row.dart ===
// 编号:GLOW-04 分段选择器 + 选中项光感(2026-09-09)
// 说明:MiuixTabRow 的选中指示器由组件内部绘制(Squircle + 纯色),无法直接叠加
//   光感 → 此处用 Stack 在**选中项位置**叠一层同形状的纯绘制光感。
//
// 形状与系统一致:MiuixTabRowDefaults.tabRowCornerRadius = 12(Squircle)。
// 性能:纯 Canvas、零 blur;shouldRepaint 仅参数变化 → 静止零重绘;
//   档位「关」时完全不构造 Stack/CustomPaint。
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
    final Widget row = MiuixTabRow(
      tabs: tabs,
      selectedTabIndex: selectedTabIndex,
      onTabSelected: onTabSelected,
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
        final double tabWidth = constraints.maxWidth / tabs.length;
        return Stack(
          children: <Widget>[
            row,
            Positioned(
              left: selectedTabIndex.clamp(0, tabs.length - 1) * tabWidth,
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
