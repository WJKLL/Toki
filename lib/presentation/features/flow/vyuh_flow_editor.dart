// lib/presentation/features/flow/vyuh_flow_editor.dart
// 编号:P-11 v2 域 —— vyuh 编辑器渲染组件(受控模式)
// 说明:
//   - controller 由页面(宿主)创建/持有/释放;本组件只负责渲染与主题;
//   - controller 实例变化(整图重建)时经 key 重建 NodeFlowEditor ——
//     vyuh editor 仅在 initState 对 controller 完整初始化(空间索引/相机/
//     screenSize),in-place 替换会错位,故一律整树重建;
//   - theme 每次 build 按 Miuix 实时取色;Miuix 深浅/Monet 切换 → 本组件
//     rebuild(依赖 MiuixTheme)→ NodeFlowEditor didUpdateWidget 同步
//     controller.updateTheme(库内建),画布即时换肤不丢视口;
//   - 节点经 Node.widgetBuilder 自渲染;业务(增删/样式/批注/自动保存)
//     全部走宿主 controller + 事件;
//   - showMinimap:缩略图 overlay(右下,主题实时取色,点击/拖动导航)。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../domain/entities/flow_doc.dart';
import 'vyuh_flow_theme.dart';

/// vyuh 流程图编辑器(受控:controller 由宿主传入)。
class VyuhFlowEditor extends StatefulWidget {
  const VyuhFlowEditor({
    super.key,
    required this.controller,
    this.behavior = NodeFlowBehavior.design,
    this.events,
    this.showMinimap = false,
    this.resizeTargetId,
    this.minimapBottomInset = 10,
  });

  /// 图控制器(宿主持有;变化时组件整树重建)。
  final NodeFlowController<FlowNodeData, dynamic> controller;

  /// 行为模式(design=编辑;inspect=播放禁改;present=纯展示)。
  final NodeFlowBehavior behavior;

  /// 画布事件(节点单击/右键/连线单击;宿主业务接入点)。
  final NodeFlowEvents<FlowNodeData, dynamic>? events;

  /// 右下缩略图(阶段2;Miuix 主题实时取色;点击/拖动导航)。
  final bool showMinimap;

  /// 尺寸编辑目标节点 id(阶段2 fix;非空 = 该节点上渲染宿主大把手
  /// overlay —— 触摸命中 100% 可靠,拖动走 controller resize API)。
  final String? resizeTargetId;

  /// 缩略图离底部间距(阶段3:C-48 悬浮 FAB 占用右下时抬升避开)。
  final double minimapBottomInset;

  @override
  State<VyuhFlowEditor> createState() => VyuhFlowEditorState();
}

class VyuhFlowEditorState extends State<VyuhFlowEditor> {
  late NodeFlowController<FlowNodeData, dynamic> _current;

  @override
  void initState() {
    super.initState();
    _current = widget.controller;
  }

  @override
  void didUpdateWidget(VyuhFlowEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      // 整图重建:key 变化 → NodeFlowEditor 全新 State(完整初始化)。
      _current = widget.controller;
    }
    // behavior/events 由 NodeFlowEditor 自身 didUpdateWidget 处理。
  }

  @override
  Widget build(BuildContext context) {
    final double miniSize =
        MediaQuery.sizeOf(context).width >= 700 ? 200.0 : 132.0;
    return Container(
      color: vyuhFlowTheme(context).backgroundColor,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: NodeFlowEditor<FlowNodeData, dynamic>(
              key: ValueKey<Object>(_current), // 换 controller → 整树重建。
              controller: _current,
              theme: vyuhFlowTheme(context),
              // 节点均经 Node.widgetBuilder 自渲染,此处占位。
              nodeBuilder: (BuildContext c2, Node<FlowNodeData> n) =>
                  const SizedBox.shrink(),
              events: widget.events,
              behavior: widget.behavior,
            ),
          ),
          // 缩略图(编辑/播放均可导航;右下留边;FAB 出现时抬升避开)。
          if (widget.showMinimap)
            Positioned(
              right: 10,
              bottom: widget.minimapBottomInset,
              child: NodeFlowMinimap<FlowNodeData>(
                controller: _current,
                size: Size(miniSize, miniSize * 0.72),
                theme: vyuhMinimapTheme(context),
                interactive: true,
              ),
            ),
          // 尺寸编辑大把手 overlay(目标节点 8 个把手:4 角方块 + 4 边条;
          // 触摸命中可靠,阻断下层 InteractiveViewer 无手势竞争)。
          if (widget.resizeTargetId != null)
            Positioned.fill(
              child: _ResizeHandlesOverlay(
                controller: _current,
                nodeId: widget.resizeTargetId!,
              ),
            ),
        ],
      ),
    );
  }
}

/// 宿主尺寸编辑把手 overlay(阶段2 fix)。
///
/// 背景:库 ResizerWidget 把手在真机触摸下不可靠(触摸拖动在编辑器
/// InteractiveViewer 手势体系外),模式中由本 overlay 全权接管:
/// - 在编辑器之上渲染目标节点 8 个放大把手(角 52px / 边条 36px),
///   命中即阻断下层(无手势竞争,触摸 pan 正常触发);
/// - 拖动直接调 controller.startResize/updateResize/endResize(公开 API,
///   与库把手同语义:绝对定位/最小尺寸/画布锁/ResizeEnded 事件);
/// - 位置经 viewport.toScreen 每帧跟随(zoom/pan/node 移动/拉伸都同步)。
class _ResizeHandlesOverlay extends StatelessWidget {
  const _ResizeHandlesOverlay({
    required this.controller,
    required this.nodeId,
  });

  final NodeFlowController<FlowNodeData, dynamic> controller;
  final String nodeId;

  static const double _corner = 52; // 角把手命中/视觉尺寸。
  static const double _edgeThick = 36; // 边条厚度(骑在边框上,半内半外)。

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (BuildContext _) {
        final Node<FlowNodeData>? node = controller.nodes[nodeId];
        if (node == null) return const SizedBox.shrink();
        final NodeFlowTheme theme =
            controller.theme ?? NodeFlowTheme.light;
        final Rect r = _screenRect(node);
        if (r.isEmpty || r.width < 40 || r.height < 40) {
          return const SizedBox.shrink();
        }
        // 角把手(4):图矩形可视四角。
        final List<(ResizeHandle, Offset)> corners = <(ResizeHandle, Offset)>[
          (ResizeHandle.topLeft, r.topLeft),
          (ResizeHandle.topRight, r.topRight),
          (ResizeHandle.bottomLeft, r.bottomLeft),
          (ResizeHandle.bottomRight, r.bottomRight),
        ];
        // 边条(4):骑在可视四边中段(避开角)。
        final double innerW = (r.width - _corner).clamp(0, double.infinity);
        final double innerH = (r.height - _corner).clamp(0, double.infinity);
        final List<Widget> children = <Widget>[
          // 上/下边条(横,厚 36,中心贴边,宽 = 可视宽 - 2×角半)。
          _edgeBar(
            context,
            theme: theme,
            handle: ResizeHandle.topCenter,
            rect: Rect.fromLTWH(
              r.left + _corner / 2,
              r.top - _edgeThick / 2,
              innerW,
              _edgeThick,
            ),
          ),
          _edgeBar(
            context,
            theme: theme,
            handle: ResizeHandle.bottomCenter,
            rect: Rect.fromLTWH(
              r.left + _corner / 2,
              r.bottom - _edgeThick / 2,
              innerW,
              _edgeThick,
            ),
          ),
          // 左/右边条(竖)。
          _edgeBar(
            context,
            theme: theme,
            handle: ResizeHandle.centerLeft,
            rect: Rect.fromLTWH(
              r.left - _edgeThick / 2,
              r.top + _corner / 2,
              _edgeThick,
              innerH,
            ),
          ),
          _edgeBar(
            context,
            theme: theme,
            handle: ResizeHandle.centerRight,
            rect: Rect.fromLTWH(
              r.right - _edgeThick / 2,
              r.top + _corner / 2,
              _edgeThick,
              innerH,
            ),
          ),
          // 角方块(压边条之上)。
          for (final (ResizeHandle h, Offset c) in corners)
            Positioned(
              left: c.dx - _corner / 2,
              top: c.dy - _corner / 2,
              child: _cornerHandle(context, theme, h),
            ),
        ];
        return Stack(
          clipBehavior: Clip.none,
          children: children,
        );
      },
    );
  }

  /// 节点可视矩形(图矩形两角经 viewport 投影;缩放各向同性保持轴对齐)。
  Rect _screenRect(Node<FlowNodeData> node) {
    final GraphViewport viewport = controller.viewport;
    final Offset p = node.position.value;
    final Size sz = node.size.value;
    final Offset a =
        viewport.toScreen(GraphPosition(p)).offset;
    final Offset b =
        viewport.toScreen(GraphPosition(p + Offset(sz.width, sz.height))).offset;
    return Rect.fromPoints(a, b);
  }

  Widget _edgeBar(
    BuildContext context, {
    required NodeFlowTheme theme,
    required ResizeHandle handle,
    required Rect rect,
  }) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: _handleGesture(
        theme: theme,
        handle: handle,
        bar: true,
        child: Container(
          decoration: BoxDecoration(
            color: theme.nodeTheme.selectedBorderColor
                .withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(_edgeThick / 2),
            border: Border.all(
              color: theme.nodeTheme.selectedBorderColor,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cornerHandle(
    BuildContext context,
    NodeFlowTheme theme,
    ResizeHandle handle,
  ) {
    return _handleGesture(
      theme: theme,
      handle: handle,
      child: Container(
        width: _corner,
        height: _corner,
        decoration: BoxDecoration(
          color: theme.nodeTheme.selectedBorderColor.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.backgroundColor,
            width: 2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.arrow_outward,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// 把手手势:pan 直接驱动 controller resize(绝对定位;含画布锁/
  /// ResizeEnded;dragStartBehavior.down 触摸零延迟)。
  Widget _handleGesture({
    required NodeFlowTheme theme,
    required ResizeHandle handle,
    required Widget child,
    bool bar = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (DragStartDetails d) =>
          controller.startResize(nodeId, handle, d.globalPosition),
      onPanUpdate: (DragUpdateDetails d) =>
          controller.updateResize(d.globalPosition),
      onPanEnd: (_) => controller.endResize(),
      onPanCancel: controller.endResize,
      child: child,
    );
  }
}
