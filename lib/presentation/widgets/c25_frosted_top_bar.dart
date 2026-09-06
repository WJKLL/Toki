// lib/presentation/widgets/c25_frosted_top_bar.dart
// 编号:C-25 顶部标题栏(v1.12.0 登记;v1.24.0 纯蒙版定稿;
//   v1.44.1 回官方方案:撤销自绘蒙版,背景直接由 flutter_miuix 官方
//   MiuixTopAppBar(blurred:) 渲染 —— 均匀毛玻璃 + 官方色调,
//   门控同 U-03:Android 13+ 且用户开 blurEnabled 才真模糊,
//   否则官方纯色 surface(不透明,零采样)。折叠行为保持官方原样。)
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';

/// C-25 顶部标题栏(官方毛玻璃方案)。
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

  /// 页面级顶部快照源(兼容保留:菜单 C-26 仍消费;官方 blurred 方案
  /// 直接采样身后内容,本组件不再消费快照)。
  final MiuixBackdrop? backdrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // U-03 裁决:用户开关 × 平台能力 → 是否允许官方毛玻璃。
    final bool blur = ref.watch(effectiveBlurProvider);

    return MiuixTopAppBar(
      title: title,
      largeTitle: largeTitle,
      subtitle: subtitle,
      navigationIcon: navigationIcon,
      actions: actions,
      scrollBehavior: scrollBehavior,
      // blurred:true → 官方毛玻璃(整条均匀 BackdropFilter + 色调);
      // blurred:false → 官方纯色不透明 surface(Web/<13/用户关闭)。
      blurred: blur,
    );
  }
}
