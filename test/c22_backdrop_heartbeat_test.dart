// test/c22_backdrop_heartbeat_test.dart
// 验证 CaptureHeartbeat 的被动帧回调机制（v1.10.25 适配系统自适应刷新率）：
//   1. 静止不自我驱动帧：帧结束后不主动 scheduleFrame（对比旧实现
//      AnimationController.repeat 会持续调度帧，阻止系统降频）；
//   2. 采样节流：内容每 N 帧（everyNFrames）才重建 CustomPaint（采样），
//      非采样帧零 rebuild。
//
// 说明：TestWidgetsFlutterBinding.pump 仅在 hasScheduledFrame 为 true 时执行
// 帧，因此"内容驱动帧"需先显式 scheduleFrame 再 pump（模拟滚动/动画）。
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xiangjugong/presentation/widgets/c22_backdrop_heartbeat.dart';

void main() {
  // v1.18.x+:CaptureHeartbeat 为 Consumer(v1.18 活动档位依赖
  // scrollActivityProvider),harness 需包 ProviderScope。
  Widget harness({int everyNFrames = 3}) {
    return ProviderScope(
      child: CaptureHeartbeat(
        everyNFrames: everyNFrames,
        child: const SizedBox(width: 100, height: 100),
      ),
    );
  }

  int painterFrame(WidgetTester tester) {
    final CustomPaint cp = tester.widget<CustomPaint>(find.byType(CustomPaint));
    return (cp.painter! as dynamic).frame as int;
  }

  bool hasScheduledFrame() => SchedulerBinding.instance.hasScheduledFrame;

  /// 模拟一帧"内容驱动的帧"（滚动/动画）：显式调度后 pump。
  Future<void> pumpContentFrame(WidgetTester tester) async {
    SchedulerBinding.instance.scheduleFrame();
    await tester.pump();
  }

  testWidgets('静止时不自我驱动帧（无持续 Ticker → 系统可降频）', (tester) async {
    await tester.pumpWidget(harness());
    // 首帧结束：回调已执行（非采样帧），但未主动调度下一帧。
    expect(hasScheduledFrame(), isFalse, reason: '首帧后不应主动请求下一帧');

    // 非采样内容帧（_frame 2）：结束后无残留帧请求。
    await pumpContentFrame(tester);
    expect(hasScheduledFrame(), isFalse, reason: '非采样内容帧结束后不应自我驱动帧');

    // 采样帧（_frame 3 → setState）：调度一次重建帧 —— 必要的一次性行为。
    await pumpContentFrame(tester);
    expect(hasScheduledFrame(), isTrue, reason: '采样帧应调度一次重建帧');
    // 重建帧完成后（_frame 4）：不再有残留调度 —— 无持续自我驱动。
    await pumpContentFrame(tester);
    expect(hasScheduledFrame(), isFalse, reason: '重建完成后不应继续自我驱动帧');
  });

  testWidgets('采样帧后仅调度一次重建帧，重建完成后即停', (tester) async {
    await tester.pumpWidget(harness()); // 首帧末 _frame = 1
    await pumpContentFrame(tester); // _frame = 2
    await pumpContentFrame(tester); // _frame = 3 → setState → 调度重建帧
    expect(hasScheduledFrame(), isTrue, reason: '采样帧应调度一次重建帧');
    await pumpContentFrame(tester); // 重建帧：painter 更新；帧末 _frame = 4
    expect(hasScheduledFrame(), isFalse, reason: '重建完成后不应继续自我驱动');
  });

  testWidgets('采样节流：painter 仅在 N 的倍数帧重建（frame 0→3→6）', (tester) async {
    await tester.pumpWidget(harness(everyNFrames: 3));
    expect(painterFrame(tester), 0, reason: '初始 painter frame = 0');

    await pumpContentFrame(tester); // _frame 1：非采样帧，不重建
    expect(painterFrame(tester), 0, reason: '帧 1 不应重建（1 % 3 != 0）');
    await pumpContentFrame(tester); // _frame 2：非采样帧
    expect(painterFrame(tester), 0, reason: '帧 2 不应重建（2 % 3 != 0）');
    await pumpContentFrame(tester); // _frame 3 → setState
    await pumpContentFrame(tester); // 重建帧：painter frame = 3
    expect(painterFrame(tester), 3, reason: '帧 3 应重建为 frame 3');

    await pumpContentFrame(tester); // _frame 4
    await pumpContentFrame(tester); // _frame 5
    await pumpContentFrame(tester); // _frame 6 → setState
    await pumpContentFrame(tester); // 重建帧：painter frame = 6
    expect(painterFrame(tester), 6, reason: '帧 6 应重建为 frame 6');
  });
}
