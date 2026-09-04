// lib/presentation/widgets/c23_push_collapsing_header.dart
// 编号：C-23 内容推动折叠标题栏（连续替换模式，PROJECT_SPEC §5 已登记）
// ✨ 新增：C-23 内容推动折叠标题栏（连续替换模式）
// 说明：SliverPersistentHeader + 自定义 SliverPersistentHeaderDelegate 实现
//       （widgets 库原语，零 Material 视觉组件，§1 合规）：
//   - 动作行（左 1 + 右 2 胶囊按钮，36×36 squircle 20px）常驻顶部，不随滚动移动；
//   - 大标题（28px 级，Miuix title1 令牌）：展开态左边缘与左按钮左边缘对齐
//     （left = kSideInset），随滚动 **1:1** 上移（top -= shrinkOffset），移出屏幕顶；
//   - 小标题（18px 级，Miuix title3 令牌）：从顶部外下滑入
//     （top -= (1-t)×小标题行高），t = shrinkOffset/(max-min) 钳制 [0,1]；
//   - 交叉淡入：文字色 alpha（大 1-t / 小 t），**直接改颜色值**（withValues，
//     等价模板 withOpacity），**禁止** Opacity / AnimatedOpacity widget；
//   - 折叠态小标题水平中心 = 左按钮组与右按钮组的几何中心（纯算术，零测量）；
//   - 背景/字体/颜色全 Miuix 令牌；毛玻璃按 U-03 策略：本组件为全宽 header，
//     超出「区域 ≤200×200px」约束（§11.7.2），故不叠加 BackdropFilter，
//     使用纯 surface 背景（Web/低版本同样安全）。
// 功耗要点：滚动期间仅 header 子树重绘（SliverPersistentHeader 内部驱动，
//   build ≤2 次/帧）；静止零 ticker（无任何 AnimationController）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// C-23 内容推动折叠标题栏（连续替换模式）。
///
/// 作为 `CustomScrollView` 的首个 sliver 使用：
/// ```dart
/// CustomScrollView(slivers: [
///   C23PushCollapsingHeader(
///     leading: leadingButton,
///     actions: [a, b],
///     largeTitle: 'Toki',
///     smallTitle: '首页',
///   ),
///   SliverList(...),
/// ])
/// ```
class C23PushCollapsingHeader extends ConsumerWidget {
  const C23PushCollapsingHeader({
    super.key,
    required this.leading,
    required this.actions,
    required this.largeTitle,
    required this.smallTitle,
  });

  /// 左 1 按钮（36×36 胶囊，调用方提供）。
  final Widget leading;

  /// 右 2 按钮（36×36 胶囊列表）。
  final List<Widget> actions;

  /// 大标题（展开态，28px 级，左对齐）。
  final String largeTitle;

  /// 小标题（折叠态，18px 级，居中）。
  final String smallTitle;

  // 静态几何常量（§11.2 static const，纯算术定位，零测量）。
  static const double kSideInset = 16; // 左右留白
  static const double kButtonSize = 36; // 胶囊按钮尺寸
  static const double kButtonRadius = 20; // 胶囊圆角
  static const double kButtonGap = 12; // 按钮组与标题区间隙
  static const double kRowHeight = 56; // 动作行高（按钮所在行）
  static const double kLargeAreaHeight = 64; // 大标题区高（120-56）
  static const double kLargeTopGap = 12; // 大标题距动作行下缘
  static const double kSmallTitleHeight = 24; // 小标题行高估算（18px 级，纯算术）

  /// 左按钮组右缘（含间隙）——用于小标题居中间隙（静态常量，零 build 计算）。
  static const double kLeftGroupRight = kSideInset + kButtonSize + kButtonGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double topInset = MediaQuery.paddingOf(context).top;
    // 🔧 修复（v1.5.2 / T32）：注册 MiuixTheme 依赖 —— 主题切换（S-01 →
    //   MiuixThemeController → MiuixTheme 数据变化）时本组件立即重建，
    //   并携带最新 MiuixThemeData 供 delegate.shouldRebuild 比较。
    //   此前 delegate.build 虽读取 MiuixTheme.of(context)，但 SliverPersistentHeader
    //   仅在 shouldRebuild 为 true 或 shrinkOffset 变化时才重跑 delegate.build；
    //   shouldRebuild 不比较主题 → 主题切换后颜色停留旧值，直到滑动才刷新。
    final MiuixThemeData theme = MiuixTheme.of(context);
    // U-03 毛玻璃策略：本组件为全宽 header，超出 §11.7.2「模糊区域 ≤200×200px」
    // 约束，故不叠加 BackdropFilter（Web/Android<13 亦禁用，纯 surface 背景）。
    return SliverPersistentHeader(
      pinned: true, // 动作行始终钉在顶部
      delegate: _C23PushCollapsingDelegate(
        leading: leading,
        actions: actions,
        largeTitle: largeTitle,
        smallTitle: smallTitle,
        topInset: topInset,
        theme: theme, // 🔧 修复：主题数据传入 delegate（shouldRebuild 比较用）
      ),
    );
  }
}

/// C-23 自定义 SliverPersistentHeaderDelegate。
class _C23PushCollapsingDelegate extends SliverPersistentHeaderDelegate {
  _C23PushCollapsingDelegate({
    required this.leading,
    required this.actions,
    required this.largeTitle,
    required this.smallTitle,
    required this.topInset,
    required this.theme,
  });

  final Widget leading;
  final List<Widget> actions;
  final String largeTitle;
  final String smallTitle;
  final double topInset;

  /// 🔧 修复（v1.5.2 / T32）：当前主题数据（shouldRebuild 比较用）。
  final MiuixThemeData theme;

  @override
  double get minExtent => topInset + C23PushCollapsingHeader.kRowHeight;
  @override
  double get maxExtent =>
      topInset +
      C23PushCollapsingHeader.kRowHeight +
      C23PushCollapsingHeader.kLargeAreaHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // t = 折叠进度，钳制 [0,1]（T17 边界：快速甩动/橡皮筋不越界）。
    final double t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);

    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final double width = MediaQuery.sizeOf(context).width;

    // 纯算术几何（无 RenderBox/TextPainter 测量）：
    final double buttonTop =
        topInset +
        (C23PushCollapsingHeader.kRowHeight -
                C23PushCollapsingHeader.kButtonSize) /
            2;
    // 左按钮组右缘（含间隙）——静态常量；右按钮组左缘依赖屏宽（运行时）。
    const double leftGroupRight = C23PushCollapsingHeader.kLeftGroupRight;
    final double rightGroupLeft =
        width -
        C23PushCollapsingHeader.kSideInset -
        C23PushCollapsingHeader.kButtonSize -
        C23PushCollapsingHeader.kButtonGap;
    // 小标题水平中心 = 左右按钮组几何中心；垂直中心 = 动作行中心，从顶部外滑入。
    final double smallCenterX = (leftGroupRight + rightGroupLeft) / 2;
    final double smallTop =
        topInset +
        C23PushCollapsingHeader.kRowHeight / 2 -
        C23PushCollapsingHeader.kSmallTitleHeight / 2 -
        (1 - t) * C23PushCollapsingHeader.kSmallTitleHeight;

    // 大标题：左边缘与左按钮左边缘对齐（left = kSideInset），1:1 随内容上移。
    final double largeTop =
        topInset +
        C23PushCollapsingHeader.kRowHeight +
        C23PushCollapsingHeader.kLargeTopGap -
        shrinkOffset;

    // 交叉淡入：文字色 alpha（直接改颜色值；等价模板 withOpacity，非 Opacity widget）。
    final Color base = colors.onSurface;
    final Color largeColor = base.withValues(alpha: 1.0 - t);
    final Color smallColor = base.withValues(alpha: t);

    return ColoredBox(
      color: colors.surface, // 背景盖住下方滚动内容（纯 surface，§U-03 无模糊）
      child: Stack(
        children: [
          // 大标题（展开态，随滚动上移并移出屏幕顶；越界部分由视口裁剪）。
          Positioned(
            left: C23PushCollapsingHeader.kSideInset,
            top: largeTop,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width - C23PushCollapsingHeader.kSideInset * 2,
              ),
              child: Text(
                largeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis, // T17：标题超长截断
                style: textStyles.title1.copyWith(color: largeColor),
              ),
            ),
          ),
          // 小标题（折叠态，从顶部外滑入；水平居中于按钮组几何中心）。
          Positioned(
            left: smallCenterX - (rightGroupLeft - leftGroupRight) / 2,
            width: rightGroupLeft - leftGroupRight,
            top: smallTop,
            height: C23PushCollapsingHeader.kSmallTitleHeight,
            child: Text(
              smallTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textStyles.title3.copyWith(color: smallColor),
            ),
          ),
          // 动作行（常驻顶部，不随滚动移动）：
          Positioned(
            left: C23PushCollapsingHeader.kSideInset,
            top: buttonTop,
            child: leading, // 左 1 按钮
          ),
          Positioned(
            right: C23PushCollapsingHeader.kSideInset,
            top: buttonTop,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: actions, // 右 2 按钮
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _C23PushCollapsingDelegate oldDelegate) {
    // 🔧 修复（v1.5.2 / T32）：主题变化（MiuixThemeData 含 colors/textStyles/
    //   brightness，值相等性比较）→ 返回 true → sliver 重布局 → delegate.build
    //   以最新主题重跑，标题/背景色立即同步刷新（无需滑动）。
    return oldDelegate.theme != theme ||
        oldDelegate.largeTitle != largeTitle ||
        oldDelegate.smallTitle != smallTitle ||
        oldDelegate.leading != leading ||
        oldDelegate.actions != actions ||
        oldDelegate.topInset != topInset;
  }
}
