// lib/presentation/widgets/c21_collapsing_title_bar.dart
// 编号：C-21 折叠标题栏（v1.2.0 登记 / v1.3.0 增强 actions，PROJECT_SPEC §5）
// 说明：滚动折叠标题栏。PROJECT_SPEC §1 禁止 Material 组件（SliverAppBar/
//       FlexibleSpaceBar 均为 Material 组件），故采用 flutter_miuix 原生能力：
//       MiuixTopAppBar(largeTitle) + MiuixExitUntilCollapsedScrollBehavior 实现
//       「展开大标题 ⇄ 折叠小标题」—— 等价模板语义：
//         pinned:true / floating:false → ExitUntilCollapsed（折叠后固定小标题）
//         expandedHeight:120 / collapsedHeight:56 → 库内大/小标题态高度
//         大号 28sp 居中 / 小号 18sp 居中 → 库内 title1 / 小标题样式
// 🔧 修改（v1.3.0 / T7）：新增 actions 参数 —— 已核实 MiuixTopAppBar 构造函数
//   原生暴露 `actions` 槽位（路径 A 直通，无需自定义 Row）；标题居中由库内
//   titlePadding 保证，不被右侧按钮挤偏。
// 功耗要点（验收：滚动 build ≤2 次/帧；静止 ticker 停止）：
//   - 折叠量是滚动位置纯函数（库实现），滚动期间仅顶栏子树重建；
//   - 松手吸附动画 280ms 一次性，静止后 ticker 立即回收；
//   - 整栏 RepaintBoundary 隔离，列表滚动不触发顶栏重绘（§11.2.3）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/u03_blur_policy.dart';
import '../providers/platform_providers.dart';

/// C-21 滚动折叠标题栏（组件封装层，Cxx 前缀，默认 RepaintBoundary）。
///
/// 使用方（页面 State）持有 [scrollBehavior]，并把它同时传给本组件与
/// `MiuixScrollBehaviorListener`（包裹滚动内容），实现联动折叠：
/// ```dart
/// final _collapse = MiuixExitUntilCollapsedScrollBehavior();
/// MiuixScaffold(
///   topBar: C21CollapsingTitleBar(
///     title: '首页',
///     largeTitle: 'Toki',
///     scrollBehavior: _collapse,
///     actions: _placeholderActions, // 🔧 v1.3.0：右上角操作按钮
///   ),
///   content: (p) => MiuixScrollBehaviorListener(
///     behavior: _collapse,
///     child: ListView(...),
///   ),
/// );
/// ```
class C21CollapsingTitleBar extends ConsumerWidget {
  const C21CollapsingTitleBar({
    super.key,
    required this.title,
    this.largeTitle,
    this.subtitle = '',
    this.navigationIcon,
    this.actions,
    required this.scrollBehavior,
  });

  /// 折叠后的小标题。
  final String title;

  /// 展开态大标题（为 null 时不展开，等价普通顶栏）。
  final String? largeTitle;

  /// 副标题（展开时在大标题下方，折叠时在小标题下方）。
  ///
  /// 🔧 修复（v1.3.2 / T14）：注意 —— MiuixTopAppBar 的 subtitle 在**折叠态
  ///   也会渲染为小标题下方的第二行**（`Positioned(top: smallTitleBottomForLayout)`），
  ///   长副标题会使折叠头部变为两行、栏高增大（52→63+），造成"标题被压低 +
  ///   顶部空白"的视觉问题。折叠态期望与参考（KernelSU）一致的紧凑单行头部时，
  ///   **调用方不应传 subtitle**（或保持极短单行）。
  final String subtitle;

  /// ✨ 交互修复（v1.3.3 / T16）：左侧导航按钮（leading）。默认 null → 不显示。
  ///   与 actions 同处折叠带（垂直中心对齐，始终在顶部按钮行），不随滚动移动；
  ///   由 MiuixTopAppBar 原生 navigationIcon 槽位渲染。
  final Widget? navigationIcon;

  /// 🔧 修改（v1.3.0 / T7）：右上角操作按钮（trailing）。
  ///   默认 null → 不显示任何按钮；传入 → 由 MiuixTopAppBar 原生 actions
  ///   槽位渲染（路径 A 直通，标题居中不被挤偏）。
  final List<Widget>? actions;

  /// 滚动行为：由使用方页面 State 持有，并同时传给 MiuixScrollBehaviorListener。
  final MiuixExitUntilCollapsedScrollBehavior scrollBehavior;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    // U-03 毛玻璃裁决（§11.7）：Web 一律禁用，Android 13+ 开启；sigma ≤ 20。
    final bool blurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: true,
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );

    // ⚡ 功耗优化：整栏 RepaintBoundary 隔离 —— 列表滚动/内容重建不触发顶栏重绘；
    //   静止时无 ticker（折叠量 = 滚动位置纯函数，吸附动画 280ms 一次性回收）。
    //
    // ✨ 交互修复（v1.3.3 / T16）：以下交互由 MiuixTopAppBar 原生实现（非 Material
    //   SliverAppBar，§1 禁止）：
    //   - 大标题：Positioned(top: collapsedHeight + effectiveOffset) 随滚动上移，
    //     在折叠带边缘 ClipRect 裁剪消失（等价 CollapseMode.parallax 语义）；
    //   - 小标题：跨 1/3 折叠阈值后弹簧滑入（上浮 20px + 淡入）；
    //   - 按钮行（navigationIcon + actions）：常驻折叠带，不随滚动移动；
    //   - 完全折叠：小标题与左右按钮同以折叠带垂直中心对齐（同一水平行）。
    return RepaintBoundary(
      child: MiuixTopAppBar(
        title: title,
        largeTitle: largeTitle,
        subtitle: subtitle,
        navigationIcon: navigationIcon, // ✨ v1.3.3 / T16：左侧按钮（leading）
        actions: actions, // 🔧 v1.3.0 / T7：路径 A 直通 MiuixTopAppBar.actions
        scrollBehavior: scrollBehavior,
        blurred: blurAllowed, // Web 禁用 / Android 13+ 开启（U-03）
        blurRadius: U03BlurPolicy.clampSigma(10), // demo 低模糊 12→10
      ),
    );
  }
}

/// C-21 顶栏图标按钮（MIUI 无底，官方 MiuixPressable 遮罩反馈）。
///
/// v1.44.x（MIUI 无底化）：原「36×36 半透明胶囊背景 + 折叠阈值换 alpha」为
/// Material 式常驻背景，不符合 MIUI 设计语言 —— 顶栏导航按钮应为无底纯图标，
/// 按压仅浮现浅色圆形遮罩（onBackground@0.10，spring 驱动，官方
/// MiuixPressable 内建）。collapseState 从未被任何调用方传入（10 个二级页均
/// 只传 icon/tooltip/onTap），随背景一并摘除：组件改为 Stateless，零监听
/// 零重建。热区 40×40（官方 MiuixIconButtonDefaults.minWidth/minHeight），
/// 视觉图标 20。
class C21CapsuleIconButton extends StatelessWidget {
  const C21CapsuleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  /// Miuix 矢量图标（经 appIcon 惰性查找，禁 Material Icons）。
  final MiuixVectorIcon icon;

  /// 无障碍标签（Semantics）。
  final String tooltip;

  final VoidCallback? onTap;

  /// 热区边长 / 视觉图标尺寸（官方 IconButton 默认 40 / 20）。
  static const double kSize = 40;
  static const double kIconSize = 20;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return MiuixPressable(
      onPressed: onTap,
      semanticLabel: tooltip,
      borderRadius: BorderRadius.circular(kSize / 2), // 圆形按压遮罩
      child: SizedBox(
        width: kSize,
        height: kSize,
        child: Center(
          child: MiuixIcon(
            vector: icon,
            size: kIconSize,
            tint: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
