// lib/core/flow/legacy_flow_migrator.dart
// 编号:P-11 旧数据迁移器(v1.46 阶段1 / v1.47 阶段2 泳道转 LaneNode)
// 职责:把 flutter_flow_chart Dashboard JSON(旧落盘格式)无损迁移为
//   FlowDoc(vyuh 内核格式,version=2)。幂等:输出只增不改旧文件,
//   由调用方决定何时写回。
// 说明:
//   - 元素:elementData 真实键 {'k': kind名, 'n': 序号, 'lock', 'note',
//     'c': 自定义样式标记};泳道元素 elementData['lane']==true → 转
//     LaneNode(阶段2;kind=lane,标题取 text/t,尺寸取 size.* 或默认,
//     不进连线端点集 —— 旧数据泳道不承载连线);
//   - 连线:真实旧文件内嵌于元素 next[](ConnectionParams:
//     {destElementId, arrowParams{arrowHead/color/autoColor/thickness}, note});
//     兼容「顶层 connections」表达(合成样本/测试用,src/dest 直连);
//   - 端口分配:源侧出线序 → oN,目标侧入线序 → iN(vyuh 端口 id);
//   - 分支名:旧数据连线无独立字段,note 即分支标签(批注域);
//     label=note,新模型 note 留空(旧数据无法区分两者);
//   - 线样式:arrowHead(0 none/1 single/2 both,对齐旧 ArrowHead);
//     autoColor=false 才保留自定义 color;thickness≈1.7 视为默认(0)。
import 'dart:convert' show jsonDecode;

import '../../domain/entities/flow_doc.dart';

/// 迁移结果统计(泳道转 LaneNode 计数)。
class FlowMigrateReport {
  FlowMigrateReport({this.lanes = 0});

  /// 迁移出的泳道(LaneNode)数。
  int lanes;
}

/// 把旧格式 JSON 文本迁移为 [FlowDoc]。
/// [raw] 顶层:{elements: [...], dashboardSizeWidth/Height, ...} 或合成样本。
FlowDoc migrateLegacyFlowJson(String raw, {FlowMigrateReport? report}) {
  final FlowMigrateReport rep = report ?? FlowMigrateReport();
  final Map<String, dynamic> top = jsonDecode(raw) as Map<String, dynamic>;
  final List<dynamic> rawElements = top['elements'] as List<dynamic>? ?? const [];

  // ── 收集连线(两种表达统一为 (src, dst, note, arrowParams) 列表)──
  final List<Map<String, dynamic>> rawConns = <Map<String, dynamic>>[];
  if (top['connections'] is List<dynamic>) {
    // 兼容:顶层直连表达(合成样本/测试)。
    for (final dynamic c in top['connections'] as List<dynamic>) {
      rawConns.add(Map<String, dynamic>.from(c as Map));
    }
  }
  for (final dynamic re in rawElements) {
    final Map<String, dynamic> e = Map<String, dynamic>.from(re as Map);
    final List<dynamic>? next = e['next'] as List<dynamic>?;
    if (next == null) continue;
    for (final dynamic n in next) {
      final Map<String, dynamic> conn = Map<String, dynamic>.from(n as Map);
      rawConns.add(<String, dynamic>{
        'src': e['id'],
        'dest': conn['destElementId'],
        'note': conn['note'] ?? '',
        'arrowParams': conn['arrowParams'],
      });
    }
  }

  // ── 出入度统计(端口分配)──
  final Map<String, List<int>> outOrder = <String, List<int>>{};
  final Map<String, int> inCount = <String, int>{};
  for (int i = 0; i < rawConns.length; i++) {
    outOrder.putIfAbsent(rawConns[i]['src'] as String, () => <int>[]).add(i);
    inCount.update(
      rawConns[i]['dest'] as String,
      (int v) => v + 1,
      ifAbsent: () => 1,
    );
  }

  // ── 节点 ──
  final List<FlowNodeData> nodes = <FlowNodeData>[];
  final Set<String> nodeIds = <String>{};
  for (final dynamic re in rawElements) {
    final Map<String, dynamic> e = Map<String, dynamic>.from(re as Map);
    final String id = e['id'] as String;
    final Object? ed = e['elementData'];
    final Map<String, dynamic> data = ed is Map
        ? Map<String, dynamic>.from(ed)
        : <String, dynamic>{};
    if (data['lane'] == true) {
      // 泳道 → LaneNode(阶段2):不进连线端点集(lane 不承载连线),
      // 标题 text/t 兜底,尺寸 size.* 或默认。
      rep.lanes++;
      final double lw = (e['size.width'] as num?)?.toDouble() ??
          FlowNodeData.widthOf(FlowNodeKind.lane);
      final double lh = (e['size.height'] as num?)?.toDouble() ??
          FlowNodeData.heightOf(FlowNodeKind.lane);
      nodes.add(
        FlowNodeData(
          id: id,
          kind: FlowNodeKind.lane,
          dx: (e['positionDx'] as num?)?.toDouble() ?? 0,
          dy: (e['positionDy'] as num?)?.toDouble() ?? 0,
          w: lw,
          h: lh,
          title: (e['text'] as String?)?.isNotEmpty == true
              ? e['text'] as String
              : (data['t'] as String? ?? ''),
          locked: data['lock'] == true,
        ),
      );
      continue;
    }
    final FlowNodeKind kind =
        FlowNodeKind.parse(data['k'] as String? ?? 'step');
    final bool customStyled = data['c'] == true;
    final int customColor = customStyled
        ? ((e['backgroundColor'] as num?)?.toInt() ?? 0)
        : 0;
    nodeIds.add(id);
    nodes.add(
      FlowNodeData(
        id: id,
        kind: kind,
        dx: (e['positionDx'] as num?)?.toDouble() ?? 0,
        dy: (e['positionDy'] as num?)?.toDouble() ?? 0,
        title: e['text'] as String? ?? '',
        note: data['note'] as String? ?? '',
        locked: data['lock'] == true,
        badge: (data['n'] as num?)?.toInt() ?? 0,
        customStyled: customStyled,
        customColor: customColor,
      ),
    );
  }

  // ── 连线(源出线序/目标入线序 → 端口)──
  final List<FlowEdge> edges = <FlowEdge>[];
  final Map<String, int> destSeen = <String, int>{};
  for (int i = 0; i < rawConns.length; i++) {
    final Map<String, dynamic> c = rawConns[i];
    final String src = c['src'] as String;
    final String dest = c['dest'] as String;
    if (!nodeIds.contains(src) || !nodeIds.contains(dest)) continue;
    final int srcOut = outOrder[src]!.indexOf(i);
    final int destIn =
        destSeen.update(dest, (int v) => v + 1, ifAbsent: () => 0);

    // 样式:autoColor=false 才保留自定义色;默认粗 1.7 → 0。
    int arrow = 1;
    int color = 0;
    double width = 0;
    final Object? apRaw = c['arrowParams'];
    if (apRaw is Map) {
      final Map<String, dynamic> ap = Map<String, dynamic>.from(apRaw);
      arrow = (ap['arrowHead'] as num?)?.toInt() ?? 1;
      if (ap['autoColor'] == false) {
        color = (ap['color'] as num?)?.toInt() ?? 0;
      }
      final double t = (ap['thickness'] as num?)?.toDouble() ?? 1.7;
      if ((t - 1.7).abs() > 0.01) width = t;
    }
    final String note = c['note'] as String? ?? '';
    edges.add(
      FlowEdge(
        id: 'c$i',
        srcNodeId: src,
        srcPortId: 'o$srcOut',
        dstNodeId: dest,
        dstPortId: 'i$destIn',
        data: FlowEdgeData(
          label: note, // 旧数据 note 即分支标签(见文件头说明)。
          note: '',
          arrow: arrow,
          color: color,
          width: width,
        ),
      ),
    );
  }

  return FlowDoc(nodes: nodes, edges: edges);
}
