// lib/presentation/providers/nav_items_providers.dart
// 编号：C-22 / C-26 辅助件（底栏项 / 更多菜单项数据源，v1.13.0）
// 职责：底栏项与顶部更多菜单项统一配置 —— 新增一级页面时在底栏项追加、
//   新增功能入口时在菜单项追加，页面/底栏自动跟随（动态项数）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/c22_content_through_floating_bottom_bar.dart';
import '../widgets/c26_more_menu.dart';

/// 底栏项（C-22 动态项数数据源：与 PageView 页数同源派生）。
final bottomBarItemsProvider = Provider<List<C22BarItemData>>(
  (ref) => const [C22BarItemData('home', '首页'), C22BarItemData('tools', '工具')],
);

/// 顶部「更多」菜单项（C-26：设置 / 关于，后期可扩展）。
final moreMenuItemsProvider = Provider<List<MoreMenuItem>>(
  (ref) => const [
    MoreMenuItem(iconName: 'tune', label: '设置', route: '/settings'),
    MoreMenuItem(iconName: 'info', label: '关于', route: '/about'),
  ],
);
