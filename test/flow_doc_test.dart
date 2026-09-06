// FlowDoc 模型单测:JSON 往返/版本守卫/端口几何派生。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/domain/entities/flow_doc.dart';

void main() {
  group('FlowDoc 序列化', () {
    test('往返无损', () {
      final FlowDoc doc = FlowDoc(
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
            dx: 980,
            dy: 250,
            title: '有优惠?',
            badge: 3,
            note: '判断批注',
            locked: true,
          ),
          const FlowNodeData(
            id: 'a10',
            kind: FlowNodeKind.step,
            dx: 380,
            dy: 80,
            title: '检查库存',
            customStyled: true,
            customColor: 0xFF3482FF,
          ),
        ],
        edges: <FlowEdge>[
          FlowEdge(
            id: 'c0',
            srcNodeId: 'a1',
            srcPortId: 'o0',
            dstNodeId: 'a4',
            dstPortId: 'i0',
            data: const FlowEdgeData(label: '走判断', arrow: 1, width: 2),
          ),
        ],
      );
      final FlowDoc back = FlowDoc.fromJson(doc.toJson());
      expect(back.nodes.length, 3);
      expect(back.edges.length, 1);
      expect(back.nodes[0].id, 'a1');
      expect(back.nodes[0].kind, FlowNodeKind.start);
      expect(back.nodes[1].kind, FlowNodeKind.decision);
      expect(back.nodes[1].badge, 3);
      expect(back.nodes[1].note, '判断批注');
      expect(back.nodes[1].locked, isTrue);
      expect(back.nodes[2].customStyled, isTrue);
      expect(back.nodes[2].customColor, 0xFF3482FF);
      expect(back.edges[0].srcPortId, 'o0');
      expect(back.edges[0].dstPortId, 'i0');
      expect(back.edges[0].data.label, '走判断');
      expect(back.edges[0].data.width, 2);
    });

    test('版本守卫:非当前版本抛 FormatException', () {
      expect(
        () => FlowDoc.fromJson('{"v":1,"nodes":[],"edges":[]}'),
        throwsFormatException,
      );
      expect(
        () => FlowDoc.fromJson('not-json'),
        throwsFormatException,
      );
    });
  });

  group('尺寸派生', () {
    test('kind 语义尺寸', () {
      expect(FlowNodeData.widthOf(FlowNodeKind.start), 130);
      expect(FlowNodeData.heightOf(FlowNodeKind.step), 66);
      expect(FlowNodeData.widthOf(FlowNodeKind.decision), 200);
      expect(FlowNodeData.widthOf(FlowNodeKind.lane), 420);
      expect(FlowNodeData.heightOf(FlowNodeKind.lane), 240);
    });

    test('lane 尺寸覆盖(w/h)与 JSON 往返', () {
      const FlowNodeData lane = FlowNodeData(
        id: 'L1',
        kind: FlowNodeKind.lane,
        dx: 50,
        dy: 60,
        w: 640,
        h: 300,
        title: '仓储分区',
        locked: true,
      );
      expect(lane.width, 640);
      expect(lane.height, 300);
      final Map<String, dynamic> json =
          lane.toJson(); // jsonDecode 需 dart:convert;此处仅类型层面不可用。
      expect(json['k'], 'lane');
      expect(json['w'], 640);
      expect(json['h'], 300);
      // 非 lane 不写 w/h。
      const FlowNodeData step = FlowNodeData(
        id: 's1',
        kind: FlowNodeKind.step,
        dx: 0,
        dy: 0,
      );
      expect(step.toJson().containsKey('w'), isFalse);
      // 全文档往返。
      final FlowDoc doc = FlowDoc(
        nodes: <FlowNodeData>[lane, step],
        edges: const <FlowEdge>[],
      );
      final FlowDoc back = FlowDoc.fromJson(doc.toJson());
      expect(back.nodes[0].kind, FlowNodeKind.lane);
      expect(back.nodes[0].w, 640);
      expect(back.nodes[0].h, 300);
      expect(back.nodes[0].title, '仓储分区');
      expect(back.nodes[0].locked, isTrue);
      expect(back.nodes[1].w, isNull);
    });

    test('lane 非流程执行节点(isFlowStep=false)', () {
      expect(FlowNodeKind.step.isFlowStep, isTrue);
      expect(FlowNodeKind.lane.isFlowStep, isFalse);
      expect(FlowNodeKind.lane.defaultLabel(2), '泳道 2');
    });
  });
}
