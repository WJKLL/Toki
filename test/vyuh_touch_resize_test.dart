// 触摸 resize 实证测试(阶段2 fix 泳道缩放):两条触摸路径
// 1) 库 ResizerWidget 把手(选中态,非模式)—— 触摸全局路由(v0.4.0);
// 2) 宿主 overlay 大把手(尺寸编辑模式,VyuhFlowEditor resizeTargetId)。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';
import 'package:xiangjugong/domain/entities/flow_doc.dart';
import 'package:xiangjugong/presentation/features/flow/vyuh_flow_editor.dart';

NodeFlowController<String, dynamic> _makeCtrl() {
  return NodeFlowController<String, dynamic>(
    nodes: <Node<String>>[
      GroupNode<String>(
        id: 'g1',
        position: const Offset(60, 60),
        size: const Size(420, 240),
        title: '泳道',
        data: 'lane',
      ),
    ],
  );
}

NodeFlowController<FlowNodeData, dynamic> _makeFlowCtrl() {
  return NodeFlowController<FlowNodeData, dynamic>(
    nodes: <Node<FlowNodeData>>[
      GroupNode<FlowNodeData>(
        id: 'g1',
        position: const Offset(60, 60),
        size: const Size(420, 240),
        title: '泳道',
        data: const FlowNodeData(
          id: 'g1',
          kind: FlowNodeKind.lane,
          dx: 60,
          dy: 60,
          w: 420,
          h: 240,
          title: '泳道',
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('库把手(选中态):触摸拖右下把手可改变 GroupNode 尺寸',
      (WidgetTester tester) async {
    final NodeFlowController<String, dynamic> ctrl = _makeCtrl();
    addTearDown(ctrl.dispose);
    ctrl.selectNode('g1'); // 非模式:选中才显把手。

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeFlowEditor<String, dynamic>(
            controller: ctrl,
            theme: NodeFlowTheme.light,
            nodeBuilder: (BuildContext context, Node<String> node) =>
                const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();

    final double before = ctrl.nodes['g1']!.size.value.width;
    // 右下角 node(60,60)+(420,240) → (480,300);库把手命中 ~16px。
    final TestGesture g = await tester.startGesture(const Offset(483, 303));
    await tester.pump(const Duration(milliseconds: 40));
    await g.moveBy(const Offset(60, 40));
    await tester.pump(const Duration(milliseconds: 40));
    await g.up();
    await tester.pump(const Duration(milliseconds: 40));

    final double after = ctrl.nodes['g1']!.size.value.width;
    expect(after, greaterThan(before),
        reason: '库把手触摸拖动应增大宽度(前 $before → 后 $after)');
  });

  testWidgets('overlay 大把手(尺寸模式):触摸拖动改变 GroupNode 尺寸',
      (WidgetTester tester) async {
    final NodeFlowController<FlowNodeData, dynamic> ctrl = _makeFlowCtrl();
    addTearDown(ctrl.dispose);
    ctrl.setResizeOnlyNode('g1'); // 尺寸编辑模式。

    await tester.pumpWidget(
      MaterialApp(
        home: MiuixTheme(
          data: MiuixThemeData.light(),
          child: Scaffold(
            body: VyuhFlowEditor(
              controller: ctrl,
              resizeTargetId: 'g1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // overlay 右下角把手中心 = viewport.toScreen(node pos+size) = (480,300)。
    final double before = ctrl.nodes['g1']!.size.value.width;
    final TestGesture g =
        await tester.startGesture(const Offset(480, 300));
    await tester.pump(const Duration(milliseconds: 40));
    await g.moveBy(const Offset(70, 50));
    await tester.pump(const Duration(milliseconds: 40));
    await g.up();
    await tester.pump(const Duration(milliseconds: 40));

    final double after = ctrl.nodes['g1']!.size.value.width;
    expect(after, greaterThan(before),
        reason: 'overlay 把手触摸拖动应增大宽度(前 $before → 后 $after)');
  });
}
