// lib/presentation/widgets/c22_backdrop_heartbeat.dart
// 编号：C-22 内部件（不占编号；T50/P1 采样卡死修复辅助件）
// 职责：MiuixLayerBackdropCapture 的捕获节点是 RepaintBoundary（flutter_miuix
//   v1.1.1 miuix_layer_backdrop.dart:74），页面滚动重绘被 RenderViewport（同为
//   RepaintBoundary）截断 → capture.paint() 仅首帧执行 → 快照冻结。
//   本组件以"透明 CustomPaint 心跳"按需强制捕获子树重绘，使快照实时更新。
// 功耗约束（指令 §3 / §9；v1.10.25 适配系统自适应刷新率）：
//   - 仅悬浮模式 + 毛玻璃开关 + Android 13+（U-03）由 main_shell_page 挂载，
//     否则整树卸载、零开销；
//   - **被动帧回调**：不再持有任何 Ticker / AnimationController —— Flutter
//     无活动 Ticker 时不会主动请求帧，静止场景系统（Android LTPO/动态刷新率）
//     可自动降到低刷新率省电；帧来源 = 页面内容自身的重绘（滚动/动画/切换），
//     内容静止 → 无帧 → 零采样、零开销；
//   - 采样节流：内容每 [everyNFrames] 帧触发一次捕获节点重绘（采样），
//     采样率跟随内容帧率（内容 120Hz → 120/N Hz，N=3 → 40Hz）；
//   - 非采样帧仅做一次计数递增（零 rebuild、零 paint），页面内容（PageView）
//     不在心跳 CustomPaint 子树内，页面刷新率不受影响。
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/scroll_activity_provider.dart';

/// 捕获心跳：按内容帧被动节流的透明 CustomPaint，按需强制所在
/// RepaintBoundary 重新 paint。
///
/// 必须放在 [MiuixLayerBackdropCapture] 的子树内：通过节流的帧生成新的
/// painter 实例且 `shouldRepaint` 在采样帧返回 true → 捕获节点被标记 dirty →
/// RepaintBoundary 重绘 → capture.paint() 重新 toImageSync 采样。
///
/// v1.18.x 采样率活动自适应：滚动/切页中（[scrollActivityProvider] true）用
/// [activeEveryNFrames]（默认 2 帧，快照跟手、消除拖影）；静止用
/// [everyNFrames]（默认 4 帧，省电）。静止无内容帧 → 心跳本就停，静止档
/// 仅在播放动画（如折叠标题）时体现。内容滚动期间 60Hz → 30Hz 采样。
class CaptureHeartbeat extends ConsumerStatefulWidget {
  const CaptureHeartbeat({
    super.key,
    this.everyNFrames = 4,
    this.activeEveryNFrames = 2,
    required this.child,
  });

  /// 静止档采样节流：内容每 N 帧触发一次重绘（v1.18.x：3→4 更省电，
  /// 仅滚动/切页外动画生效；滚动中用 [activeEveryNFrames]）。
  final int everyNFrames;

  /// 活动档（滚动/切页中）采样节流：每 N 帧一次。默认 2 → 快照更新
  /// 频率 = 内容帧率/2（60Hz 内容 30Hz 采样），滚动跟手不拖影。
  final int activeEveryNFrames;

  /// 被捕获的页面内容（普通子树，不随心跳重建）。
  final Widget child;

  @override
  ConsumerState<CaptureHeartbeat> createState() => _CaptureHeartbeatState();
}

class _CaptureHeartbeatState extends ConsumerState<CaptureHeartbeat> {
  /// 心跳帧计数（仅内容实际重绘的帧递增；实际触发采样的频率再除以
  /// 当前档位 N）。
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  @override
  void dispose() {
    // ⚡ 功耗优化：被动回调无资源可释放；未执行的帧回调经 mounted 检查短路。
    super.dispose();
  }

  /// 当前生效采样档位：活动（滚动/切页）用活动档，否则静止档。
  int get _effectiveN => ref.read(scrollActivityProvider)
      ? widget.activeEveryNFrames
      : widget.everyNFrames;

  /// 每帧结束回调（由内容重绘驱动的帧触发）：递增计数，命中节流的帧
  /// setState 触发捕获节点重绘（采样）。**不主动调度下一帧** —— 下一帧
  /// 由页面内容自身驱动（滚动/动画），内容静止即无帧、心跳自然停止，
  /// 系统刷新率随之自适应下降。
  void _onFrame() {
    if (!mounted) return;
    _frame++;
    if (_frame % _effectiveN == 0) {
      // ⚡ 功耗优化：仅采样帧重建 CustomPaint（painter 换新实例 →
      //   shouldRepaint true → 捕获节点重绘）；非采样帧零 rebuild。
      setState(() {});
    }
    _scheduleNext(); // 重新注册：后续帧（若存在）继续检查。
  }

  void _scheduleNext() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _onFrame());
  }

  @override
  Widget build(BuildContext context) {
    // 活动态切换（滚动起止）本身触发 rebuild；painter 在非采样帧
    // shouldRepaint=false，不产生额外采样。
    ref.watch(scrollActivityProvider);
    return CustomPaint(
      // ⚡ 功耗优化：child 直接传入，心跳期间页面内容零 rebuild。
      painter: _HeartbeatPainter(_frame, _effectiveN),
      child: widget.child,
    );
  }
}

/// 透明心跳 painter：不绘制任何像素；`shouldRepaint` 仅在采样帧
/// （frame % everyNFrames == 0）返回 true，使 CustomPaint 所在的
/// RepaintBoundary（捕获节点）重新 paint。
class _HeartbeatPainter extends CustomPainter {
  _HeartbeatPainter(this.frame, this.everyNFrames);

  final int frame;
  final int everyNFrames;

  @override
  void paint(Canvas canvas, Size size) {
    // 透明：无任何绘制内容。
  }

  @override
  bool shouldRepaint(_HeartbeatPainter oldDelegate) =>
      frame % everyNFrames == 0;
}
