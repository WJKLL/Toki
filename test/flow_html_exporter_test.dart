// test/flow_html_exporter_test.dart
// v1.44.0 批D：HTML 可播放文件导出器单测（纯 JSON 输入,无 Flutter 依赖）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/export/flow_html_exporter.dart';

void main() {
  const FlowHtmlExporter exporter = FlowHtmlExporter();

  Map<String, dynamic> el({
    required String id,
    required double x,
    required double y,
    String kind = 'step',
    String? text,
    String? note,
    bool lane = false,
    bool custom = false,
    int? bg,
    int? border,
    int? fg,
    List<Map<String, dynamic>>? next,
  }) {
    return <String, dynamic>{
      'positionDx': x,
      'positionDy': y,
      'size.width': 176,
      'size.height': 56,
      'text': text ?? id,
      'textSize': 14,
      'textIsBold': false,
      'id': id,
      'elementData': <String, dynamic>{
        'k': kind,
        'note': ?note,
        if (lane) 'lane': true,
        if (custom) 'c': true,
      },
      'backgroundColor': bg ?? 0xFFFFFFFF,
      'borderColor': border ?? 0xFFB9BEC7,
      'textColor': fg ?? 0xFF000000,
      'next': next ?? <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> conn(
    String destId, {
    String note = '',
  }) {
    return <String, dynamic>{
      'destElementId': destId,
      'arrowParams': <String, dynamic>{
        'thickness': 1.7,
        'headRadius': 6,
        'color': 0xFF4A4A4A,
        'autoColor': true,
      },
      'note': note,
    };
  }

  String dashboardJson(List<Map<String, dynamic>> els) {
    return jsonEncode(<String, dynamic>{
      'elements': els,
      'dashboardSizeWidth': 800,
      'dashboardSizeHeight': 600,
      'gridBackgroundParams': <String, dynamic>{'visible': true},
    });
  }

  test('空图导出基础 HTML 结构', () {
    final String html = exporter.export(dashboardJson(<Map<String, dynamic>>[]));
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('<svg'));
    expect(html, contains('const DATA='));
    expect(html, contains('</html>'));
  });

  test('含开始/步骤/结束与连线的完整图', () {
    final String html = exporter.export(dashboardJson(<Map<String, dynamic>>[
      el(id: 's', x: 20, y: 20, kind: 'start', text: '开始'),
      el(id: 'a', x: 260, y: 20, kind: 'step', text: '步骤 1'),
      el(
        id: 'e',
        x: 500,
        y: 20,
        kind: 'end',
        text: '结束',
        next: <Map<String, dynamic>>[],
      ),
      // 连线通过 next 表达(挂在源节点上)。
    ]));
    // 播放器数据含全部节点与连线。
    expect(html, contains('"kind":"start"'));
    expect(html, contains('"kind":"end"'));
    expect(html, contains('n${'s'}'));
    expect(html, contains('n${'a'}'));
    expect(html, contains('n${'e'}'));
  });

  test('带分支与批注的连线进入播放数据', () {
    final String html = exporter.export(dashboardJson(<Map<String, dynamic>>[
      el(id: 's', x: 20, y: 20, kind: 'start'),
      el(
        id: 'd',
        x: 260,
        y: 20,
        kind: 'decision',
        note: '条件?',
        next: <Map<String, dynamic>>[
          conn('yes', note: '是'),
          conn('no', note: '否'),
        ],
      ),
      el(id: 'yes', x: 260, y: 160, kind: 'step', text: '是分支'),
      el(id: 'no', x: 500, y: 160, kind: 'step', text: '否分支'),
    ]));
    expect(html, contains('"kind":"decision"'));
    expect(html, contains('"srcId":"d"'));
    expect(html, contains('"note":"是"'));
    expect(html, contains('"note":"否"'));
    // SVG 连线元素存在。
    expect(html, contains('c${'d'}_${'yes'}'));
    expect(html, contains('c${'d'}_${'no'}'));
  });

  test('泳道渲染为虚线分区', () {
    final String html = exporter.export(dashboardJson(<Map<String, dynamic>>[
      el(id: 'lane1', x: 10, y: 10, lane: true, text: '分区 1'),
      el(id: 's', x: 60, y: 60, kind: 'start'),
    ]));
    expect(html, contains('class="lane"'));
    expect(html, contains('分区 1'));
  });

  test('HTML 为合法转义(节点文本含 < > &)', () {
    final String html = exporter.export(dashboardJson(<Map<String, dynamic>>[
      el(id: 's', x: 0, y: 0, kind: 'start', text: 'A & B <C>'),
    ]));
    expect(html, contains('&amp;'));
    expect(html, contains('&lt;C&gt;'));
  });

  group('v2 FlowDoc 输入(3c-2)', () {
    test('节点/连线/分支名播放数据齐全', () {
      final String doc = json.encode(<String, dynamic>{
        'v': 2,
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 's1',
            'k': 'start',
            'x': 80,
            'y': 300,
            't': '开始',
          },
          <String, dynamic>{
            'id': 'd1',
            'k': 'decision',
            'x': 480,
            'y': 250,
            't': '有货?',
          },
          <String, dynamic>{
            'id': 's2',
            'k': 'step',
            'x': 780,
            'y': 120,
            't': '下单',
          },
          <String, dynamic>{
            'id': 'e1',
            'k': 'end',
            'x': 780,
            'y': 400,
            't': '结束',
          },
        ],
        'edges': <dynamic>[
          <String, dynamic>{
            'id': 'c0',
            'src': 's1',
            'sp': 'o0',
            'dst': 'd1',
            'dp': 'i0',
            'd': <String, dynamic>{},
          },
          <String, dynamic>{
            'id': 'c1',
            'src': 'd1',
            'sp': 'o0',
            'dst': 's2',
            'dp': 'i0',
            'd': <String, dynamic>{'label': '有'},
          },
          <String, dynamic>{
            'id': 'c2',
            'src': 'd1',
            'sp': 'o1',
            'dst': 'e1',
            'dp': 'i0',
            'd': <String, dynamic>{'label': '无'},
          },
        ],
      });
      final String html = exporter.export(doc);
      expect(html, contains('class="node start"'));
      expect(html, contains('class="node decision"'));
      expect(html, contains('class="node end"'));
      expect(html, contains('"note":"有"'));
      expect(html, contains('"note":"无"'));
      expect(html, contains('c${'s1'}_${'d1'}'));
      expect(html, contains('c${'d1'}_${'e1'}'));
    });

    test('v2 自定义色节点写入内联 fill', () {
      final String doc = json.encode(<String, dynamic>{
        'v': 2,
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 'a',
            'k': 'step',
            'x': 0,
            'y': 0,
            't': '自定义',
            'c': true,
            'color': 0xFF3482FF,
          },
        ],
        'edges': <dynamic>[],
      });
      final String html = exporter.export(doc);
      expect(html, contains('fill="#3482ff"'));
    });

    test('v2 泳道渲染为虚线分区(尺寸 w/h/标题)', () {
      final String doc = json.encode(<String, dynamic>{
        'v': 2,
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 'lane1',
            'k': 'lane',
            'x': 40,
            'y': 40,
            'w': 600,
            'h': 300,
            't': '主流程',
          },
          <String, dynamic>{
            'id': 's',
            'k': 'start',
            'x': 120,
            'y': 120,
            't': '开始',
          },
        ],
        'edges': <dynamic>[],
      });
      final String html = exporter.export(doc);
      expect(html, contains('class="lane"'));
      expect(html, contains('主流程'));
      // 普通节点仍为 node 渲染(非 lane 分支)。
      expect(html, contains('class="node start"'));
    });
  });
}
