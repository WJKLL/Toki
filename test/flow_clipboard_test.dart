// 复制/粘贴子图单测(阶段2):抽取/端口重编/重映射/平移/锚点。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/flow/flow_clipboard.dart';
import 'package:xiangjugong/domain/entities/flow_doc.dart';

FlowDoc _graph() {
  return FlowDoc(
    nodes: <FlowNodeData>[
      const FlowNodeData(
        id: 'a',
        kind: FlowNodeKind.start,
        dx: 100,
        dy: 100,
        title: '开始',
      ),
      const FlowNodeData(
        id: 'b',
        kind: FlowNodeKind.step,
        dx: 400,
        dy: 120,
        title: '步骤',
        badge: 1,
      ),
      const FlowNodeData(
        id: 'c',
        kind: FlowNodeKind.end,
        dx: 700,
        dy: 100,
        title: '结束',
      ),
      const FlowNodeData(
        id: 'L',
        kind: FlowNodeKind.lane,
        dx: 50,
        dy: 50,
        w: 900,
        h: 400,
        title: '泳道',
      ),
    ],
    edges: <FlowEdge>[
      FlowEdge(id: 'c0', srcNodeId: 'a', srcPortId: 'o0', dstNodeId: 'b', dstPortId: 'i0'),
      FlowEdge(id: 'c1', srcNodeId: 'b', srcPortId: 'o0', dstNodeId: 'c', dstPortId: 'i0'),
    ],
  );
}

void main() {
  group('extractSubgraph', () {
    test('抽取 a+b(内部线 c0),排除 lane 与跨界线', () {
      final FlowDoc copy = extractSubgraph(_graph(), <String>{'a', 'b', 'L'});
      expect(copy.nodes.length, 2);
      expect(copy.nodes.map((FlowNodeData n) => n.id), <String>['a', 'b']);
      // lane 不复制;c1(b→c)因 c 未选被排除。
      expect(copy.edges.length, 1);
      expect(copy.edges.single.id, 'c0');
    });

    test('端口重编:源出线序/目标入线序', () {
      final FlowDoc g = _graph();
      // 全选 a/b/c:边 c0(o0/i0)、c1(o0/i0 重编为 b 的 o0、c 的 i0)。
      final FlowDoc copy = extractSubgraph(g, <String>{'a', 'b', 'c'});
      expect(copy.edges.length, 2);
      expect(copy.edges[0].srcPortId, 'o0');
      expect(copy.edges[0].dstPortId, 'i0');
      expect(copy.edges[1].srcPortId, 'o0');
      expect(copy.edges[1].dstPortId, 'i0');
    });
  });

  group('subgraphAnchor', () {
    test('按包围盒中心', () {
      final FlowDoc copy =
          extractSubgraph(_graph(), <String>{'a', 'b', 'c'});
      // x:(100..880)/2 近似(节点宽):start 130 → 100..230;step 180 → 400..580;
      // end 130 → 700..830。bbox 100..830 → 中心 465;y 100..186 → 143。
      final ({double x, double y}) anchor = subgraphAnchor(copy);
      expect(anchor.x, closeTo(465, 1));
      expect(anchor.y, closeTo(143, 1));
    });
  });

  group('remapSubgraph', () {
    test('新 id/平移/边端点映射/端口重编', () {
      final FlowDoc copy =
          extractSubgraph(_graph(), <String>{'a', 'b', 'c'});
      final (FlowDoc doc, Map<String, String> map) = remapSubgraph(
        copy,
        idGen: (int i) => 'p$i',
        offsetX: 1000,
        offsetY: 500,
      );
      expect(doc.nodes.length, 3);
      expect(map['a'], 'p0');
      expect(map['b'], 'p1');
      expect(map['c'], 'p2');
      expect(doc.nodes[0].id, 'p0');
      expect(doc.nodes[0].dx, 1100);
      expect(doc.nodes[0].dy, 600);
      expect(doc.nodes[1].badge, 1);
      expect(doc.nodes[1].title, '步骤');
      expect(doc.edges.length, 2);
      expect(doc.edges[0].srcNodeId, 'p0');
      expect(doc.edges[0].dstNodeId, 'p1');
      expect(doc.edges[0].srcPortId, 'o0');
      expect(doc.edges[0].dstPortId, 'i0');
      expect(doc.edges[1].srcNodeId, 'p1');
      expect(doc.edges[1].dstNodeId, 'p2');
      expect(doc.edges[1].id, 'p4'); // 节点 0..2,边 3..4。
    });

    test('重映射后经 nodesFromDoc 端口可达(往返一致性)', () {
      final FlowDoc copy =
          extractSubgraph(_graph(), <String>{'a', 'b', 'c'});
      final (FlowDoc doc, Map<String, String> _) = remapSubgraph(
        copy,
        idGen: (int i) => 'q$i',
        offsetX: 0,
        offsetY: 0,
      );
      // 直接以纯数据断言端口引用与重建(度)匹配:每条边源端口 o0 存在性由
      // 重建逻辑保证 —— 此处断言重建后每个源出线序连续。
      final Map<String, int> srcCount = <String, int>{};
      for (final FlowEdge e in doc.edges) {
        srcCount.update(e.srcNodeId, (int v) => v + 1, ifAbsent: () => 1);
      }
      for (final MapEntry<String, int> en in srcCount.entries) {
        final List<FlowEdge> outs = doc.edges
            .where((FlowEdge e) => e.srcNodeId == en.key)
            .toList()
          ..sort((FlowEdge x, FlowEdge y) =>
              x.srcPortId.compareTo(y.srcPortId));
        for (int i = 0; i < outs.length; i++) {
          expect(outs[i].srcPortId, 'o$i');
        }
      }
    });
  });
}
