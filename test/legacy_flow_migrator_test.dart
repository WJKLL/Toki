// 迁移器单测:真实 next 内嵌结构 + 顶层 connections 兼容结构 + 泳道转 LaneNode。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/flow/legacy_flow_migrator.dart';
import 'package:xiangjugong/domain/entities/flow_doc.dart';

/// 真实旧格式样本:连线内嵌元素 next[](ConnectionParams),含泳道元素。
const String realLegacySample = '''
{
  "elements": [
    {"id":"s1","kind":0,"text":"开始","positionDx":80,"positionDy":300,
     "elementData":{"k":"start"}},
    {"id":"s2","kind":2,"text":"步骤 1","positionDx":380,"positionDy":290,
     "elementData":{"k":"step","n":1}},
    {"id":"s3","kind":4,"text":"有货?","positionDx":680,"positionDy":250,
     "elementData":{"k":"decision","n":2}},
    {"id":"s4","kind":2,"text":"下单","positionDx":980,"positionDy":120,
     "elementData":{"k":"step","n":3,"note":"加急","lock":true}},
    {"id":"s5","kind":2,"text":"放弃","positionDx":980,"positionDy":400,
     "elementData":{"k":"step","n":4,"c":true},
     "backgroundColor":4294927624},
    {"id":"s6","kind":1,"text":"结束","positionDx":1280,"positionDy":260,
     "elementData":{"k":"end"}},
    {"id":"lane1","kind":6,"text":"主流程","positionDx":40,"positionDy":40,
     "elementData":{"lane":true,"t":"主流程"}}
  ],
  "connections": []
}
''';

/// 顶层 connections 兼容样本(合成结构与 POC 一致)。
const String flatLegacySample = '''
{
  "elements": [
    {"id":"a1","text":"开始","positionDx":80,"positionDy":300,"elementData":{"k":"start"}},
    {"id":"a2","text":"比价","positionDx":380,"positionDy":290,"elementData":{"k":"step","n":1}},
    {"id":"a3","text":"有优惠?","positionDx":680,"positionDy":250,"elementData":{"k":"decision","n":2}},
    {"id":"a4","text":"下单","positionDx":980,"positionDy":120,"elementData":{"k":"step","n":3}},
    {"id":"a5","text":"结束","positionDx":1280,"positionDy":260,"elementData":{"k":"end"}}
  ],
  "connections": [
    {"src":"a1","dest":"a2","note":"","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}},
    {"src":"a2","dest":"a3","note":"","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}},
    {"src":"a3","dest":"a4","note":"是","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}},
    {"src":"a3","dest":"a5","note":"否","arrowParams":{"arrowHead":0,"autoColor":true,"thickness":1.7}}
  ]
}
''';

/// 真实结构样本的连线补丁(next 内嵌;真实旧文件连接不入顶层)。
const String _realConnsJson = '''
{"s1":[{"destElementId":"s2","note":"","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}}],
 "s2":[{"destElementId":"s3","note":"","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}}],
 "s3":[{"destElementId":"s4","note":"有","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}},
       {"destElementId":"s5","note":"无","arrowParams":{"arrowHead":1,"autoColor":false,"color":4294927624,"thickness":3.0}}],
 "s4":[{"destElementId":"s6","note":"","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}}],
 "s5":[{"destElementId":"s6","note":"","arrowParams":{"arrowHead":1,"autoColor":true,"thickness":1.7}}]}
''';

/// 把 next 注入真实样本(测试用)。
String _realWithNext() {
  final Map<String, dynamic> top = _decode(realLegacySample);
  final Map<String, dynamic> conns = _decode(_realConnsJson);
  final List<dynamic> elements = top['elements'] as List<dynamic>;
  for (final dynamic e in elements) {
    final String id = e['id'] as String;
    if (conns[id] != null) {
      e['next'] = conns[id];
    }
  }
  return _encode(top);
}

Map<String, dynamic> _decode(String s) =>
    (const JsonDecoder().convert(s)) as Map<String, dynamic>;
String _encode(Map<String, dynamic> m) => const JsonEncoder().convert(m);

void main() {
  group('迁移器:真实 next 内嵌结构', () {
    final FlowMigrateReport report = FlowMigrateReport();
    final FlowDoc doc = migrateLegacyFlowJson(_realWithNext(), report: report);

    test('节点:泳道转 LaneNode(默认尺寸/标题),其余保留(含锁/批注/自定义标记)', () {
      expect(doc.nodes.length, 7);
      expect(report.lanes, 1);
      final Map<String, FlowNodeData> byId = <String, FlowNodeData>{
        for (final FlowNodeData n in doc.nodes) n.id: n,
      };
      expect(byId['s1']!.kind, FlowNodeKind.start);
      expect(byId['s2']!.badge, 1);
      expect(byId['s3']!.kind, FlowNodeKind.decision);
      expect(byId['s4']!.locked, isTrue);
      expect(byId['s4']!.note, '加急');
      expect(byId['s5']!.customStyled, isTrue);
      expect(byId['s5']!.customColor, 4294927624);
      expect(byId['s6']!.kind, FlowNodeKind.end);
      // 泳道:kind=lane;标题取 text;默认尺寸 420×240;无连线端点参与。
      final FlowNodeData lane = byId['lane1']!;
      expect(lane.kind, FlowNodeKind.lane);
      expect(lane.title, '主流程');
      expect(lane.w, 420);
      expect(lane.h, 240);
      expect(doc.edges.any((FlowEdge e) => e.srcNodeId == 'lane1' ||
          e.dstNodeId == 'lane1'), isFalse);
    });

    test('泳道尺寸自定义时保留 size.*', () {
      // map 层注入:真实旧文件把尺寸存为 "size.width"/"size.height" 键。
      final Map<String, dynamic> top = _decode(_realWithNext());
      final List<dynamic> elements = top['elements'] as List<dynamic>;
      for (final dynamic re in elements) {
        final Map e = re as Map;
        if (e['id'] == 'lane1') {
          e['size.width'] = 600;
          e['size.height'] = 320;
        }
      }
      final FlowDoc d2 = migrateLegacyFlowJson(_encode(top));
      final FlowNodeData lane =
          d2.nodes.firstWhere((FlowNodeData n) => n.id == 'lane1');
      expect(lane.w, 600);
      expect(lane.h, 320);
    });

    test('连线:6 条;分支/样式/端口分配正确', () {
      expect(doc.edges.length, 6);
      // s3(判断)两条出线:o0→s4(有)、o1→s5(无)。
      final FlowEdge toS4 =
          doc.edges.firstWhere((FlowEdge e) => e.dstNodeId == 's4');
      final FlowEdge toS5 =
          doc.edges.firstWhere((FlowEdge e) => e.dstNodeId == 's5');
      expect(toS4.srcNodeId, 's3');
      expect(toS4.srcPortId, 'o0');
      expect(toS4.data.label, '有');
      expect(toS5.srcPortId, 'o1');
      expect(toS5.data.label, '无');
      // s5 自定义线:autoColor=false → 色保留;粗 3 → 保留;箭头 none。
      expect(toS5.data.color, 4294927624);
      expect(toS5.data.width, 3.0);
      expect(toS5.data.arrow, 1);
      final FlowEdge toS5FromS3 = toS5;
      expect(toS5FromS3.data.arrow, 1);
      // s4→s6 与 s5→s6:s6 入线序 i0/i1。
      final List<FlowEdge> toS6 = doc.edges
          .where((FlowEdge e) => e.dstNodeId == 's6')
          .toList()
        ..sort((FlowEdge a, FlowEdge b) => a.srcNodeId.compareTo(b.srcNodeId));
      expect(toS6[0].dstPortId, 'i0');
      expect(toS6[1].dstPortId, 'i1');
      // 默认色不落盘(主题默认)。
      expect(toS4.data.color, 0);
      expect(toS4.data.width, 0);
    });

    test('输出可被 FlowDoc 读回(version=2)', () {
      final FlowDoc back = FlowDoc.fromJson(doc.toJson());
      expect(back.nodes.length, doc.nodes.length);
      expect(back.edges.length, doc.edges.length);
    });
  });

  group('迁移器:顶层 connections 兼容结构', () {
    final FlowDoc doc = migrateLegacyFlowJson(flatLegacySample);
    test('5 节点 4 连线;判断分支 label=note;none 箭头保留', () {
      expect(doc.nodes.length, 5);
      expect(doc.edges.length, 4);
      final FlowEdge toA5 = doc.edges
          .firstWhere((FlowEdge e) => e.dstNodeId == 'a5');
      expect(toA5.data.label, '否');
      expect(toA5.data.arrow, 0); // arrowHead 0 = none
    });
  });

  test('空图迁移不崩', () {
    final FlowDoc doc = migrateLegacyFlowJson('{"elements":[],"connections":[]}');
    expect(doc.nodes, isEmpty);
    expect(doc.edges, isEmpty);
  });
}
