// lib/presentation/features/permissions/page_p03_permissions_page.dart
// 编号：P-03 权限管理页（F-06 权限管理模块）
// v1.42.0(④A):摘除页面级采样(C-28/心跳) — 滚动零 toImageSync。
// 说明：权限声明列表与状态展示（参考蓝本 PermissionScreen），静态展示。
// 🔧 修改（v1.4.3 / T24）：接入 C-23 内容推动折叠标题栏（push 型二级页，
//   leading 为返回胶囊按钮），顶栏为 CustomScrollView 首个 sliver。
// 功耗要点：静态页 0 ticker、0 网络（§11.1 / 1-8 功耗检查点）；全 const 构建；
//   SliverList 惰性构建（§11.3）。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/c03_group_card.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';

class PageP03PermissionsPage extends ConsumerStatefulWidget {
  const PageP03PermissionsPage({super.key});

  @override
  ConsumerState<PageP03PermissionsPage> createState() =>
      _PageP03PermissionsPageState();
}

class _PageP03PermissionsPageState
    extends ConsumerState<PageP03PermissionsPage> {
  static const List<(String, String, String)> _permissions =
      <(String, String, String)>[
        // (权限名, 图标 key, 说明)
        ('通知', 'messages', '发送通知以展示换算结果与更新提醒'),
        ('定位', 'location', '定位换算相关功能预留'),
        ('存储', 'folder', '读写换算历史与缓存（预留）'),
        ('相机', 'photos', '扫描识别单位（预留）'),
        ('麦克风', 'mic', '语音输入换算（预留）'),
      ];

  /// 🔧 修改（v1.4.3 / T24）：push 型二级页 leading = 返回。
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('permissions.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  // ── C-25（v1.12.3）：折叠滚动行为（v1.42.0 起纯折叠，无快照采样）──
  /// 顶部折叠滚动行为（MiuixTopAppBar + MiuixScrollBehaviorListener 联动）。
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;

    // v1.12.3：移除 TickerMode(false) —— MiuixTopAppBar 内部有小标题弹簧
    //   AnimationController，静音会冻结折叠动画；静止零 ticker。
    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      // v1.12.3（C-25）：顶部毛玻璃标题栏（KernelSU TopAppBar 样式）。
      topBar: C25FrostedTopBar(
        title: '权限管理',
        largeTitle: '权限管理',
        navigationIcon: _backButton, // 左 1 按钮（返回）
        actions: const <Widget>[
          // v1.13.0（C-26）：顶部更多菜单。
          C26MoreMenu(),
        ],
        scrollBehavior: _collapse,
      ),
      content: (padding) {
        // v1.12.3：内容避让顶栏；快照画 surface 底色 + 采样 6 帧。
        final Widget list = ListView(
          // v1.18.x（T1）：列表按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(top: 12 + padding.top, bottom: 24),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            C03GroupCard(
              children: [
                for (int i = 0; i < _permissions.length; i++) ...[
                  if (i > 0) const C03IndentDivider(),
                  MiuixBasicComponent(
                    title: _permissions[i].$1,
                    summary: _permissions[i].$3,
                    startAction: MiuixIcon(
                      vector: appIcon(_permissions[i].$2),
                      size: 22,
                      tint: MiuixTheme.of(context).colors.primary,
                    ),
                    endActions: const [MiuixBadge(child: Text('未声明'))],
                    insideMargin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
        final Widget listWithBg = ColoredBox(
          color: colors.surface,
          child: list,
        );
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
                  child: listWithBg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
