// lib/presentation/widgets/c25_frosted_top_bar.dart
// 编号:C-25 顶部标题栏(v1.12.0 登记;v1.24.0 方案替换:毛玻璃 → 纯蒙版)
// 说明:顶部标题区背景不再采样/模糊,采用纯蒙版(用户定稿):
//   - 动效开关(blurEnabled)开启 → 渐变蒙版(上限实色 0.97,下限 0.58,
//     S 形曲线,过渡带底 32% —— v1.24.3 A 档遮瑕参数);
//   - 关闭 → 普通不透明遮罩(实色);
//   - 颜色取 Miuix token surfaceContainer(深浅色/Monet 自适应)。
// 功耗:纯静态一次 gradient,零 ticker;backdrop 参数兼容保留(菜单消费)。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';

/// C-25 顶部标题栏(纯蒙版背景)。
class C25FrostedTopBar extends ConsumerWidget {
  const C25FrostedTopBar({
    super.key,
    required this.title,
    this.largeTitle,
    this.subtitle = '',
    this.navigationIcon,
    this.actions,
    required this.scrollBehavior,
    this.backdrop,
  });

  final String title;
  final String? largeTitle;
  final String subtitle;
  final Widget? navigationIcon;
  final List<Widget>? actions;
  final MiuixExitUntilCollapsedScrollBehavior scrollBehavior;

  /// 页面级顶部快照源(兼容保留:菜单 C-26 仍消费;本组件不再使用)。
  final MiuixBackdrop? backdrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool smoothMask = ref.watch(
      appSettingsProvider.select((s) => s.blurEnabled),
    );
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Color base = colors.surfaceContainer;

    final MiuixTopAppBar bar = MiuixTopAppBar(
      title: title,
      largeTitle: largeTitle,
      subtitle: subtitle,
      navigationIcon: navigationIcon,
      actions: actions,
      scrollBehavior: scrollBehavior,
      color: const Color(0x00000000),
      blurred: false,
    );

    // ⚡ 功耗优化:整栏一次静态绘制(实色或一次 gradient),RepaintBoundary 隔离。
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          // v1.24.3(A 档遮瑕定稿):下限 0.58 + 过渡带底 32% + S 形曲线
          // (中度可见区最窄,高对比内容边缘快速穿越,横带不可见)。
          gradient: smoothMask
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    base.withValues(alpha: 0.97),
                    base.withValues(alpha: 0.97),
                    base.withValues(alpha: 0.93),
                    base.withValues(alpha: 0.86),
                    base.withValues(alpha: 0.78),
                    base.withValues(alpha: 0.70),
                    base.withValues(alpha: 0.63),
                    base.withValues(alpha: 0.58),
                  ],
                  stops: const <double>[
                    0.00,
                    0.68,
                    0.75,
                    0.82,
                    0.88,
                    0.93,
                    0.97,
                    1.00,
                  ],
                )
              : null,
          color: smoothMask ? null : base,
        ),
        child: bar,
      ),
    );
  }
}
