// lib/presentation/widgets/c50_splash_gate.dart
// 编号：C-50 开屏 Gate（v1.44.0 试验：首帧预热；v1.44.x 原生式品牌开屏）
// 说明：
//   - 冷启动后品牌开屏：真实应用 logo(assets/images/app_icon.png,与
//     Android launcher 图标同图) + surface 底 —— 与 Android 12+ 系统
//     Splash 同图同底，双段无缝衔接（原生段：系统缩放淡出到 Flutter 首帧；
//     Flutter 段：本层承接品牌时长）。最短展示 ~1100ms，淡出 320ms；
//   - 开屏期间**底层真实渲染首页**（child 先绘制、开屏盖其上）——首页首帧
//     提前完成绘制（消除首帧调度/交互首 stall）；结束淡出后完全摘除
//     （零持续成本）；
//   - 重播（v1.44.x 后台复位）：订阅 S-24 —— 后台 ≥15s 复位发生时若仍后台
//     则挂起，回前台 resume 即重播；若复位发生在前台则立即重播。重播时
//     首帧条件视为已满足（首页已渲染过），仅走最短展示计时；
//   - main() 显式启用（static enabled；widget 测试不跑 main → 不受影响）；
//   - 独立文件：整体可回滚。
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/constants/app_constants.dart';
import '../../core/lifecycle/app_lifecycle_controller.dart';

/// C-50 开屏 Gate（包在 MaterialApp 的 Navigator 外层 content 上）。
class C50SplashGate extends StatefulWidget {
  const C50SplashGate({super.key, required this.child});

  /// 由 main() 显式开启（测试/预览保持关闭）。
  static bool enabled = false;

  final Widget child;

  @override
  State<C50SplashGate> createState() => _C50SplashGateState();
}

class _C50SplashGateState extends State<C50SplashGate>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 开屏生命周期：showing → fading → gone。
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320), // 淡出(原生式缓出)
  );

  /// 最短品牌展示(logo 可读 + 首页首帧从容) —— v1.44.x 由 700ms 调至 1100ms。
  static const Duration _minShow = Duration(milliseconds: 1100);

  bool _minElapsed = false; // 最短展示计时到。
  bool _firstFrame = false; // 首页首帧已渲染（首帧绘制完成信号）。
  bool _gone = false;
  Timer? _minTimer;

  /// 当前生命周期（重播时机判定用）。
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// 后台期间收到复位信号 → 挂起，resume 即重播。
  bool _pendingReplay = false;

  @override
  void initState() {
    super.initState();
    if (!C50SplashGate.enabled) {
      _gone = true;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    AppLifecycleController.instance.addListener(_onResetSignal);
    _startShow();
  }

  /// 冷启动首次展示：最短计时 + 首帧信号。
  void _startShow() {
    _minTimer = Timer(_minShow, () {
      if (!mounted) return;
      setState(() => _minElapsed = true);
      _maybeFadeOut();
    });
    // 首帧后（child 已被绘制 → 首页首帧完成）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _firstFrame = true);
      _maybeFadeOut();
    });
  }

  /// 重播（后台复位后回前台 / 前台复位当下）。
  void _replay() {
    if (!C50SplashGate.enabled || !mounted) return;
    if (!_gone) return; // 已在展示中，忽略重复信号。
    setState(() {
      _gone = false;
      _minElapsed = false;
      _firstFrame = true; // 已渲染过 → 不再等首帧，仅走最短展示。
    });
    _fadeCtrl.value = 0;
    _minTimer?.cancel();
    _startShow();
  }

  void _onResetSignal() {
    // S-24 复位广播：前台(已可见)立即重播；仍后台则挂起等 resume。
    if (_lifecycle == AppLifecycleState.resumed) {
      _replay();
    } else {
      _pendingReplay = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed && _pendingReplay) {
      _pendingReplay = false;
      _replay();
    }
  }

  @override
  void dispose() {
    AppLifecycleController.instance.removeListener(_onResetSignal);
    WidgetsBinding.instance.removeObserver(this);
    _minTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _maybeFadeOut() {
    if (!_minElapsed || !_firstFrame || _gone) return;
    if (_fadeCtrl.isAnimating) return;
    unawaited(_fadeCtrl.forward().whenComplete(() {
      if (mounted) setState(() => _gone = true);
    }));
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    // 开屏进行中：child 在底层被真实渲染（首帧绘制提前），开屏层覆盖其上。
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        // 淡出动画结束后把开屏层摘除。
        FadeTransition(
          opacity: _fadeCtrl,
          child: _SplashContent(),
        ),
      ],
    );
  }
}

/// 品牌开屏内容（真实应用 logo，原生式：同底同图 + 轻微放大淡入）。
class _SplashContent extends StatefulWidget {
  @override
  State<_SplashContent> createState() => _SplashContentState();
}

class _SplashContentState extends State<_SplashContent>
    with SingleTickerProviderStateMixin {
  /// 入场：淡入 + 0.92→1 轻微放大（easeOut，原生系统 splash 同节奏，无弹性）。
  late final AnimationController _inCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  )..forward();

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _inCtrl,
    curve: Curves.easeOut,
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1.0)
      .animate(CurvedAnimation(parent: _inCtrl, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _inCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return ColoredBox(
      // 与原生 Splash 同底色系（浅 surface / 深 surface 近似）。
      color: colors.surface,
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                // 真实应用 logo（与 Android launcher ic_launcher 同图，
                // launcher 图自带圆角背景，ClipRRect 兜底不裁内容）。
                'assets/images/app_icon.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: MiuixText(
                    AppConstants.appName.substring(0, 1), // ASCII 首字母兜底
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
