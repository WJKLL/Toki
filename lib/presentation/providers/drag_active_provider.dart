// lib/presentation/providers/drag_active_provider.dart
// 编号:C-34 辅助件(v1.23.0,不占独立编号)
// 说明:卡片拖拽进行中标志 —— 拖拽激活 → true,松手落位 → false。
//   消费方:
//   1. 首页 ListView(拖拽中禁用滚动,防手势冲突);
//   2. combo/C-33 的分钟 Timer(拖拽中跳过本轮刷新,等效"暂停定时器",
//      无 Timer 生命周期管理,结束自动恢复)。
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 拖拽进行中(默认 false,静止零开销)。
final dragActiveProvider = NotifierProvider<DragActiveController, bool>(
  DragActiveController.new,
);

class DragActiveController extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() => state = true;

  void end() => state = false;
}
