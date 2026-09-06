// lib/presentation/features/todo/page_p11_v2_flow_editor_page.dart
// 编号:P-11 v2(vyuh_node_flow 内核,v1.46 阶段1-b 骨架)
// 说明:流程图编辑器新内核版(旧 P-11 保留至旧内核移除提交)。
//   - 打开:读 flowchart_$taskId —— v2(FlowDoc)直读;旧 Dashboard JSON
//     自动迁移并写回;空 → 空文档;
//   - 编辑:VyuhFlowEditor(vyuh 内核:拖动/连线/框选/键盘内建)+ 基础
//     工具行(添加四类节点/删除选中/适应视图);详情弹窗/样式/批注/播放/
//     导出/撤销重做为 3b-2/3c(见 PLAN_v1.46_flow_vyuh.md);
//   - 保存:图事件防抖 500ms → docFromGraph → 写回 v2;dispose 兜底落盘;
//   - 端口策略与泛型说明见 vyuh_flow_codec.dart / PLAN §3.1。
import 'dart:async' show Timer, unawaited;
import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../core/export/flow_html_exporter.dart';
import '../../../core/flow/flow_clipboard.dart';
import '../../../core/flow/flow_connect_rules.dart';
import '../../../core/flow/legacy_flow_migrator.dart';
import '../../../core/logging/app_log_service.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../../domain/entities/flow_doc.dart';
import '../../../domain/entities/todo_item.dart';
import '../../providers/todo_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c48_flow_toolbar_v2.dart';
import '../flow/vyuh_flow_codec.dart';
import '../flow/vyuh_flow_editor.dart';
import '../flow/vyuh_flow_node_card.dart';
import '../flow/vyuh_flow_theme.dart';

/// P-11 v2 流程图编辑器页(/todo/:taskId)。
class PageP11V2FlowEditorPage extends ConsumerStatefulWidget {
  const PageP11V2FlowEditorPage({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<PageP11V2FlowEditorPage> createState() =>
      _PageP11V2FlowEditorPageState();
}

class _PageP11V2FlowEditorPageState
    extends ConsumerState<PageP11V2FlowEditorPage> {
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('p11v2.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  /// 图控制器(页面持有/释放;meta 变更时换新实例并整树重建编辑器)。
  NodeFlowController<FlowNodeData, dynamic>? _ctrl;

  /// 当前文档(编辑器数据源;meta 变更重建后更新)。
  FlowDoc? _doc;
  Timer? _saveDebounce;
  int _addSeq = 0;

  /// 节点业务数据覆盖(id → FlowNodeData;改名/批注/锁/自定义色经
  /// docFromGraph(dataFor:) 合入重建,规避 vyuh Node.data 不可变限制)。
  final Map<String, FlowNodeData> _meta = <String, FlowNodeData>{};

  /// 重建后待恢复视口(帧后应用)。
  GraphViewport? _pendingViewport;

  /// 复制子图(阶段2;原坐标;粘贴时按视口中心平移重映射)。
  FlowDoc? _clip;

  /// 缩略图/LOD/图例(阶段2)。
  bool _showMiniMap = false;
  bool _lodOn = false;
  bool _legendOpen = false;

  /// 尺寸编辑模式目标(阶段2 fix;非空 = 该泳道仅可调整尺寸)。
  String? _resizeNodeId;

  /// C-48 v2 悬浮工具栏(点画布空白收起)。
  final GlobalKey<C48FlowToolbarV2State> _toolbarKey =
      GlobalKey<C48FlowToolbarV2State>();

  /// 宽屏右栏宽度(阶段3 收尾:分隔条拖拽可调,240-420;会话级)。
  double _rightPanelWidth = 272;
  bool _rightDragging = false;

  // ── 撤销/重做(3c,整图快照栈 20)──────────────────────────────
  final List<String> _undo = <String>[];
  final List<String> _redo = <String>[];
  static const int _kUndoLimit = 20;

  // ── 逻辑播放(3c)──────────────────────────────────────────────
  bool _playing = false; // 播放中(编辑器转 inspect 禁改)
  bool _playAuto = false; // 自动步进(定时器推进)
  bool _playDone = false; // 已到达终点(高亮保留)
  String? _playCurId; // 当前执行节点
  String? _playActiveConnId; // 当前激活连线(高亮中)
  int _playStepCount = 0;
  int _speedIndex = 1; // 默认 1.2s(档位 0.6/1.2/2.0)
  Timer? _playTimer;
  bool _branchOpen = false; // 判断多出口选路弹窗
  List<String> _branchConnIds = <String>[]; // 候选连线 id

  /// 弹层状态(单击节点/连线打开;show 驱动零开销)。
  String? _nodeSheetId;
  String? _connSheetId;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _labelCtrl = TextEditingController();

  /// 弹层编辑临时态(打开时初始化,应用时写入)。
  bool _nodeLock = false;
  int? _nodeColorSel;
  int? _connColorSel;
  double? _connWidthSel;
  int _connArrow = 1;

  /// 节点自定义色板(0 = 恢复主题默认;与连线色板共用基调)。
  static const List<int> _palette = <int>[
    0,
    0xFF8A93A6,
    0xFFE5533D,
    0xFFFF8A3D,
    0xFFF5A623,
    0xFF36D167,
    0xFF00A6B5,
    0xFF3482FF,
    0xFF8E5BFF,
    0xFFEB4B96,
  ];

  /// 连线色板(九色;再点已选色恢复默认)。
  static const List<int> _edgePalette = <int>[
    0xFF8A93A6,
    0xFFE5533D,
    0xFFFF8A3D,
    0xFFF5A623,
    0xFF36D167,
    0xFF00A6B5,
    0xFF3482FF,
    0xFF8E5BFF,
    0xFFEB4B96,
  ];

  /// 持久化有意义事件白名单(视口/选择/hover 等不触发保存)。
  /// 撤销快照入栈语义:离散结构事件即时入栈;连续变化(拖动/缩放)只在
  /// 结束事件(NodeDragEnded/ResizeEnded)入栈一次,避免每帧快照。
  static const Set<String> _saveEvents = <String>{
    'NodeAdded',
    'NodeRemoved',
    'NodeDataChanged',
    'NodeLockChanged',
    'ConnectionAdded',
    'ConnectionRemoved',
    'GraphLoaded',
    'GraphCleared',
    'NodeDragEnded',
    'ResizeEnded',
    'BatchEnded',
  };

  @override
  void initState() {
    super.initState();
    // PC/Web 键盘(阶段3 批3-4):Ctrl+Z/Y/C/V/X 宿主接管
    // (vyuh 内建 copy/paste 未实现;Delete/全选等由编辑器内建处理)。
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  /// 桌面快捷键(Ctrl/Meta + Z/Y/C/V/X);返回 true = 已消费(不再进
  /// 编辑器 Focus 链;Delete/Backspace/Ctrl+A 留给 vyuh 内建)。
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final bool ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!ctrl) return false;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyZ:
        if (HardwareKeyboard.instance.isShiftPressed) {
          _redoAction();
        } else {
          _undoAction();
        }
        return true;
      case LogicalKeyboardKey.keyY:
        _redoAction();
        return true;
      case LogicalKeyboardKey.keyC:
        _copySelected();
        return true;
      case LogicalKeyboardKey.keyX:
        _cutSelected();
        return true;
      case LogicalKeyboardKey.keyV:
        _pasteClip();
        return true;
      default:
        return false;
    }
  }

  /// 剪切:复制子图后删除选中(批量边界整批可撤销)。
  void _cutSelected() {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    _copySelected();
    if (_clip == null) return;
    final NodeFlowController<FlowNodeData, dynamic> ctrl = c;
    final List<String> nodeIds = ctrl.nodes.values
        .where((Node<FlowNodeData> n) => n.isSelected && !n.locked)
        .map((Node<FlowNodeData> n) => n.id)
        .toList();
    final List<String> connIds = ctrl.selectedConnectionIds.toList();
    if (nodeIds.isEmpty && connIds.isEmpty) return;
    ctrl.mutateGraph(() {
      if (connIds.isNotEmpty) ctrl.removeConnections(connIds);
      if (nodeIds.isNotEmpty) ctrl.deleteNodes(nodeIds);
    }, reason: 'cut');
  }

  Future<void> _init() async {
    final String raw =
        ref.read(todoRepositoryProvider).loadFlowchart(widget.taskId) ?? '';
    FlowDoc doc;
    if (raw.isEmpty) {
      doc = FlowDoc(nodes: const <FlowNodeData>[], edges: const <FlowEdge>[]);
    } else {
      try {
        doc = FlowDoc.fromJson(raw); // v2 直读。
      } on FormatException {
        // 旧 Dashboard JSON:迁移并写回 v2。
        final FlowMigrateReport report = FlowMigrateReport();
        doc = migrateLegacyFlowJson(raw, report: report);
        AppLogService.instance.info(
          'p11v2',
          '旧格式迁移:${doc.nodes.length} 节点 / ${doc.edges.length} 连线'
          '(泳道转 LaneNode ${report.lanes})',
        );
        unawaitedSave(doc);
      }
    }
    if (!mounted) return;
    _meta
      ..clear()
      ..addEntries(
        doc.nodes.map(
          (FlowNodeData n) => MapEntry<String, FlowNodeData>(n.id, n),
        ),
      );
    final NodeFlowController<FlowNodeData, dynamic> ctrl = _makeController(doc);
    setState(() {
      _doc = doc;
      _ctrl = ctrl;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.fitToView(); // editor 首帧(screenSize 就绪)后适配。
    });
  }

  /// 由文档构建控制器(注入自渲染卡与自动保存/撤销快照插件)。
  NodeFlowController<FlowNodeData, dynamic> _makeController(FlowDoc doc) {
    return NodeFlowController<FlowNodeData, dynamic>(
      nodes: nodesFromDoc(
        doc,
        widgetBuilder: buildVyuhFlowNodeCard,
        laneBuilder: buildLaneNodeCard,
      ),
      connections: edgesFromDoc(doc),
    )
      ..addPlugin(_DirtyPlugin(_scheduleSave, _pushUndo))
      // 细节层次(阶段2):缩小隐藏细节,大图性能;开关经 controller.lod。
      ..addPlugin(LodPlugin(enabled: _lodOn))
      // 自动平移(阶段3):拖动节点/连线到画布边缘自动滚动(50px 触发区)。
      ..addPlugin(AutoPanPlugin());
  }

  void unawaitedSave(FlowDoc doc) {
    // 写回(迁移后立即持久化为 v2)。
    unawaited(
      ref
          .read(todoRepositoryProvider)
          .saveFlowchart(widget.taskId, doc.toJson()),
    );
  }

  // ── 自动保存(图事件 → 防抖 500ms → docFromGraph 落盘)────────────

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _flushSave);
  }

  Future<void> _flushSave() async {
    final NodeFlowController<FlowNodeData, dynamic> c = _ctrl!;
    final FlowDoc doc = docFromGraph(
      c,
      dataFor: (String id) => _meta[id] ?? _fallbackNodeData(id, c),
    );
    await ref.read(todoRepositoryProvider).saveFlowchart(
          widget.taskId,
          doc.toJson(),
        );
  }

  FlowNodeData _fallbackNodeData(
    String id,
    NodeFlowController<FlowNodeData, dynamic> ctrl,
  ) {
    return ctrl.nodes[id]?.data ??
        FlowNodeData(id: id, kind: FlowNodeKind.step, dx: 0, dy: 0);
  }

  /// 安装整图:换新 controller(组件整树重建,editor 完整 init)+ meta 同步
  /// + 帧后恢复视口 + 旧控制器释放 + 触发保存。
  void _installDoc(FlowDoc doc) {
    final NodeFlowController<FlowNodeData, dynamic> old = _ctrl!;
    final GraphViewport vp = old.viewport;
    final NodeFlowController<FlowNodeData, dynamic> ctrl = _makeController(doc);
    // 尺寸编辑模式跨重建保持(目标节点仍存在时);否则退出。
    final String? resizeId = _resizeNodeId;
    final bool keepResize = resizeId != null &&
        doc.nodes.any((FlowNodeData n) => n.id == resizeId);
    if (keepResize) {
      ctrl.setResizeOnlyNode(resizeId);
    }
    _meta
      ..clear()
      ..addEntries(
        doc.nodes.map(
          (FlowNodeData n) => MapEntry<String, FlowNodeData>(n.id, n),
        ),
      );
    setState(() {
      _doc = doc;
      _ctrl = ctrl;
      _pendingViewport = vp;
      if (!keepResize) _resizeNodeId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final GraphViewport? restore = _pendingViewport;
      _pendingViewport = null;
      if (restore != null) {
        ctrl.setViewport(restore);
      }
    });
    old.dispose();
    _scheduleSave();
  }

  /// meta 业务字段变更(改名/批注/锁/色)后的整图重建(先推撤销快照)。
  void _rebuildFromMeta() {
    final NodeFlowController<FlowNodeData, dynamic> c = _ctrl!;
    _pushUndo();
    _installDoc(
      docFromGraph(
        c,
        dataFor: (String id) => _meta[id] ?? _fallbackNodeData(id, c),
      ),
    );
  }

  // ── 撤销/重做(3c,整图快照栈;与旧编辑器同思路)───────────────

  String _snapshotJson() {
    final NodeFlowController<FlowNodeData, dynamic> c = _ctrl!;
    return docFromGraph(
      c,
      dataFor: (String id) => _meta[id] ?? _fallbackNodeData(id, c),
    ).toJson();
  }

  /// 撤销快照:当前状态入栈(去重;离散事件即时,连续动作由结束事件驱动)。
  void _pushUndo() {
    final String json = _snapshotJson();
    if (_undo.isNotEmpty && _undo.last == json) return;
    _undo.add(json);
    if (_undo.length > _kUndoLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoAction() {
    if (_undo.isEmpty) {
      showMiniToast(context, '无可撤销');
      return;
    }
    _redo.add(_snapshotJson());
    _applyDocJson(_undo.removeLast());
  }

  void _redoAction() {
    if (_redo.isEmpty) {
      showMiniToast(context, '无可重做');
      return;
    }
    _undo.add(_snapshotJson());
    _applyDocJson(_redo.removeLast());
  }

  void _applyDocJson(String json) {
    final FlowDoc doc;
    try {
      doc = FlowDoc.fromJson(json);
    } on FormatException {
      return;
    }
    _installDoc(doc);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _saveDebounce?.cancel();
    _playTimer?.cancel();
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    _labelCtrl.dispose();
    // 兜底落盘(controller 仍存活,同步 flush)。
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c != null) {
      final FlowDoc doc = docFromGraph(
        c,
        dataFor: (String id) => _meta[id] ?? _fallbackNodeData(id, c),
      );
      if (doc.nodes.isNotEmpty ||
          doc.edges.isNotEmpty ||
          (_doc?.nodes.isNotEmpty ?? false)) {
        unawaited(
          ref
              .read(todoRepositoryProvider)
              .saveFlowchart(widget.taskId, doc.toJson()),
        );
      }
    }
    _ctrl?.dispose();
    _ctrl = null;
    super.dispose();
  }

  // ── 节点添加(基础工具行)────────────────────────────────────────

  void _addNode(FlowNodeKind kind) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    final NodeFlowController<FlowNodeData, dynamic> ctrl = c;
    final int seq = ++_addSeq;
    // 落点:当前视口中心(图坐标)。
    final Offset center = ctrl.viewportScreenBounds.rect.center;
    final Offset pos = ctrl.screenToGraph(ScreenPosition(center)).offset;
    final String id = 'n${DateTime.now().microsecondsSinceEpoch}';
    if (kind == FlowNodeKind.lane) {
      // 泳道:GroupNode(空间包含),默认尺寸,无端口。
      ctrl.addNode(
        GroupNode<FlowNodeData>(
          id: id,
          position: pos,
          size: Size(
            FlowNodeData.widthOf(FlowNodeKind.lane),
            FlowNodeData.heightOf(FlowNodeKind.lane),
          ),
          title: kind.defaultLabel(seq),
          data: FlowNodeData(
            id: id,
            kind: kind,
            dx: pos.dx,
            dy: pos.dy,
            title: kind.defaultLabel(seq),
          ),
          widgetBuilder: buildLaneNodeCard,
        ),
      );
      _scheduleSave();
      return;
    }
    // 序号:文档内同类计数 +1(步骤/判断)。
    final int kindCount =
        ctrl.nodes.values.where((Node<FlowNodeData> n) => n.data.kind == kind).length;
    final int badge =
        kind == FlowNodeKind.step || kind == FlowNodeKind.decision
        ? kindCount + 1
        : 0;
    final String title = kind.defaultLabel(seq);
    final Node<FlowNodeData> node = Node<FlowNodeData>(
      id: id,
      type: kind.name,
      position: pos,
      size: Size(FlowNodeData.widthOf(kind), FlowNodeData.heightOf(kind)),
      // 统一 in/out 各一(策略见 codec;新连线均可达)。
      ports: <Port>[
        Port(
          id: 'i0',
          name: 'in',
          type: PortType.input,
          position: PortPosition.left,
          multiConnections: true,
        ),
        Port(
          id: 'o0',
          name: 'out',
          type: PortType.output,
          position: PortPosition.right,
          multiConnections: true,
        ),
      ],
      widgetBuilder: buildVyuhFlowNodeCard,
      data: FlowNodeData(
        id: id,
        kind: kind,
        dx: pos.dx,
        dy: pos.dy,
        title: title,
        badge: badge,
      ),
    );
    ctrl.addNode(node);
    _scheduleSave();
  }

  void _deleteSelected() {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    final NodeFlowController<FlowNodeData, dynamic> ctrl = c;
    final List<String> nodeIds = ctrl.nodes.values
        .where((Node<FlowNodeData> n) => n.isSelected && !n.locked)
        .map((Node<FlowNodeData> n) => n.id)
        .toList();
    final bool skipped = ctrl.nodes.values
        .any((Node<FlowNodeData> n) => n.isSelected && n.locked);
    final List<String> connIds = ctrl.selectedConnectionIds.toList();
    if (nodeIds.isEmpty && connIds.isEmpty) {
      showMiniToast(context, '未选中可删除内容');
      return;
    }
    // 批量边界:撤销一步回退整批(BatchEnded 单次入栈)。
    ctrl.mutateGraph(() {
      if (connIds.isNotEmpty) ctrl.removeConnections(connIds);
      if (nodeIds.isNotEmpty) ctrl.deleteNodes(nodeIds);
    }, reason: 'delete-selection');
    if (skipped) showMiniToast(context, '已跳过锁定节点(需先解锁)');
  }

  // ── 复制/粘贴(阶段2;子图=选中流程节点+内部连线)─────────────────

  void _copySelected() {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    final NodeFlowController<FlowNodeData, dynamic> ctrl = c;
    final Set<String> ids = <String>{
      for (final Node<FlowNodeData> n in ctrl.nodes.values)
        if (n.isSelected) n.id,
    };
    if (ids.isEmpty) {
      showMiniToast(context, '未选中节点(单击节点后复制)');
      return;
    }
    final FlowDoc doc = docFromGraph(
      ctrl,
      dataFor: (String id) => _meta[id] ?? _fallbackNodeData(id, ctrl),
    );
    final FlowDoc clip = extractSubgraph(doc, ids);
    if (clip.nodes.isEmpty) {
      showMiniToast(context, '泳道分区不可复制(仅流程节点)');
      return;
    }
    _clip = clip;
    showMiniToast(context, '已复制 ${clip.nodes.length} 个节点');
  }

  void _pasteClip() {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    final FlowDoc? clip = _clip;
    if (c == null) return;
    if (clip == null || clip.nodes.isEmpty) {
      showMiniToast(context, '剪贴板为空(先选中节点复制)');
      return;
    }
    final NodeFlowController<FlowNodeData, dynamic> ctrl = c;
    // 锚点 → 当前视口中心。
    final ({double x, double y}) anchor = subgraphAnchor(clip);
    final Offset center = ctrl.viewportScreenBounds.rect.center;
    final Offset target = ctrl.screenToGraph(ScreenPosition(center)).offset;
    final int base = DateTime.now().microsecondsSinceEpoch;
    final (FlowDoc doc, Map<String, String> map) = remapSubgraph(
      clip,
      idGen: (int i) => 'p${base}_$i',
      offsetX: target.dx - anchor.x,
      offsetY: target.dy - anchor.y,
    );
    final List<Node<FlowNodeData>> nodes = nodesFromDoc(
      doc,
      widgetBuilder: buildVyuhFlowNodeCard,
      laneBuilder: buildLaneNodeCard,
    );
    final List<Connection<dynamic>> conns = edgesFromDoc(doc);
    ctrl.mutateGraph(() {
      if (nodes.isNotEmpty) ctrl.addNodes(nodes);
      if (conns.isNotEmpty) ctrl.addConnections(conns);
    }, reason: 'paste');
    // 粘贴组选中(便于移动/删除)。
    ctrl.selectNodes(<String>[for (final Node<FlowNodeData> n in nodes) n.id]);
    showMiniToast(context, '已粘贴 ${nodes.length} 个节点');
  }

  // ── 节点详情 / 连线样式(3b-2)───────────────────────────────────

  void _openNodeSheet(String id) {
    if (_playing) return; // 播放中禁编辑入口。
    final FlowNodeData? d = _meta[id];
    if (d == null) return;
    _titleCtrl.text = d.title;
    _noteCtrl.text = d.note;
    setState(() {
      _nodeSheetId = id;
      _connSheetId = null;
      _nodeLock = d.locked;
      _nodeColorSel =
          d.customStyled && d.customColor != 0 ? d.customColor : null;
    });
  }

  void _openConnSheet(String id) {
    if (_playing) return; // 播放中禁编辑入口。
    final Connection<dynamic>? c = _findConn(id);
    if (c == null) return;
    final FlowEdgeData old = c.data is FlowEdgeData
        ? c.data as FlowEdgeData
        : const FlowEdgeData();
    _labelCtrl.text = c.label?.text ?? old.label;
    setState(() {
      _connSheetId = id;
      _nodeSheetId = null;
      _connColorSel = c.color?.toARGB32();
      _connWidthSel = c.strokeWidth;
      _connArrow = arrowFromEndpoints(c);
    });
  }

  Connection<dynamic>? _findConn(String id) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return null;
    for (final Connection<dynamic> conn in c.connections) {
      if (conn.id == id) return conn;
    }
    return null;
  }

  /// 是否存在同 (src → dst) 连线(防重复;不含临时线)。
  bool _hasPair(String srcId, String dstId) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return false;
    for (final Connection<dynamic> conn in c.connections) {
      if (conn.sourceNodeId == srcId && conn.targetNodeId == dstId) {
        return true;
      }
    }
    return false;
  }

  /// 节点详情应用(改名/批注/锁/自定义色 → meta → 整图重建)。
  void _applyNodeSheet() {
    final String? id = _nodeSheetId;
    if (id == null) return;
    final FlowNodeData? cur = _meta[id];
    if (cur == null) return;
    if (cur.locked && _nodeLock) {
      // 锁定未解除:字段禁改,无变更可提交,仅关闭。
      setState(() => _nodeSheetId = null);
      return;
    }
    final String title = _titleCtrl.text.trim();
    final String note = _noteCtrl.text.trim();
    _meta[id] = cur.copyWith(
      title: title.isEmpty ? cur.title : title,
      note: note,
      locked: _nodeLock,
      customStyled: _nodeColorSel != null,
      customColor: _nodeColorSel ?? 0,
    );
    setState(() => _nodeSheetId = null);
    _rebuildFromMeta();
  }

  /// 删除节点(连带连线由内核处理;锁定节点拒绝)。
  void _deleteNode(String id) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    final Node<FlowNodeData>? n = c.nodes[id];
    if (n != null && n.locked) {
      showMiniToast(context, '节点已锁定,请先解锁');
      return;
    }
    c.deleteNodes(<String>[id]);
    _meta.remove(id);
    setState(() => _nodeSheetId = null);
    _rebuildFromMeta();
  }

  /// 连线样式应用(label/色/粗 写 connection 现态;保存时回读)。
  void _applyConnSheet() {
    final String? id = _connSheetId;
    final Connection<dynamic>? c = id == null ? null : _findConn(id);
    if (c == null) return;
    final String label = _labelCtrl.text.trim();
    c.label = label.isEmpty ? null : ConnectionLabel(text: label);
    c.color = _connColorSel == null ? null : Color(_connColorSel!);
    c.strokeWidth = _connWidthSel;
    applyEdgeArrow(c, _connArrow);
    setState(() => _connSheetId = null);
    _pushUndo(); // 样式入撤销栈(样式无图事件)。
    _scheduleSave();
  }

  /// 删除连线。
  void _deleteConn(String id) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    c.removeConnections(<String>[id]);
    setState(() => _connSheetId = null);
    _pushUndo();
    _scheduleSave();
  }

  // ── 逻辑播放(3c:推进/分支选路/自动步进/高亮)──────────────────

  Duration get _playInterval => switch (_speedIndex) {
        0 => const Duration(milliseconds: 600),
        2 => const Duration(milliseconds: 2000),
        _ => const Duration(milliseconds: 1200),
      };

  String _playSpeedLabel() => switch (_speedIndex) {
        0 => '0.6s',
        2 => '2.0s',
        _ => '1.2s',
      };

  void _togglePlay() {
    if (_playing) {
      _stopPlay();
    } else {
      _startPlay();
    }
  }

  void _startPlay() {
    // 播放与尺寸编辑互斥:进入播放先退出尺寸模式。
    if (_resizeNodeId != null) _exitResizeMode();
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    String? startId;
    for (final Node<FlowNodeData> n in c.nodes.values) {
      if (n.data.kind == FlowNodeKind.start) {
        startId = n.id;
        break;
      }
    }
    if (startId == null) {
      // 兜底:首个流程节点(泳道是容器,不进播放)。
      for (final Node<FlowNodeData> n in c.nodes.values) {
        if (n.data.kind.isFlowStep) {
          startId = n.id;
          break;
        }
      }
    }
    if (startId == null) return;
    setState(() {
      _playing = true;
      _playAuto = false;
      _playDone = false;
      _playStepCount = 0;
      _playCurId = startId;
    });
    _refreshHighlights();
  }

  void _stopPlay() {
    _playTimer?.cancel();
    setState(() {
      _playing = false;
      _playAuto = false;
      _playDone = false;
      _playCurId = null;
      _playActiveConnId = null;
      _branchOpen = false;
      _branchConnIds = <String>[];
    });
    _applyActiveConnEffect(null); // 停止:动画停(静止零 ticker)。
    _ctrl?.clearSelection();
  }

  /// 高亮刷新:清全部选择 → 激活线选中 + 当前节点选中(蓝框语义)。
  void _refreshHighlights() {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    final String? cur = _playCurId;
    final String? connId = _playActiveConnId;
    if (c == null) return;
    c.clearSelection();
    if (connId != null) c.selectConnection(connId);
    if (cur != null) c.selectNode(cur);
  }

  /// 播放连线动画(阶段3 收尾):激活线设置流光效果(GradientFlow,走
  /// 连线层独立 animated RepaintBoundary,静态层不重绘;停止/换线清除,
  /// 静止零 ticker 恢复);分支等待期间持续流动,结束保留静态高亮。
  void _applyActiveConnEffect(String? activeId) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    final GradientFlowEffect flow = GradientFlowEffect(
      speed: 1,
      gradientLength: 0.3,
      connectionOpacity: 1,
    );
    for (final Connection<dynamic> conn in c.connections) {
      if (conn.id == activeId) {
        conn.animationEffect ??= flow;
      } else if (conn.animationEffect != null) {
        conn.animationEffect = null;
      }
    }
  }

  /// 自动/手动单步推进(无出口 → 结束)。
  void _stepPlay() {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    final String? cur = _playCurId;
    if (!_playing || _playDone || c == null || cur == null) return;
    final List<Connection<dynamic>> outs = c.connections
        .where((Connection<dynamic> e) => e.sourceNodeId == cur)
        .toList();
    if (outs.isEmpty) {
      setState(() => _playDone = true);
      showMiniToast(context, '流程结束');
      return;
    }
    if (outs.length > 1) {
      // 判断/多出口:弹分支选路(自动暂停,选后继续)。
      setState(() {
        _branchOpen = true;
        _branchConnIds = <String>[for (final Connection<dynamic> o in outs) o.id];
      });
      return;
    }
    _advanceAlong(outs.first.id);
    _maybeAutoNext();
  }

  void _pickBranch(String connId) {
    setState(() {
      _branchOpen = false;
      _branchConnIds = <String>[];
    });
    _advanceAlong(connId);
    _maybeAutoNext();
  }

  void _advanceAlong(String connId) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    Connection<dynamic>? conn;
    for (final Connection<dynamic> e in c.connections) {
      if (e.id == connId) {
        conn = e;
        break;
      }
    }
    if (conn == null) return;
    final String targetId = conn.targetNodeId;
    setState(() {
      _playActiveConnId = connId;
      _playCurId = targetId;
      _playStepCount++;
    });
    _refreshHighlights();
    _applyActiveConnEffect(connId); // 激活线流光动画。
    final bool noOut = !c.connections
        .any((Connection<dynamic> e) => e.sourceNodeId == targetId);
    if (noOut) {
      setState(() => _playDone = true);
      _applyActiveConnEffect(null); // 到达终点:静态高亮保留,动画停。
      showMiniToast(context, '流程结束');
    }
  }

  void _maybeAutoNext() {
    if (_playAuto && _playing && !_playDone) {
      _playTimer?.cancel();
      _playTimer = Timer(_playInterval, _stepPlay);
    }
  }

  void _setPlayAuto(bool auto) {
    setState(() => _playAuto = auto);
    if (auto && _playing && !_playDone) {
      _playTimer?.cancel();
      _playTimer = Timer(_playInterval, _stepPlay);
    } else if (!auto) {
      _playTimer?.cancel();
    }
  }

  void _cyclePlaySpeed() {
    setState(() => _speedIndex = (_speedIndex + 1) % 3);
  }

  // ── HTML 播放文件导出(3c-2,FlowDoc v2)────────────────────────

  void _toggleMiniMap() => setState(() => _showMiniMap = !_showMiniMap);

  void _toggleLod() {
    setState(() => _lodOn = !_lodOn);
    _ctrl?.lod?.setEnabled(_lodOn);
  }

  // ── 尺寸编辑模式(阶段2 fix:泳道显式编辑入口)───────────────────

  /// 进入尺寸编辑:目标节点禁整体拖动,把手常显+命中放大(整边框带)。
  void _startResizeMode(String id) {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    c.clearSelection();
    c.setResizeOnlyNode(id);
    setState(() {
      _nodeSheetId = null;
      _resizeNodeId = id;
    });
    showMiniToast(context, '拖动泳道边框/角调整尺寸,完成后点顶部「完成」');
  }

  void _exitResizeMode() {
    _ctrl?.setResizeOnlyNode(null);
    setState(() => _resizeNodeId = null);
  }

  Future<void> _exportHtml() async {
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return;
    if (c.nodes.isEmpty) {
      showMiniToast(context, '画布为空,无可导出内容');
      return;
    }
    final FlowDoc doc = docFromGraph(
      c,
      dataFor: (String id) => _meta[id] ?? _fallbackNodeData(id, c),
    );
    final String html = const FlowHtmlExporter().export(doc.toJson());
    final Uri? saved;
    try {
      saved = await FilePicker.saveFile(
        dialogTitle: '保存流程图演示文件',
        fileName: '流程图.html',
        type: FileType.custom,
        allowedExtensions: const <String>['html'],
        bytes: Uint8List.fromList(utf8.encode(html)),
      );
    } catch (e) {
      if (!mounted) return;
      showMiniToast(context, '导出失败:$e');
      return;
    }
    if (saved == null) return; // 用户取消。
    if (!mounted) return;
    showMiniToast(context, '已导出 HTML 播放文件');
  }

  // ── UI ─────────────────────────────────────────────────────────

  /// 节点详情面板(改名/批注/锁定/自定义色/删除;锁定中禁改,先解锁)。
  Widget _buildNodeSheet() {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final FlowNodeData? d = _meta[_nodeSheetId];
    if (d == null) return const SizedBox.shrink();
    // 锁定中:标题/批注/色板禁改(解锁开关除外),删除拒绝。
    final bool locked = _nodeLock;
    final Widget fields = Opacity(
      opacity: locked ? 0.4 : 1,
      child: IgnorePointer(
        ignoring: locked,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MiuixTextField(label: '标题', controller: _titleCtrl),
            const SizedBox(height: 8),
            MiuixTextField(label: '批注', controller: _noteCtrl),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                MiuixText(
                  '节点颜色',
                  fontSize: 12,
                  color: colors.onSurfaceVariantSummary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final int c in _palette)
                        _colorDot(
                          c,
                          selected: c == 0
                              ? _nodeColorSel == null
                              : _nodeColorSel == c,
                          onTap: () {
                            if (locked) return;
                            setState(() {
                              _nodeColorSel = c == 0 ? null : c;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          fields,
          const SizedBox(height: 12),
          GestureDetector(
            key: const ValueKey('p11v2.lock'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _nodeLock = !_nodeLock),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  MiuixIcon(
                    vector: appIcon(_nodeLock ? 'lock' : 'unlock'),
                    size: 14,
                    tint:
                        _nodeLock ? colors.primary : colors.onSurfaceVariantActions,
                  ),
                  const SizedBox(width: 8),
                  MiuixText(
                    _nodeLock ? '已锁定(不可拖动/编辑)' : '锁定节点',
                    fontSize: 13,
                    color: _nodeLock ? colors.primary : colors.onSurface,
                  ),
                ],
              ),
            ),
          ),
          if (d.kind == FlowNodeKind.lane) ...<Widget>[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: MiuixButton(
                key: const ValueKey('p11v2.editSize'),
                onPressed: () {
                  if (_nodeLock) {
                    showMiniToast(context, '节点已锁定,请先解锁');
                    return;
                  }
                  _startResizeMode(d.id);
                },
                minHeight: 32,
                insideMargin: const EdgeInsets.symmetric(horizontal: 12),
                colors: MiuixButtonColors(
                  color: colors.primary.withValues(alpha: 0.12),
                  disabledColor: colors.primary.withValues(alpha: 0.06),
                  contentColor: colors.primary,
                  disabledContentColor:
                      colors.primary.withValues(alpha: 0.4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MiuixIcon(
                      vector: appIcon('edit'),
                      size: 13,
                      tint: colors.primary,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      '编辑尺寸',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            MiuixText(
              '进入后拖动泳道边框/角调整;完成后点底部「完成」',
              fontSize: 11,
              color: colors.onSurfaceVariantSummary,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              MiuixButton(
                onPressed: locked
                    ? null
                    : () => _deleteNode(d.id),
                minHeight: 34,
                insideMargin: const EdgeInsets.symmetric(horizontal: 14),
                colors: MiuixButtonColors(
                  color: colors.error,
                  disabledColor: colors.error.withValues(alpha: 0.4),
                  contentColor: colors.onError,
                  disabledContentColor: colors.onError,
                ),
                child: const Text('删除节点'),
              ),
              const SizedBox(width: 8),
              MiuixButton(
                onPressed: _applyNodeSheet,
                minHeight: 34,
                insideMargin: const EdgeInsets.symmetric(horizontal: 14),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 连线样式面板(分支名/线色/粗细/删除)。
  Widget _buildConnSheet() {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Connection<dynamic>? c = _findConn(_connSheetId ?? '');
    if (c == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MiuixTextField(label: '分支名(批注)', controller: _labelCtrl),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              MiuixText(
                '线色',
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final int cc in _edgePalette)
                      _colorDot(
                        cc,
                        selected: _connColorSel == cc,
                        onTap: () => setState(() {
                          _connColorSel = _connColorSel == cc ? null : cc;
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              MiuixText(
                '粗细',
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 10),
              for (final double w in const <double>[1.5, 2.5, 3.5, 5.0])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _connWidthSel = _connWidthSel == w ? null : w;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _connWidthSel == w
                            ? colors.primary.withValues(alpha: 0.14)
                            : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: _connWidthSel == w
                            ? Border.all(color: colors.primary, width: 1)
                            : null,
                      ),
                      child: MiuixText(
                        '$w',
                        fontSize: 12,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              MiuixText(
                '箭头',
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 10),
              for (final (int v, String t) in const <(int, String)>[
                (0, '无'),
                (1, '单向'),
                (2, '双向'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _connArrow = v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _connArrow == v
                            ? colors.primary.withValues(alpha: 0.14)
                            : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: _connArrow == v
                            ? Border.all(color: colors.primary, width: 1)
                            : null,
                      ),
                      child: MiuixText(
                        t,
                        fontSize: 12,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              MiuixButton(
                onPressed: () => _deleteConn(c.id),
                minHeight: 34,
                insideMargin: const EdgeInsets.symmetric(horizontal: 14),
                colors: MiuixButtonColors(
                  color: colors.error,
                  disabledColor: colors.error.withValues(alpha: 0.4),
                  contentColor: colors.onError,
                  disabledContentColor: colors.onError,
                ),
                child: const Text('删除连线'),
              ),
              const SizedBox(width: 8),
              MiuixButton(
                onPressed: _applyConnSheet,
                minHeight: 34,
                insideMargin: const EdgeInsets.symmetric(horizontal: 14),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 色板圆点(0 = 默认恢复)。
  Widget _colorDot(
    int argb, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool isDefault = argb == 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: isDefault ? colors.surfaceContainerHigh : Color(argb),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.primary : colors.dividerLine,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: isDefault
            ? Center(
                child: Text(
                  '↺',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariantActions,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  String _taskTitle() {
    final List<TodoItem>? todos = ref.watch(todoListProvider).value;
    for (final TodoItem t in todos ?? const <TodoItem>[]) {
      if (t.id == widget.taskId) return t.title;
    }
    return '流程图';
  }

  @override
  Widget build(BuildContext context) {
    final FlowDoc? doc = _doc;
    // 宽屏/横屏(≥700):三段式(左 docked 工具 · 中画布 · 右详情)。
    final bool wide = MediaQuery.sizeOf(context).width >= 700;
    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: MiuixSmallTopAppBar(
        title: _taskTitle(),
        navigationIcon: _backButton,
      ),
      content: (padding) {
        final Widget canvasStack = _buildCanvasArea(context, doc, wide);
        final Widget body = doc == null || !wide
            ? canvasStack
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildToolbar(docked: true),
                    const SizedBox(width: 12),
                    Expanded(child: canvasStack),
                    // 右栏分隔条(桌面 hover 光标;拖拽调宽)。
                    _buildRightDivider(context),
                    SizedBox(
                      width: _rightPanelWidth,
                      child: _buildRightPanel(context),
                    ),
                  ],
                ),
              );
        return Stack(
          children: <Widget>[
            body,
            // 窄屏:节点详情/连线样式走弹层;宽屏走右栏(不弹)。
            if (!wide) ...<Widget>[
              MiuixOverlayDialog(
                show: _nodeSheetId != null,
                title: '节点详情',
                onDismissRequest: () => setState(() => _nodeSheetId = null),
                content: _buildNodeSheet(),
              ),
              MiuixOverlayDialog(
                show: _connSheetId != null,
                title: '连线样式',
                onDismissRequest: () => setState(() => _connSheetId = null),
                content: _buildConnSheet(),
              ),
            ],
            // 播放分支选路(判断多出口;两模式都弹)。
            MiuixOverlayDialog(
              show: _branchOpen,
              title: '选择分支',
              onDismissRequest: () => setState(() => _branchOpen = false),
              content: _buildBranchSheet(),
            ),
            // 图例(阶段2:节点语义/泳道/连线说明)。
            MiuixOverlayDialog(
              show: _legendOpen,
              title: '图例',
              onDismissRequest: () => setState(() => _legendOpen = false),
              content: _buildLegendSheet(),
            ),
          ],
        );
      },
    );
  }

  // ── 响应式布局(阶段3 批3-3:宽屏三段式)────────────────────────

  /// 画布区(编辑器 + 底部条(窄)或顶部悬浮条(宽)+ 窄屏 FAB)。
  Widget _buildCanvasArea(BuildContext context, FlowDoc? doc, bool wide) {
    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: doc == null
                  ? const SizedBox.shrink()
                  : _editorWidget(context, wide),
            ),
            if (!wide) ...<Widget>[
              if (_resizeNodeId != null) _buildResizeBar(context),
              if (_playing) _buildPlayBar(context),
            ],
          ],
        ),
        // 宽屏:播放/尺寸条顶部悬浮。
        if (wide && _playing)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: _buildPlayBarFloating(context)),
          ),
        if (wide && _resizeNodeId != null)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: _buildResizeBarFloating(context)),
          ),
        // 窄屏:右下悬浮 FAB(无底化后抬高留白,44 热区)。
        if (!wide && doc != null)
          Positioned(
            right: 14,
            bottom: 30,
            child: _buildToolbar(docked: false),
          ),
      ],
    );
  }

  /// C-48 v2 工具栏(窄屏 FAB / 宽屏 docked 常驻卡;同一实例 key)。
  Widget _buildToolbar({required bool docked}) {
    return C48FlowToolbarV2(
      key: _toolbarKey,
      docked: docked,
      visible: !_playing && _resizeNodeId == null,
      onAddNode: _addNode,
      onAddLane: () => _addNode(FlowNodeKind.lane),
      onUndo: _undoAction,
      onRedo: _redoAction,
      onDeleteSelected: _deleteSelected,
      onCopy: _copySelected,
      onPaste: _pasteClip,
      onFit: () => _ctrl?.fitToView(),
      onLegend: () => setState(() => _legendOpen = true),
      onPlay: _togglePlay,
      onExportHtml: _exportHtml,
      onToggleMiniMap: _toggleMiniMap,
      onToggleLod: _toggleLod,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
      hasClip: _clip != null,
      miniMapOn: _showMiniMap,
      lodOn: _lodOn,
      nodeCount: _ctrl?.nodes.length ?? 0,
    );
  }

  /// vyuh 编辑器(事件/主题/缩略图/尺寸把手统一装配)。
  Widget _editorWidget(BuildContext context, bool wide) {
    return VyuhFlowEditor(
      controller: _ctrl!,
      // 播放中 inspect:可平移缩放/选中查看,禁改禁拖。
      behavior:
          _playing ? NodeFlowBehavior.inspect : NodeFlowBehavior.design,
      showMinimap: _showMiniMap,
      resizeTargetId: _resizeNodeId,
      // 窄屏无底 FAB(right14/bottom30,44 高)时缩略图抬升避让。
      minimapBottomInset:
          !wide && _showMiniMap && !_playing && _resizeNodeId == null
          ? 82
          : 10,
      // 单击节点/连线 → 详情与样式面板;长按/右键与单击同路。
      events: NodeFlowEvents<FlowNodeData, dynamic>(
        node: NodeEvents<FlowNodeData>(
          // 尺寸编辑模式中:目标泳道点击不打开详情(平移画布不误触)。
          onTap: (Node<FlowNodeData> n) {
            if (_resizeNodeId == n.id) return;
            _openNodeSheet(n.id);
          },
          onContextMenu: (Node<FlowNodeData> n, ScreenPosition _) {
            if (_resizeNodeId == n.id) return;
            _openNodeSheet(n.id);
          },
        ),
        connection: ConnectionEvents(
          onTap: (Connection<dynamic> c) => _openConnSheet(c.id),
          // 拉线起点:锁定节点禁出线。
          onBeforeStart: (ConnectionStartContext<FlowNodeData> ctx) {
            final String? reason = denyConnectStart(
              sourceLocked: ctx.sourceNode.locked,
            );
            if (reason == null) {
              return const ConnectionValidationResult.allow();
            }
            showMiniToast(context, reason);
            return ConnectionValidationResult.deny(
              reason: reason,
              showMessage: false,
            );
          },
          // 落点校验:自环/同对重复/判断出口唯一。
          onBeforeComplete:
              (ConnectionCompleteContext<FlowNodeData> ctx) {
            final String? reason = denyConnect(
              sourceLocked: ctx.sourceNode.locked,
              targetLocked: ctx.targetNode.locked,
              isSelf: ctx.isSelfConnection,
              samePairExists: _hasPair(
                ctx.sourceNode.id,
                ctx.targetNode.id,
              ),
              sourceIsDecision:
                  ctx.sourceNode.data.kind == FlowNodeKind.decision,
            );
            if (reason == null) {
              return const ConnectionValidationResult.allow();
            }
            showMiniToast(context, reason);
            return ConnectionValidationResult.deny(
              reason: reason,
              showMessage: false,
            );
          },
        ),
        // 点画布空白:C-48 面板收起;宽屏同时关闭右栏详情。
        viewport: ViewportEvents(
          onCanvasTap: (GraphPosition _) {
            _toolbarKey.currentState?.collapse();
            if (wide) {
              setState(() {
                _nodeSheetId = null;
                _connSheetId = null;
              });
            }
          },
        ),
      ),
    );
  }

  /// 宽屏右栏拖拽分隔条(桌面可调宽 240-420;触摸可拖)。
  Widget _buildRightDivider(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: const ValueKey('p11v2.rightDivider'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _rightDragging = true),
        onHorizontalDragUpdate: (DragUpdateDetails d) {
          setState(() {
            _rightPanelWidth =
                (_rightPanelWidth - d.delta.dx).clamp(240.0, 420.0);
          });
        },
        onHorizontalDragEnd: (_) => setState(() => _rightDragging = false),
        onHorizontalDragCancel: () => setState(() => _rightDragging = false),
        child: Container(
          width: 14,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          color: _rightDragging
              ? colors.primary.withValues(alpha: 0.12)
              : null,
          child: Center(
            child: Container(
              width: 2,
              height: 48,
              decoration: BoxDecoration(
                color: _rightDragging
                    ? colors.primary
                    : colors.dividerLine.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 宽屏右栏:详情/属性面板(复用弹层内容;无选中时空态)。
  Widget _buildRightPanel(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final String? nodeId = _nodeSheetId;
    final String? connId = _connSheetId;
    final Widget? inner;
    final String? title;
    if (nodeId != null) {
      title = '节点详情';
      inner = _buildNodeSheet();
    } else if (connId != null) {
      title = '连线样式';
      inner = _buildConnSheet();
    } else {
      title = null;
      inner = null;
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: inner == null
          ? Center(
              child: MiuixText(
                '点选画布中的节点或连线,\n在这里查看与编辑',
                textAlign: TextAlign.center,
                fontSize: 12,
                height: 1.6,
                color: colors.onSurfaceVariantSummary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: MiuixText(
                    title ?? '',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(child: inner),
                ),
              ],
            ),
    );
  }

  /// 分支选路面板(候选线:分支名(默认 → 目标名))。
  Widget _buildBranchSheet() {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final NodeFlowController<FlowNodeData, dynamic>? c = _ctrl;
    if (c == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final String connId in _branchConnIds)
            Builder(
              builder: (BuildContext context) {
                Connection<dynamic>? conn;
                for (final Connection<dynamic> e in c.connections) {
                  if (e.id == connId) {
                    conn = e;
                    break;
                  }
                }
                if (conn == null) return const SizedBox.shrink();
                final String label =
                    conn.label?.text ?? (conn.data is FlowEdgeData
                        ? (conn.data as FlowEdgeData).label
                        : '');
                final String targetTitle =
                    c.nodes[conn.targetNodeId]?.data.title ?? '';
                return GestureDetector(
                  key: ValueKey<String>('branch.$connId'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pickBranch(connId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MiuixText(
                            label.isEmpty ? '→ $targetTitle' : '$label($targetTitle)',
                            fontSize: 14,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// 尺寸编辑操作条(模式激活时显示:提示 + 完成;窄屏底通栏)。
  Widget _buildResizeBar(BuildContext context) {
    return Container(
      key: const ValueKey('p11v2.resizeBar'),
      color: MiuixTheme.of(context).colors.primary.withValues(alpha: 0.1),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: _resizeBarRow(context),
        ),
      ),
    );
  }

  /// 尺寸编辑操作条(宽屏:顶部悬浮胶囊)。
  Widget _buildResizeBarFloating(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.primary, width: 1),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: _resizeBarRow(context),
    );
  }

  /// 尺寸条内容行(提示 + 完成)。
  Widget _resizeBarRow(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final String? id = _resizeNodeId;
    final String name = (id == null ? '' : _meta[id]?.title ?? '').trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: MiuixText(
            '调整尺寸中:${name.isEmpty ? '拖动边框/角' : '拖动「$name」边框/角'}',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        MiuixButton(
          key: const ValueKey('p11v2.resizeDone'),
          onPressed: _exitResizeMode,
          minHeight: 32,
          insideMargin: const EdgeInsets.symmetric(horizontal: 14),
          child: const Text(
            '完成',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  /// 播放条(窄屏:播放中显示于底部;步骤/自动/单步/速度/停止)。
  Widget _buildPlayBar(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Container(
      color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: _playBarRow(context),
        ),
      ),
    );
  }

  /// 播放条(宽屏:顶部悬浮胶囊,横向可滚动)。
  Widget _buildPlayBarFloating(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colors.outline.withValues(alpha: 0.2),
          width: 0.5,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _playBarRow(context),
      ),
    );
  }

  /// 播放条内容行(窄/宽共用)。
  Widget _playBarRow(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Row(
      children: <Widget>[
        MiuixText(
          _playDone ? '已结束 · 共 $_playStepCount 步' : '步骤 $_playStepCount',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        const SizedBox(width: 10),
        _playTool(
          _playAuto ? '自动:开' : '自动:关',
          () => _setPlayAuto(!_playAuto),
        ),
        _playTool('单步', _stepPlay),
        _playTool(_playSpeedLabel(), _cyclePlaySpeed),
        _playTool('停止', _togglePlay),
      ],
    );
  }

  Widget _playTool(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: MiuixButton(
          onPressed: onTap,
          minHeight: 30,
          insideMargin: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );

  /// 图例(阶段2):节点语义/泳道/连线方向说明。
  Widget _buildLegendSheet() {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final List<(Color, String, String)> rows = <(Color, String, String)>[
      (kindAccent(colors, FlowNodeKind.start), '开始', '流程入口,播放从这里开始'),
      (kindAccent(colors, FlowNodeKind.step), '步骤', '常规处理步骤(带序号)'),
      (kindAccent(colors, FlowNodeKind.decision), '判断', '条件分支,可多条出口(播放时选路)'),
      (kindAccent(colors, FlowNodeKind.end), '结束', '流程终点'),
      (kindAccent(colors, FlowNodeKind.lane), '泳道', '虚线分区:节点拖入/拖出自动归属;可拉伸'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (Color dot, String name, String desc) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 泳道用空心方框示意虚线分区,其余为实心圆点。
                  name == '泳道'
                      ? Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: dot, width: 1.6),
                          ),
                        )
                      : Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 3),
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    child: MiuixText(
                      name,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  Expanded(
                    child: MiuixText(
                      desc,
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Container(height: 1, color: colors.dividerLine),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MiuixText(
                '→',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kindAccent(colors, FlowNodeKind.step),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MiuixText(
                  '连线带三角箭头表示方向;点击连线可改分支名/颜色/粗细/箭头',
                  fontSize: 12,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 图事件 → 自动保存/撤销快照(白名单过滤视口/选择类;
/// 批量操作内静默,仅 BatchEnded 落一次保存+快照)。
class _DirtyPlugin extends NodeFlowPlugin {
  _DirtyPlugin(this.onDirty, this.onSnap);

  final VoidCallback onDirty;
  final VoidCallback onSnap;

  int _batchDepth = 0;

  @override
  String get id => 'p11v2-autosave';

  @override
  void attach(NodeFlowController controller) {}

  @override
  void detach() {}

  @override
  void onEvent(GraphEvent event) {
    final String type = event.runtimeType.toString();
    if (type == 'BatchStarted') {
      _batchDepth++;
      return;
    }
    if (type == 'BatchEnded') {
      if (_batchDepth > 0) _batchDepth--;
      if (_batchDepth == 0) {
        onDirty();
        onSnap();
      }
      return;
    }
    if (_batchDepth > 0) return; // 批量内中间事件静默。
    if (_PageP11V2FlowEditorPageState._saveEvents.contains(type)) {
      onDirty();
      onSnap();
    }
  }
}
