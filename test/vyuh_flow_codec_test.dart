// P-11 v2 域 codec 单测:FlowDoc ↔ vyuh 图对象(端口分配/往返一致/样式回读)。
import 'dart:ui' show Color, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';
import 'package:xiangjugong/domain/entities/flow_doc.dart';
import 'package:xiangjugong/presentation/features/flow/vyuh_flow_codec.dart';

FlowDoc _sampleDoc() {
  return FlowDoc(
    nodes: <FlowNodeData>[
      const FlowNodeData(
        id: 'a1',
        kind: FlowNodeKind.start,
        dx: 80,
        dy: 300,
        title: '开始',
      ),
      const FlowNodeData(
        id: 'a4',
        kind: FlowNodeKind.decision,
        dx: 680,
        dy: 250,
        title: '有货?',
        badge: 2,
      ),
      const FlowNodeData(
        id: 'a5',
        kind: FlowNodeKind.step,
        dx: 980,
        dy: 120,
        title: '下单',
        badge: 3,
        locked: true,
      ),
      const FlowNodeData(
        id: 'a6',
        kind: FlowNodeKind.end,
        dx: 1280,
        dy: 250,
        title: '结束',
      ),
    ],
    edges: <FlowEdge>[
      FlowEdge(
        id: 'c0',
        srcNodeId: 'a1',
        srcPortId: 'o0',
        dstNodeId: 'a4',
        dstPortId: 'i0',
      ),
      FlowEdge(
        id: 'c1',
        srcNodeId: 'a4',
        srcPortId: 'o0',
        dstNodeId: 'a5',
        dstPortId: 'i0',
        data: const FlowEdgeData(label: '有'),
      ),
      FlowEdge(
        id: 'c2',
        srcNodeId: 'a4',
        srcPortId: 'o1',
        dstNodeId: 'a6',
        dstPortId: 'i0',
        data: const FlowEdgeData(label: '无', arrow: 0),
      ),
    ],
  );
}

void main() {
  group('nodesFromDoc', () {
    test('端口按出入度分配(iN/oN 均布),尺寸/锁映射', () {
      final List<Node<FlowNodeData>> nodes = nodesFromDoc(_sampleDoc());
      expect(nodes.length, 4);
      final Map<String, Node<FlowNodeData>> byId = <String, Node<FlowNodeData>>{
        for (final Node<FlowNodeData> n in nodes) n.id: n,
      };
      // a1 出 1 入 0 → 策略每侧至少 1:入 i0 + 出 o0,均 multi。
      expect(byId['a1']!.ports.length, 2);
      expect(
        byId['a1']!.ports.where((Port p) => p.type == PortType.output).length,
        1,
      );
      expect(byId['a1']!.ports.every((Port p) => p.multiConnections), isTrue);
      expect(byId['a1']!.size.value.width, 130);
      // a4(判断)入 1 出 2。
      final Node<FlowNodeData> a4 = byId['a4']!;
      expect(a4.ports.length, 3);
      expect(a4.ports.where((Port p) => p.type == PortType.output).length, 2);
      expect(
        a4.ports
            .where((Port p) => p.type == PortType.output)
            .map((Port p) => p.id),
        containsAll(<String>['o0', 'o1']),
      );
      expect(a4.size.value.width, 200);
      // 锁与端点端口存在。
      expect(byId['a5']!.locked, isTrue);
      for (final Connection<dynamic> c in edgesFromDoc(_sampleDoc())) {
        expect(byId[c.sourceNodeId]!.ports.any((Port p) => p.id == c.sourcePortId), isTrue);
        expect(byId[c.targetNodeId]!.ports.any((Port p) => p.id == c.targetPortId), isTrue);
      }
    });
  });

  group('样式回读与 meta 覆盖', () {
    test('connection 现态样式(color/width/label)回读进 doc', () {
      final FlowDoc src = _sampleDoc();
      final NodeFlowController<FlowNodeData, dynamic> ctrl =
          NodeFlowController<FlowNodeData, dynamic>(
        nodes: nodesFromDoc(src),
        connections: edgesFromDoc(src),
      );
      addTearDown(ctrl.dispose);
      final Connection<dynamic> c0 = ctrl.connections.first;
      c0.color = const Color(0xFF3482FF);
      c0.strokeWidth = 3.5;
      c0.label = ConnectionLabel(text: '已改分支');
      final FlowDoc back = docFromGraph(ctrl);
      final FlowEdge e0 = back.edges.first;
      expect(e0.data.color, 0xFF3482FF);
      expect(e0.data.width, 3.5);
      expect(e0.data.label, '已改分支');
      // 未设样式线保持默认(0)。
      expect(back.edges[1].data.color, 0);
      expect(back.edges[1].data.width, 0);
    });

    test('dataFor 覆盖业务字段(标题/锁)', () {
      final FlowDoc src = _sampleDoc();
      final NodeFlowController<FlowNodeData, dynamic> ctrl =
          NodeFlowController<FlowNodeData, dynamic>(
        nodes: nodesFromDoc(src),
        connections: edgesFromDoc(src),
      );
      addTearDown(ctrl.dispose);
      final FlowDoc back = docFromGraph(
        ctrl,
        dataFor: (String id) => id == 'a4'
            ? src.nodes[1].copyWith(title: '改名后', locked: true)
            : src.nodes.firstWhere((FlowNodeData n) => n.id == id),
      );
      final FlowNodeData a4 =
          back.nodes.firstWhere((FlowNodeData n) => n.id == 'a4');
      expect(a4.title, '改名后');
      expect(a4.locked, isTrue);
    });
  });

  group('往返一致', () {
    test('doc → graph → docFromGraph:结构/端点/样式一致', () {
      final FlowDoc src = _sampleDoc();
      final NodeFlowController<FlowNodeData, dynamic> ctrl =
          NodeFlowController<FlowNodeData, dynamic>(
        nodes: nodesFromDoc(src),
        connections: edgesFromDoc(src),
      );
      addTearDown(ctrl.dispose);
      final FlowDoc back = docFromGraph(ctrl);
      expect(back.nodes.length, src.nodes.length);
      expect(back.edges.length, src.edges.length);
      final Map<String, FlowNodeData> backNodes = <String, FlowNodeData>{
        for (final FlowNodeData n in back.nodes) n.id: n,
      };
      for (final FlowNodeData n in src.nodes) {
        expect(backNodes[n.id]!.kind, n.kind);
        expect(backNodes[n.id]!.dx, n.dx);
        expect(backNodes[n.id]!.dy, n.dy);
        expect(backNodes[n.id]!.title, n.title);
        expect(backNodes[n.id]!.badge, n.badge);
        expect(backNodes[n.id]!.locked, n.locked);
      }
      final Map<String, FlowEdge> backEdges = <String, FlowEdge>{
        for (final FlowEdge e in back.edges) e.id: e,
      };
      for (final FlowEdge e in src.edges) {
        expect(backEdges[e.id]!.srcNodeId, e.srcNodeId);
        expect(backEdges[e.id]!.srcPortId, e.srcPortId);
        expect(backEdges[e.id]!.dstNodeId, e.dstNodeId);
        expect(backEdges[e.id]!.dstPortId, e.dstPortId);
        expect(backEdges[e.id]!.data.label, e.data.label);
        expect(backEdges[e.id]!.data.arrow, e.data.arrow);
      }
      // 往返后端口分配稳定(重建端口 id 与导出一致)。
      final List<Node<FlowNodeData>> nodes2 = nodesFromDoc(back);
      final Map<String, Node<FlowNodeData>> byId2 = <String, Node<FlowNodeData>>{
        for (final Node<FlowNodeData> n in nodes2) n.id: n,
      };
      for (final FlowEdge e in back.edges) {
        expect(
          byId2[e.srcNodeId]!.ports.any((Port p) => p.id == e.srcPortId),
          isTrue,
        );
      }
    });
  });

  group('泳道 LaneNode(阶段2)', () {
    FlowDoc laneDoc() => FlowDoc(
          nodes: <FlowNodeData>[
            const FlowNodeData(
              id: 'L1',
              kind: FlowNodeKind.lane,
              dx: 40,
              dy: 40,
              w: 600,
              h: 300,
              title: '主流程',
            ),
            const FlowNodeData(
              id: 'a1',
              kind: FlowNodeKind.start,
              dx: 120,
              dy: 120,
              title: '开始',
            ),
            const FlowNodeData(
              id: 'a2',
              kind: FlowNodeKind.end,
              dx: 480,
              dy: 120,
              title: '结束',
            ),
          ],
          edges: <FlowEdge>[
            FlowEdge(
              id: 'c0',
              srcNodeId: 'a1',
              srcPortId: 'o0',
              dstNodeId: 'a2',
              dstPortId: 'i0',
            ),
          ],
        );

    test('lane → GroupNode(尺寸/标题/无端口/位置)', () {
      final List<Node<FlowNodeData>> nodes = nodesFromDoc(laneDoc());
      expect(nodes.length, 3);
      final Node<FlowNodeData> lane =
          nodes.firstWhere((Node<FlowNodeData> n) => n.id == 'L1');
      expect(lane, isA<GroupNode<FlowNodeData>>());
      expect(lane.size.value.width, 600);
      expect(lane.size.value.height, 300);
      expect(lane.position.value.dx, 40);
      expect(lane.ports, isEmpty);
      expect(lane.locked, isFalse);
      // 普通节点不受影响:常规 Node + 端口。
      final Node<FlowNodeData> a1 =
          nodes.firstWhere((Node<FlowNodeData> n) => n.id == 'a1');
      expect(a1, isNot(isA<GroupNode<FlowNodeData>>()));
      expect(a1.ports, isNotEmpty);
    });

    test('拉伸后尺寸回写 docFromGraph(lane 落盘 w/h)', () {
      final FlowDoc src = laneDoc();
      final NodeFlowController<FlowNodeData, dynamic> ctrl =
          NodeFlowController<FlowNodeData, dynamic>(
        nodes: nodesFromDoc(src),
        connections: edgesFromDoc(src),
      );
      addTearDown(ctrl.dispose);
      // 模拟拉伸:尺寸 600×300 → 760×380。
      final GroupNode<FlowNodeData> lane =
          ctrl.nodes['L1']! as GroupNode<FlowNodeData>;
      lane.setSize(const Size(760, 380));
      final FlowDoc back = docFromGraph(ctrl);
      final FlowNodeData laneData =
          back.nodes.firstWhere((FlowNodeData n) => n.id == 'L1');
      expect(laneData.w, 760);
      expect(laneData.h, 380);
      // 普通节点仍无 w/h。
      final FlowNodeData a1 =
          back.nodes.firstWhere((FlowNodeData n) => n.id == 'a1');
      expect(a1.w, isNull);
      // 往返后可重建同尺寸泳道。
      final List<Node<FlowNodeData>> nodes2 = nodesFromDoc(back);
      final Node<FlowNodeData> lane2 =
          nodes2.firstWhere((Node<FlowNodeData> n) => n.id == 'L1');
      expect(lane2.size.value.width, 760);
      expect(lane2.size.value.height, 380);
    });
  });
}
