// lib/domain/entities/flow_doc.dart
// 编号:P-11 数据模型(v1.46 阶段1,vyuh_node_flow 内核的新落盘文档格式)
// 说明:取代 flutter_flow_chart Dashboard JSON 的流程图持久化模型。
//   - FlowDoc 为 version 化文档(自定 JSON,不依赖内核序列化);
//   - FlowNodeData/FlowEdgeData 为 vyuh 泛型 T/C 的载体(controller 以
//     C=dynamic 运行,见 PLAN_v1.46_flow_vyuh.md §3.1,读写经本类转换);
//   - 节点 id 即 vyuh Node.id;连线端点端口 id 由编辑器按出入度分配(iN/oN);
//   - 纯 Dart(无 dart:ui 依赖),可单测;坐标用像素逻辑值(double)。
import 'dart:convert' show jsonDecode, jsonEncode;

/// 流程节点语义类型(与旧 FlowNodeKind 同义;形状/配色由展示层映射)。
enum FlowNodeKind {
  start,
  step,
  decision,
  end,
  lane; // 泳道分区(阶段2:GroupNode 语义,虚线框/标题 chip/子节点跟随)。

  static FlowNodeKind parse(String s) => FlowNodeKind.values.firstWhere(
        (FlowNodeKind k) => k.name == s,
        orElse: () => FlowNodeKind.step,
      );

  /// 默认标题(与旧默认一致;步骤/判断带序号由调用方补)。
  String defaultLabel(int index) => switch (this) {
        FlowNodeKind.start => '开始',
        FlowNodeKind.step => '步骤 $index',
        FlowNodeKind.decision => '判断 $index',
        FlowNodeKind.end => '结束',
        FlowNodeKind.lane => '泳道 $index',
      };

  /// 是否流程执行节点(泳道为容器,不进播放/逻辑)。
  bool get isFlowStep => this != FlowNodeKind.lane;
}

/// 节点数据(vyuh `Node<T>` 的 T;id 即 Node.id)。
class FlowNodeData {
  const FlowNodeData({
    required this.id,
    required this.kind,
    required this.dx,
    required this.dy,
    this.title = '',
    this.note = '',
    this.locked = false,
    this.badge = 0, // 步骤/判断序号(0=无)
    this.customStyled = false,
    this.customColor = 0, // ARGB;0=按 kind 主题取色
    this.w, // 尺寸覆盖(仅 lane:可拉伸,落盘实际宽;null=kind 默认)
    this.h,
  });

  final String id;
  final FlowNodeKind kind;
  final double dx;
  final double dy;
  final String title;
  final String note;
  final bool locked;
  final int badge;
  final bool customStyled;
  final int customColor;

  /// 泳道实际宽/高(非 lane 恒 null;编辑器拉伸后回写)。
  final double? w;
  final double? h;

  /// 语义尺寸:lane 取 [w]/[h](或默认),其余由 kind 派生。
  double get width => w ?? FlowNodeData.widthOf(kind);

  double get height => h ?? FlowNodeData.heightOf(kind);

  /// 节点语义尺寸(展示层固定;与旧编辑器一致,连线锚点依赖)。
  static double widthOf(FlowNodeKind kind) => switch (kind) {
        FlowNodeKind.start || FlowNodeKind.end => 130,
        FlowNodeKind.step => 180,
        FlowNodeKind.decision => 200,
        FlowNodeKind.lane => 420,
      };

  static double heightOf(FlowNodeKind kind) => switch (kind) {
        FlowNodeKind.start || FlowNodeKind.end => 56,
        FlowNodeKind.step => 66,
        FlowNodeKind.decision => 84,
        FlowNodeKind.lane => 240,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'k': kind.name,
        'x': dx,
        'y': dy,
        if (w != null) 'w': w,
        if (h != null) 'h': h,
        't': title,
        'note': note,
        'lock': locked,
        'n': badge,
        'c': customStyled,
        'color': customColor,
      };

  factory FlowNodeData.fromJson(Map<String, dynamic> m) => FlowNodeData(
        id: m['id'] as String? ?? '',
        kind: FlowNodeKind.parse(m['k'] as String? ?? 'step'),
        dx: (m['x'] as num?)?.toDouble() ?? 0,
        dy: (m['y'] as num?)?.toDouble() ?? 0,
        w: (m['w'] as num?)?.toDouble(),
        h: (m['h'] as num?)?.toDouble(),
        title: m['t'] as String? ?? '',
        note: m['note'] as String? ?? '',
        locked: m['lock'] as bool? ?? false,
        badge: (m['n'] as num?)?.toInt() ?? 0,
        customStyled: m['c'] as bool? ?? false,
        customColor: (m['color'] as num?)?.toInt() ?? 0,
      );

  FlowNodeData copyWith({
    String? title,
    String? note,
    bool? locked,
    int? badge,
    bool? customStyled,
    int? customColor,
    double? dx,
    double? dy,
    double? w,
    double? h,
    bool clearSize = false,
  }) =>
      FlowNodeData(
        id: id,
        kind: kind,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        w: clearSize ? null : (w ?? this.w),
        h: clearSize ? null : (h ?? this.h),
        title: title ?? this.title,
        note: note ?? this.note,
        locked: locked ?? this.locked,
        badge: badge ?? this.badge,
        customStyled: customStyled ?? this.customStyled,
        customColor: customColor ?? this.customColor,
      );
}

/// 连线数据(vyuh `Connection<C>` 的 C):分支名/批注/样式。
class FlowEdgeData {
  const FlowEdgeData({
    this.label = '', // 分支名(判断多出口,播放选路显示)
    this.note = '', // 连线批注
    this.arrow = 1, // 0 none / 1 single(终点) / 2 both(对齐旧 ArrowHead)
    this.color = 0, // ARGB;0=主题默认
    this.width = 0, // 线宽;0=主题默认
  });

  final String label;
  final String note;
  final int arrow;
  final int color;
  final double width;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'note': note,
        'arrow': arrow,
        'color': color,
        'width': width,
      };

  factory FlowEdgeData.fromJson(Map<String, dynamic> m) => FlowEdgeData(
        label: m['label'] as String? ?? '',
        note: m['note'] as String? ?? '',
        arrow: (m['arrow'] as num?)?.toInt() ?? 1,
        color: (m['color'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toDouble() ?? 0,
      );

  FlowEdgeData copyWith({
    String? label,
    String? note,
    int? arrow,
    int? color,
    double? width,
  }) =>
      FlowEdgeData(
        label: label ?? this.label,
        note: note ?? this.note,
        arrow: arrow ?? this.arrow,
        color: color ?? this.color,
        width: width ?? this.width,
      );
}

/// 流程文档连线(id 唯一;端点为 vyuh 端口 id,如 i0/o0)。
class FlowEdge {
  FlowEdge({
    required this.id,
    required this.srcNodeId,
    required this.srcPortId,
    required this.dstNodeId,
    required this.dstPortId,
    this.data = const FlowEdgeData(),
  });

  final String id;
  final String srcNodeId;
  final String srcPortId;
  final String dstNodeId;
  final String dstPortId;
  final FlowEdgeData data;
}

/// 流程文档(落盘格式;version 只增,旧版文档经迁移器转当前版)。
class FlowDoc {
  FlowDoc({required this.nodes, required this.edges});

  /// 文档版本(2 = vyuh 内核;1 = 旧 flutter_flow_chart)。
  static const int version = 2;

  final List<FlowNodeData> nodes;
  final List<FlowEdge> edges;

  String toJson() => jsonEncode(<String, dynamic>{
        'v': version,
        'nodes': <dynamic>[for (final FlowNodeData n in nodes) n.toJson()],
        'edges': <dynamic>[
          for (final FlowEdge e in edges)
            <String, dynamic>{
              'id': e.id,
              'src': e.srcNodeId,
              'sp': e.srcPortId,
              'dst': e.dstNodeId,
              'dp': e.dstPortId,
              'd': e.data.toJson(),
            },
        ],
      });

  /// 解析失败抛 [FormatException];版本 1 旧文档应先经迁移器。
  factory FlowDoc.fromJson(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('FlowDoc:顶层不是对象');
    }
    final int v = (decoded['v'] as num?)?.toInt() ?? 0;
    if (v != version) {
      throw FormatException('FlowDoc:版本 $v 不识别(期望 $version)');
    }
    return FlowDoc(
      nodes: <FlowNodeData>[
        for (final dynamic rawNode in decoded['nodes'] as List<dynamic>? ?? const <dynamic>[])
          FlowNodeData.fromJson(rawNode as Map<String, dynamic>),
      ],
      edges: <FlowEdge>[
        for (final dynamic rawEdge in decoded['edges'] as List<dynamic>? ?? const <dynamic>[])
          FlowEdge(
            id: rawEdge['id'] as String,
            srcNodeId: rawEdge['src'] as String,
            srcPortId: rawEdge['sp'] as String,
            dstNodeId: rawEdge['dst'] as String,
            dstPortId: rawEdge['dp'] as String,
            data: FlowEdgeData.fromJson(
              (rawEdge['d'] as Map<String, dynamic>?) ??
                  const <String, dynamic>{},
            ),
          ),
      ],
    );
  }
}
