// lib/presentation/router/app_router.dart
// 编号：S-03 导航服务（go_router 装配，R-01 ~ R-10 路径路由）
// 说明：
//   - T64（v1.10.0 一级页面横滑）：一级页面改为自定义 PageView shell（MainShellPage），
//     不再使用 StatefulShellRoute.indexedStack —— 其内部 StatefulNavigationShell 将
//     IndexedStack 硬编码、不暴露 branch 内容，无法在 shell 层换成 PageView。
//     因三个一级页面均为单页（无子路由栈），改用「单 shell route + query 页索引」。
//   - 路径语义冻结（§7）：/home /settings /about 仍可访问，redirect 落地为 /?page=N；
//     未知路径统一回 /?page=0。
//   - R-05/R-06/R-09 为顶层路由（push 覆盖 shell）。
//   - v1.29.0（二级页转场）：全部路由（含 shell R-01）改用 CustomTransitionPage +
//     miuix_route_transitions 统一转场（右滑入/让位 1/4/压暗/圆角，复刻参考项目
//     miuix-navigation3-ui 0.9.2 NavDisplay）。动效开关（blurEnabled）关闭时退回
//     NoTransitionPage 直切 —— pageBuilder 每次导航实时读开关，切换即时生效。
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/about/page_p01_03_about_page.dart';
import '../features/palette/page_p02_color_palette_page.dart';
import '../features/permissions/page_p03_permissions_page.dart';
import '../features/settings/page_p01_02_settings_page.dart';
import '../features/settings/page_p01_02_01_theme_config_page.dart';
import '../features/timetable/page_p06_timetable_page.dart';
import '../features/tools/page_p08_steam_query_page.dart';
import '../features/tools/page_p09_tool_generic.dart';
import '../shell/main_shell_page.dart';
import '../providers/settings_providers.dart';
import 'miuix_route_transitions.dart';
import '../../core/logging/app_log_service.dart';

/// 已冻结的合法路径集合（R-xx 速查，§7）。
/// v1.13.0：/settings /about 从 PageView 一级页改为顶层二级路由（push 覆盖
///   shell，由顶部「更多」菜单进入）；/tools 新增为一级页（底栏第二项）。
const Set<String> _knownPaths = <String>{
  '/', // R-01 主框架（PageView shell）
  '/home', // R-02（→ /?page=0）
  '/tools', // R-03（→ /?page=1，一级页：工具集）
  '/settings', // R-04（顶层二级页：设置）
  '/about', // R-05（顶层二级页：关于）
  '/color-palette', // R-06
  '/permissions', // R-07
  '/settings/theme', // R-08
  '/timetable', // R-10（大课表编辑页，二级页面）
  '/steam', // R-11（v1.34.0 P-08：Steam 用户查询页，二级页面）
  // R-12（v1.35.0 P-09）：通用工具页为动态路径 /tool/:toolId，不入本集合，
  //   redirect 中以 /tool/ 前缀放行（见 redirect 分支）。
};

/// v1.29.0：单一路由页工厂 —— 动效开关开 → MIUI 风格转场；
/// 关 → NoTransitionPage 直切（低性能档惯例）。每次导航实时读取开关。
Page<Object?> _pageFor(BuildContext context, Widget child) {
  // Riverpod 3 无 context.read 扩展，经容器读取（listen:false 零订阅）。
  final bool motion =
      ProviderScope.containerOf(context, listen: false)
          .read(appSettingsProvider)
          .blurEnabled;
  if (!motion) return NoTransitionPage<Object?>(child: child);
  return CustomTransitionPage<Object?>(
    child: child,
    transitionDuration: kMiuixRouteTransitionDuration,
    reverseTransitionDuration: kMiuixRouteTransitionDuration,
    transitionsBuilder: buildMiuixRouteTransitions,
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final GoRouter router = GoRouter(
    initialLocation: '/?page=0',
    redirect: (context, state) {
      final String path = state.uri.path;
      // v1.10.3（S-13 覆盖增强）：路由跳转日志（开关关闭时零成本）。
      AppLogService.instance.info('router', '路由: ${state.uri}');
      // T64：/home /tools 映射到 shell 的 PageView 页索引。
      if (path == '/' || path == '/home') return '/?page=0';
      if (path == '/tools') return '/?page=1';
      // v1.13.0：/settings /about 为顶层二级页（菜单进入），不 redirect。
      // v1.35.0：/tool/:toolId 动态路径（R-12 通用工具页）前缀放行。
      if (path.startsWith('/tool/')) return null;
      // R-01 '/' 与未知路径统一回主框架首页（§7）。
      if (!_knownPaths.contains(path)) return '/?page=0';
      return null;
    },
    routes: <RouteBase>[
      // ── R-01 主框架（PageView shell；被二级页覆盖时让位/压暗）──
      GoRoute(
        path: '/',
        name: 'R-01',
        pageBuilder: (context, state) =>
            _pageFor(context, const MainShellPage()),
      ),
      // ── 顶层路由（R-04 ~ R-08，push 覆盖 shell）─────────────────────
      GoRoute(
        path: '/settings',
        name: 'R-04',
        pageBuilder: (context, state) =>
            _pageFor(context, const PageP0102SettingsPage()),
      ),
      GoRoute(
        path: '/about',
        name: 'R-05',
        pageBuilder: (context, state) =>
            _pageFor(context, const PageP0103AboutPage()),
      ),
      GoRoute(
        path: '/color-palette',
        name: 'R-06',
        pageBuilder: (context, state) =>
            _pageFor(context, const PageP02ColorPalettePage()),
      ),
      GoRoute(
        path: '/permissions',
        name: 'R-07',
        pageBuilder: (context, state) =>
            _pageFor(context, const PageP03PermissionsPage()),
      ),
      GoRoute(
        path: '/settings/theme',
        name: 'R-08',
        pageBuilder: (context, state) =>
            _pageFor(context, const PageP010201ThemeConfigPage()),
      ),
      GoRoute(
        path: '/timetable',
        name: 'R-10',
        pageBuilder: (context, state) =>
            _pageFor(context, const PageP06TimetablePage()),
      ),
      // v1.34.0（P-08）：Steam 用户查询(工具页入口 / 首页工具卡进入)。
      GoRoute(
        path: '/steam',
        name: 'R-11',
        pageBuilder: (context, state) =>
            _pageFor(context, const PageP08SteamQueryPage()),
      ),
      // v1.35.0（P-09 / R-12）：通用工具页（/tool/:toolId；定制路由工具
      //   如 Steam 走各自页面，不经此处）。
      GoRoute(
        path: '/tool/:toolId',
        name: 'R-12',
        pageBuilder: (context, state) {
          final String toolId = state.pathParameters['toolId'] ?? '';
          return _pageFor(context, PageP09ToolGenericPage(toolId: toolId));
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
