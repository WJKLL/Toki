// === 文件: lib/core/widgets/tool_brand_icon.dart ===
// 编号：C-38 工具徽标（v1.35.0 泛化：Steam 自绘 → 工具图标统一出口）
// 说明：工具/分类图标渲染 —— 'custom:steam' 走 C-38 自绘徽标；
//   其余取 MiuixIcons.extended（工具 icon 缺省回退分类 icon，再缺省回退箭头）。
//   C-36 入口 / C-37 首页卡 / C-42 分类面板 / P-09 通用页统一经此出口。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../domain/entities/tool_config.dart';
import 'app_icons.dart';
import 'steam_logo_icon.dart';

/// 工具图标统一渲染（尺寸/着色可调，与 C-38 SteamLogoIcon 同参数风格）。
class ToolBrandIcon extends StatelessWidget {
  const ToolBrandIcon({
    super.key,
    required this.tool,
    this.fallbackIcon,
    this.size = 24,
    this.tint,
  });

  final ToolConfig tool;

  /// 分类图标名（工具 icon 为空时兜底）。
  final String? fallbackIcon;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (tool.icon == 'custom:steam') {
      return SteamLogoIcon(
        size: size,
        tint: tint ?? MiuixTheme.of(context).colors.onSurfaceVariantActions,
      );
    }
    final String name = tool.icon.isNotEmpty
        ? tool.icon
        : (fallbackIcon != null && fallbackIcon!.isNotEmpty
              ? fallbackIcon!
              : tool.category.icon);
    return MiuixIcon(vector: appIcon(name), size: size, tint: tint);
  }
}
