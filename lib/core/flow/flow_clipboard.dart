// lib/core/flow/flow_clipboard.dart
// 编号:P-11 复制/粘贴子图工具(v1.47 阶段2)
// 说明:纯逻辑(无 Flutter/vyuh 依赖),可单测。
//   - 抽取:选中集合内节点(lane 容器不复制——子节点归属语义无法随行,
//     拖动/分区需用户重建)与两端均在集合内的连线;
//   - 端口重编:抽取/重映射都按「源出线序 oN / 目标入线序 iN」重新分配,
//     与保存-重载(migrator/codec)语义一致 —— 避免引用旧端口号失效;
//   - 重映射:新 id + 平移(粘贴落点)。
library;

import '../../domain/entities/flow_doc.dart';

/// 节点是否可复制(lane 容器不参与复制)。
bool isCopyable(FlowNodeData d) => d.kind != FlowNodeKind.lane;

/// 从全图抽取选中子图(保留 doc 内节点/连线顺序)。
FlowDoc extractSubgraph(FlowDoc doc, Set<String> selectedIds) {
  final Set<String> ids = <String>{
    for (final FlowNodeData n in doc.nodes)
      if (selectedIds.contains(n.id) && isCopyable(n)) n.id,
  };
  final List<FlowNodeData> nodes = <FlowNodeData>[
    for (final FlowNodeData n in doc.nodes)
      if (ids.contains(n.id)) n,
  ];
  final List<FlowEdge> edges = _reindex(
    <FlowEdge>[
      for (final FlowEdge e in doc.edges)
        if (ids.contains(e.srcNodeId) && ids.contains(e.dstNodeId)) e,
    ],
    <String, int>{},
    <String, int>{},
  );
  return FlowDoc(nodes: nodes, edges: edges);
}

/// 子图边界中心(粘贴对齐锚点;空图返回 0,0)。
({double x, double y}) subgraphAnchor(FlowDoc clip) {
  if (clip.nodes.isEmpty) return (x: 0, y: 0);
  double minX = double.infinity, minY = double.infinity;
  double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final FlowNodeData n in clip.nodes) {
    minX = n.dx < minX ? n.dx : minX;
    minY = n.dy < minY ? n.dy : minY;
    final double right = n.dx + n.width;
    final double bottom = n.dy + n.height;
    maxX = right > maxX ? right : maxX;
    maxY = bottom > maxY ? bottom : maxY;
  }
  return (x: (minX + maxX) / 2, y: (minY + maxY) / 2);
}

/// 重映射:新 id(按原顺序 idGen(i))+ 平移(offsetX/Y 加到节点坐标),
/// 连线端点随映射更新并重编端口。
/// [idGen]:0 起返回全局唯一 id(页面按时间戳+序号生成)。
(FlowDoc, Map<String, String>) remapSubgraph(
  FlowDoc clip, {
  required String Function(int index) idGen,
  required double offsetX,
  required double offsetY,
}) {
  final Map<String, String> map = <String, String>{};
  final List<FlowNodeData> nodes = <FlowNodeData>[];
  for (int i = 0; i < clip.nodes.length; i++) {
    final FlowNodeData n = clip.nodes[i];
    final String newId = idGen(i);
    map[n.id] = newId;
    nodes.add(
      FlowNodeData(
        id: newId,
        kind: n.kind,
        dx: n.dx + offsetX,
        dy: n.dy + offsetY,
        w: n.w,
        h: n.h,
        title: n.title,
        note: n.note,
        locked: n.locked,
        badge: n.badge,
        customStyled: n.customStyled,
        customColor: n.customColor,
      ),
    );
  }
  final List<FlowEdge> edges = _reindex(
    <FlowEdge>[
      for (int j = 0; j < clip.edges.length; j++)
        FlowEdge(
          id: idGen(nodes.length + j), // 节点 0..N-1,边 N..N+M-1。
          srcNodeId: map[clip.edges[j].srcNodeId] ?? clip.edges[j].srcNodeId,
          dstNodeId: map[clip.edges[j].dstNodeId] ?? clip.edges[j].dstNodeId,
          srcPortId: clip.edges[j].srcPortId,
          dstPortId: clip.edges[j].dstPortId,
          data: clip.edges[j].data,
        ),
    ],
    <String, int>{},
    <String, int>{},
  );
  return (FlowDoc(nodes: nodes, edges: edges), map);
}

/// 按源出线序 / 目标入线序重编端口 id(与迁移器/加载语义一致)。
List<FlowEdge> _reindex(
  List<FlowEdge> edges,
  Map<String, int> srcSeen,
  Map<String, int> dstSeen,
) {
  return <FlowEdge>[
    for (final FlowEdge e in edges)
      FlowEdge(
        id: e.id,
        srcNodeId: e.srcNodeId,
        srcPortId: 'o${srcSeen.update(e.srcNodeId, (int v) => v + 1, ifAbsent: () => 0)}',
        dstNodeId: e.dstNodeId,
        dstPortId: 'i${dstSeen.update(e.dstNodeId, (int v) => v + 1, ifAbsent: () => 0)}',
        data: e.data,
      ),
  ];
}
