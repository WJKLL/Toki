// lib/presentation/widgets/c24_frosted_fab.dart
// 编号：C-24 毛玻璃悬浮按钮（FAB，v1.5.0，PROJECT_SPEC §5 已登记）
// ✨ 新增：C-24 毛玻璃 FAB（右下角快速操作入口）
// 说明：
//   - 胶囊形状 MiuixSquircleBorder（56×56 默认），右下角悬浮（由 MiuixScaffold
//     floatingActionButton 槽位定位，MiuixFabPosition.end → 右下、底栏上方）。
//   - 毛玻璃：U-03 策略（§11.7）——Android 13+ 开启 BackdropFilter（sigma ≤ 20，
//     区域 56×56 远小于 40% 视口）；Web / Android<13 降级为半透明表面色。
//   - 采用与 C-22 相同的 BackdropFilter 模式（模板建议的 MiuixTextureBlur 需
//     页面级 MiuixBackdrop 捕获 + ChangeNotifier 生命周期，对 FAB 属过度设计；
//     本实现零生命周期、Stateless、语义等价）。
// 功耗要点：RepaintBoundary 隔离（父级重绘不影响 FAB）；单层阴影（§11.2.4）；
//   静止零 ticker（无动画控制器）。
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/u03_blur_policy.dart';
import '../providers/platform_providers.dart';
import '../providers/settings_providers.dart';
import 'c22_content_through_floating_bottom_bar.dart';

/// C-24 毛玻璃悬浮按钮（FAB）。
class C24FrostedFab extends ConsumerWidget {
  const C24FrostedFab({
    super.key,
    required this.onPressed,
    required this.child,
    this.size = 56,
    this.elevation = 4,
  });

  /// 点击回调（占位可传空函数；后续接入具体功能）。
  final VoidCallback onPressed;

  /// 图标或文字内容。
  final Widget child;

  /// 按钮边长（默认 56，Material 系 FAB 标准）。
  final double size;

  /// 阴影高度（单层，§11.2.4 允许 1 层）。
  final double elevation;

  // 静态配置（§11.2 / 全局约束）。
  static const double _cornerRadius = 18; // 胶囊圆角（squircle）
  static const double _blurSigma = 10; // sigma ≤ 20（§11.7.3；demo 低模糊 12→10）
  static const double _blurredBgAlpha = 0.20; // 毛玻璃态半透明 tint
  static const double _fallbackBgAlpha = 0.88; // 降级态表面色不透明度

  /// 右下角右间距（固定）。
  static const double kRightInset = 24;

  /// 底栏关闭时的底部间距。
  static const double kDefaultBottom = 24;

  /// 位置过渡动画（200ms 一次性，§11.5 允许 ≤600ms）。
  static const Duration _positionAnim = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    // 🔧 修复（v1.5.1 / T30）：监听 C-22 悬浮底栏开关（S-01 状态），
    //   开启时 FAB 上移到底栏上方（复用 C-22 单一几何来源 contentBottomInset
    //   = 胶囊高 + 间隙 + 内容间距 + 手势区），关闭时保持默认右下角间距。
    final bool floatingBar = ref.watch(
      appSettingsProvider.select((s) => s.floatingBarEnabled),
    );
    final double bottom = floatingBar
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : kDefaultBottom;

    // U-03 裁决：Web 禁用 / Android 13+ 开启（§11.7.1）。
    final bool blurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: true,
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    final MiuixColors colors = MiuixTheme.of(context).colors;
    const ShapeBorder shape = MiuixSquircleBorder(cornerRadius: _cornerRadius);

    // 背景色：毛玻璃态低不透明度 tint；降级态高不透明度表面色（可读性）。
    final Color background = colors.surfaceContainerHigh.withValues(
      alpha: blurAllowed ? _blurredBgAlpha : _fallbackBgAlpha,
    );

    Widget button = Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: background,
        shape: shape,
        shadows: <BoxShadow>[
          // 单层阴影（§11.2.4）。
          BoxShadow(
            color: const Color(0x26000000), // black alpha 0.15
            blurRadius: elevation,
            offset: Offset(0, elevation / 2),
          ),
        ],
      ),
      child: Center(child: child),
    );

    // 毛玻璃：仅 Android 13+ 叠加，模糊被 squircle 裁剪限制在按钮区域内（§11.7.2）。
    if (blurAllowed) {
      button = ClipPath(
        clipper: const ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
          child: button,
        ),
      );
    }

    // ⚡ 功耗优化：RepaintBoundary 隔离 —— 父组件重绘不触发 FAB 重绘（§11.2.3）。
    final Widget buttonWidget = RepaintBoundary(
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: button,
        ),
      ),
    );

    // 🔧 修复（v1.5.1 / T30）：右下角悬浮，底部间距随 C-22 悬浮底栏动态避让；
    //   AnimatedPadding(200ms) 使开关切换时位置平滑过渡（§11.5 一次性 ≤600ms）。
    return Align(
      alignment: Alignment.bottomRight,
      child: AnimatedPadding(
        duration: _positionAnim,
        curve: Curves.easeOut,
        padding: EdgeInsets.only(right: kRightInset, bottom: bottom),
        child: buttonWidget,
      ),
    );
  }
}
