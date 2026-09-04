// lib/presentation/widgets/c22_content_through_floating_bottom_bar.dart
// 编号：C-22 内容穿透悬浮底栏
// v1.18.0 重构：悬浮胶囊形态整体替换为 demo 内核
//   （KernelFloatingBottomBar，miuix_bottombar_demo backup_08 移植，
//   含速度形变 v2、内阴影前景立体、方案 C 底栏本体采样、边缘折射、
//   手势优化 —— 任意 tab 按下即反馈 + 松手回位与落下重叠）。
// 说明：
//   悬浮栏模式 = demo 内核（固定紧凑胶囊 _itemWidth=76、居中悬浮，
//     1:1 参考 KernelSU FloatingBottomBar.kt）；
//   普通模式 = C22MaskSelectionBar（无拖动、无毛玻璃）。
// 保留 C22BarItemData（数据源）与 contentBottomInset（几何单一来源），
// 供页面/FAB/蒙版分支引用；参数不再经 C22VisualParams（内核自带 demo 原值）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_icons.dart';
import '../providers/settings_providers.dart';
import 'c22_mask_selection_bar.dart';
import 'c22_visual_params.dart';
import 'kernel/kernel_bottombar.dart';

/// 底栏胶囊项数据（icon 名 + 标签；icon 经 appIcon 惰性查找）。
/// 悬浮分支在内核构造处转成 [KernelBarItem]（Miuix 矢量图标）。
class C22BarItemData {
  const C22BarItemData(this.iconName, this.label);

  final String iconName;
  final String label;
}

/// C-22 内容穿透悬浮底栏（双模式编排器：悬浮内核 / 蒙版选择框）。
class C22ContentThroughFloatingBottomBar extends ConsumerWidget {
  const C22ContentThroughFloatingBottomBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.items,
    this.backdrop,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<C22BarItemData> items;

  /// T50（P1）：页面级毛玻璃快照源（main_shell_page U-03 门控创建；
  ///   Web / Android<13 为 null → 内核降级半透明）。
  final MiuixLayerBackdrop? backdrop;

  /// 悬浮胶囊几何常量（内核侧 1:1 参考值，与 C22 页面留白共用）。
  static const double kPillHeight = 64; // 内核 _pillHeight
  static const double kBottomSpacing = 12; // 底部外间距（demo main_kernel）

  /// 内容穿透所需底部安全间距（页面/悬浮 FAB 用，几何单一来源）。
  static double contentBottomInset(BuildContext context) {
    return kPillHeight +
        kBottomSpacing +
        C22VisualParams.contentClearance +
        MediaQuery.viewPaddingOf(context).bottom;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool floatingBar = ref.watch(
      appSettingsProvider.select((s) => s.floatingBarEnabled),
    );
    final double gestureInset = MediaQuery.viewPaddingOf(context).bottom;

    final Widget bar = floatingBar
        ? _wrapKernelBar(
            context,
            items: items,
            currentIndex: currentIndex,
            onSelected: onDestinationSelected,
            backdrop: backdrop,
            bottomInset: kBottomSpacing + gestureInset,
          )
        : C22MaskSelectionBar(
            currentIndex: currentIndex,
            onDestinationSelected: onDestinationSelected,
            items: items,
          );

    // ⚡ 功耗优化：整栏 RepaintBoundary 隔离 —— 页面滚动零底栏重绘。
    return RepaintBoundary(child: bar);
  }

  /// demo 内核悬浮胶囊（固定紧凑宽度、居中；bottomInset = 底部间距 + 手势区）。
  Widget _wrapKernelBar(
    BuildContext context, {
    required List<C22BarItemData> items,
    required int currentIndex,
    required ValueChanged<int> onSelected,
    required MiuixLayerBackdrop? backdrop,
    required double bottomInset,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: KernelFloatingBottomBar(
          selectedIndex: currentIndex,
          onSelected: onSelected,
          backdrop: backdrop,
          items: [
            for (final C22BarItemData d in items)
              KernelBarItem(label: d.label, icon: appIcon(d.iconName)),
          ],
          isBlurEnabled: backdrop != null,
        ),
      ),
    );
  }
}
