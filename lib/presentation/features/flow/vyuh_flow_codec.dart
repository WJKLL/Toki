// lib/presentation/features/flow/vyuh_flow_codec.dart
// 编号:P-11 v2 域(vyuh_node_flow 内核)—— FlowDoc ↔ vyuh 图对象编解码
// 说明:
//   - nodesFromDoc/edgesFromDoc:文档 → controller 构造数据(端口按出入度
//     自动分配:源侧出线序 oN / 目标侧入线序 iN,右侧/左侧均布;序号规则
//     与 legacy_flow_migrator 一致,保证旧数据与文档往返端口号稳定);
//   - 泳道(kind=lane)→ GroupNode(空间包含行为:拖入/拖出自动归属、可
//     拉伸、随泳道拖动整体移动;无端口不承载连线;自绘见 node_card);
//   - docFromGraph:controller 现态 → 文档(导出;连线样式/批注等业务字段
//     由后续样式层同步至 Connection 属性与 data,此处保留默认;泳道尺寸
//     由现态回写 w/h);
//   - 纯逻辑,不依赖 Flutter widget,可单测。
import 'dart:ui' show Color, Offset, Size;

import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../domain/entities/flow_doc.dart';

/// 由 [FlowDoc] 构建 vyuh 节点列表(保持 doc.edges 顺序 → 端口号稳定)。
/// [widgetBuilder] 可空:null 时用库默认内容(纯逻辑/测试);业务组装
/// (VyuhFlowEditor)传自渲染卡;[laneBuilder] 供泳道(GroupNode)自绘,
/// 缺省时 GroupNode 用库默认群组样式。
List<Node<FlowNodeData>> nodesFromDoc(
  FlowDoc doc, {
  NodeWidgetBuilder<FlowNodeData>? widgetBuilder,
  NodeWidgetBuilder<FlowNodeData>? laneBuilder,
}) {
  // 出入度统计。
  final Map<String, int> inCount = <String, int>{};
  for (final FlowEdge e in doc.edges) {
    inCount.update(e.dstNodeId, (int v) => v + 1, ifAbsent: () => 1);
  }

  final List<Node<FlowNodeData>> nodes = <Node<FlowNodeData>>[];
  for (final FlowNodeData d in doc.nodes) {
    if (d.kind == FlowNodeKind.lane) {
      // 泳道:空间包含组(成员随泳道拖动;节点拖出即脱离;可拉伸)。
      nodes.add(
        GroupNode<FlowNodeData>(
          id: d.id,
          position: Offset(d.dx, d.dy),
          size: Size(d.width, d.height),
          title: d.title,
          data: d,
          color: Color(d.customStyled && d.customColor != 0
              ? d.customColor
              : 0xFF5B83C8),
          locked: d.locked,
          widgetBuilder: laneBuilder,
        ),
      );
      continue;
    }
    // 端口策略(3b-1 定):每侧至少 1 个端口(起点/终点也可被连,与旧编辑器
    // "任意连线"语义一致);multiConnections=true —— 运行时新拉线总可追加
    // (旧内核 non-multi 对已占源端口做"替换",会误删旧线);多条线共享
    // 端口时起点汇聚(可接受;保存-重载按线数展开独立端口)。
    final int inDeg = inCount[d.id] ?? 0;
    final int outDeg =
        doc.edges.where((FlowEdge e) => e.srcNodeId == d.id).length;
    final int ins = inDeg < 1 ? 1 : inDeg;
    final int outs = outDeg < 1 ? 1 : outDeg;
    final List<Port> inPorts = <Port>[
      for (int j = 0; j < ins; j++)
        Port(
          id: 'i$j',
          name: 'in',
          type: PortType.input,
          position: PortPosition.left,
          offset: Offset(0, _spread(ins, j)),
          multiConnections: true,
        ),
    ];
    final List<Port> outPorts = <Port>[
      for (int j = 0; j < outs; j++)
        Port(
          id: 'o$j',
          name: 'out',
          type: PortType.output,
          position: PortPosition.right,
          offset: Offset(0, _spread(outs, j)),
          multiConnections: true,
        ),
    ];
    nodes.add(
      Node<FlowNodeData>(
        id: d.id,
        type: d.kind.name,
        position: Offset(d.dx, d.dy),
        size: Size(FlowNodeData.widthOf(d.kind), FlowNodeData.heightOf(d.kind)),
        ports: <Port>[...inPorts, ...outPorts],
        locked: d.locked,
        widgetBuilder: widgetBuilder,
        data: d,
      ),
    );
  }
  return nodes;
}

/// 由 [FlowDoc] 构建 vyuh 连线列表(顺序即 doc.edges 顺序),并把文档样式
/// 同步到连线现态(color/strokeWidth/label —— 渲染与保存所见即所存)。
List<Connection<dynamic>> edgesFromDoc(FlowDoc doc) {
  final List<Connection<dynamic>> out = <Connection<dynamic>>[];
  for (final FlowEdge e in doc.edges) {
    final Connection<dynamic> c = Connection<dynamic>(
      id: e.id,
      sourceNodeId: e.srcNodeId,
      sourcePortId: e.srcPortId,
      targetNodeId: e.dstNodeId,
      targetPortId: e.dstPortId,
      data: e.data,
    );
    _applyEdgeVisuals(c, e.data);
    out.add(c);
  }
  return out;
}

/// 文档样式 → 连线现态(0=默认不设;label 空不设;箭头映射端点)。
void _applyEdgeVisuals(Connection<dynamic> c, FlowEdgeData d) {
  if (d.color != 0) c.color = Color(d.color);
  if (d.width != 0) c.strokeWidth = d.width;
  if (d.label.isNotEmpty) c.label = ConnectionLabel(text: d.label);
  applyEdgeArrow(c, d.arrow);
}

/// 箭头三态 → 连线端点(1 single 用主题默认端点,0/2 显式覆盖)。
void applyEdgeArrow(Connection<dynamic> c, int arrow) {
  const ConnectionEndPoint tri = ConnectionEndPoint(
    shape: MarkerShapes.triangle,
    size: Size(12, 12),
  );
  if (arrow == 0) {
    c.startPoint = ConnectionEndPoint.none;
    c.endPoint = ConnectionEndPoint.none;
  } else if (arrow == 2) {
    c.startPoint = tri;
    c.endPoint = tri;
  } else {
    // single:端点恢复主题默认(null = 跟随主题)。
    c.startPoint = null;
    c.endPoint = null;
  }
}

/// 连线现态端点 → 箭头语义(导出)。
/// 端点语义:null = 主题默认(单箭头);ConnectionEndPoint.none = 显式无箭头;
/// 三角端点 = 显式有箭头。
int arrowFromEndpoints(Connection<dynamic> c) {
  bool nonNone(Object? p) => p != null && !identical(p, ConnectionEndPoint.none);
  final bool s = nonNone(c.startPoint);
  final bool e = nonNone(c.endPoint);
  if (s && e) return 2; // 双向。
  if (s || e) return 1; // 单向。
  final bool anyNone = identical(c.startPoint, ConnectionEndPoint.none) ||
      identical(c.endPoint, ConnectionEndPoint.none);
  return anyNone ? 0 : 1; // none 显式无箭头;两端 null 走主题默认单箭头。
}

/// 控制器现态 → [FlowDoc](导出;保持 controller 顺序)。
/// [dataFor]:可选外部数据覆盖(页面 meta:改名/批注/锁/样式色等业务字段,
///   id → FlowNodeData;null 时用 node.data);连线业务字段从 connection
///   现态回读(color/strokeWidth/label),note/arrow 沿用 data 旧值;
///   泳道尺寸由现态回写 w/h(拉伸结果落盘)。
FlowDoc docFromGraph(
  NodeFlowController<FlowNodeData, dynamic> ctrl, {
  FlowNodeData Function(String id)? dataFor,
}) {
  final List<FlowNodeData> nodes = <FlowNodeData>[];
  for (final Node<FlowNodeData> n in ctrl.nodes.values) {
    final FlowNodeData d = dataFor?.call(n.id) ?? n.data;
    nodes.add(
      d.kind == FlowNodeKind.lane
          ? d.copyWith(
              dx: n.position.value.dx,
              dy: n.position.value.dy,
              w: n.size.value.width,
              h: n.size.value.height,
            )
          : d.copyWith(
              dx: n.position.value.dx,
              dy: n.position.value.dy,
            ),
    );
  }
  final List<FlowEdge> edges = <FlowEdge>[];
  for (final Connection<dynamic> c in ctrl.connections) {
    final FlowEdgeData old = c.data is FlowEdgeData
        ? c.data as FlowEdgeData
        : const FlowEdgeData();
    final String label = c.label?.text ?? old.label;
    edges.add(
      FlowEdge(
        id: c.id,
        srcNodeId: c.sourceNodeId,
        srcPortId: c.sourcePortId,
        dstNodeId: c.targetNodeId,
        dstPortId: c.targetPortId,
        data: FlowEdgeData(
          label: label,
          note: old.note,
          arrow: arrowFromEndpoints(c),
          color: c.color?.toARGB32() ?? 0,
          width: c.strokeWidth ?? 0,
        ),
      ),
    );
  }
  return FlowDoc(nodes: nodes, edges: edges);
}

/// 同侧端口均布偏移(与迁移器同规则)。
double _spread(int count, int index) {
  if (count <= 1) return 0;
  return (index - (count - 1) / 2) * 24;
}
