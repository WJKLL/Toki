// lib/presentation/widgets/c26_more_menu.dart
// 编号：C-26 顶部「更多」菜单（v1.13.0 登记;v1.32.0 重构:v1.32.1 定稿）
// 职责：页面右上角三点「更多」入口 + 悬浮展开菜单（设置 / 关于,可扩展）。
// 实现（v1.32.1 定稿,用户三连纠正后）：
//   - 触发器：**裸三点图标（无圆形/胶囊蒙版背景）** —— MiuixOverlayIconDropdownMenu
//     的 child 直接放 MiuixIcon（热区由组件内 MiuixIconButton 承担,背景默认空,
//     仅按压缩放反馈）；
//   - 菜单：flutter_miuix 官方 **悬浮展开菜单**（对应参考项目 KernelSU/miuix-kmp
//     的 OverlayIconDropdownMenu 同款实现）—— 点击图标后从锚点弹出悬浮圆角
//     面板（自动测锚点定位,非底部弹层、非居中对话框;collapseOnSelection
//     选中即收,点外部/返回关闭;面板样式/动画由 miuix 组件内建,深色/Monet
//     主题自动跟随;Overlay 变体挂在 MiuixScaffold 弹层内,页面级覆盖）；
//   - 菜单项：icon + 文字,点击 context.push 跳转（路由由调用方项配置）;
//     items 默认取 moreMenuItemsProvider(全页面统一);
//   - 兼容：backdrop 参数保留但不再消费（旧毛玻璃快照方案已退役）。
// 功耗：未展开时仅静态图标;展开状态由组件内部管理,收起零开销。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_icons.dart';
import '../providers/nav_items_providers.dart';

/// 顶部菜单项（C-26 数据项；iconName 经 appIcon 惰性查找）。
class MoreMenuItem {
  const MoreMenuItem({
    required this.iconName,
    required this.label,
    required this.route,
  });

  final String iconName;
  final String label;
  final String route;
}

/// C-26 顶部「更多」悬浮菜单（裸三点图标触发 + miuix 官方悬浮展开菜单）。
class C26MoreMenu extends ConsumerWidget {
  const C26MoreMenu({super.key, this.backdrop, this.items});

  /// v1.32.0：兼容保留 —— 旧毛玻璃快照源已退役，本组件不再消费。
  final MiuixBackdrop? backdrop;

  /// 菜单项（默认取 moreMenuItemsProvider：设置/关于）。
  final List<MoreMenuItem>? items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final List<MoreMenuItem> menuItems =
        items ?? ref.read(moreMenuItemsProvider);
    return MiuixOverlayIconDropdownMenu(
      entry: MiuixDropdownEntry(
        items: <MiuixDropdownItem>[
          for (final MoreMenuItem item in menuItems)
            MiuixDropdownItem(
              text: item.label,
              icon: MiuixIcon(
                vector: appIcon(item.iconName),
                size: 20,
                tint: colors.onSurface,
              ),
              onClick: () => context.push(item.route),
            ),
        ],
      ),
      // 裸三点图标（无圆形蒙版背景;热区 40dp 由组件内 IconButton 承担）。
      child: MiuixIcon(
        vector: appIcon('more'),
        size: 22,
        tint: colors.onSurface,
      ),
    );
  }
}
