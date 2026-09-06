import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../editor/controller/node_flow_controller.dart';
import '../editor/drag_session.dart';
import '../editor/element_scope.dart';
import '../editor/resizer_widget.dart';
import '../editor/themes/cursor_theme.dart';
import '../editor/themes/node_flow_theme.dart';
import '../editor/unbounded_widgets.dart';
import '../graph/coordinates.dart';
import '../plugins/autopan/auto_pan_plugin.dart';
import '../plugins/lod/detail_visibility.dart';
import '../plugins/lod/lod_plugin.dart';
import '../ports/port.dart';
import '../ports/port_widget.dart';
import 'node.dart';
import 'node_shape.dart';

/// A container widget that handles the structural/positioning aspects of a node.
///
/// This widget is responsible for:
/// - Positioning the node at its visual position
/// - Sizing the node based on its size observable
/// - Handling gesture callbacks (tap, drag, context menu, hover)
/// - Rendering ports at appropriate positions
/// - Rendering resize handles when selected and resizable
///
/// The [child] widget is injected and represents the visual content of the node,
/// which is typically built by [NodeWidget].
///
/// This separation allows for:
/// - Cleaner dual-layer optimization (static vs active layers)
/// - Better separation of concerns
/// - Easier creation of proxy nodes for smooth drag rendering
class NodeContainer<T> extends StatelessWidget {
  const NodeContainer({
    super.key,
    required this.node,
    required this.controller,
    required this.child,
    this.shape,
    this.portBuilder,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.onMouseEnter,
    this.onMouseLeave,
    this.onPortTap,
    this.onPortHover,
    this.onPortContextMenu,
    /// POC vendor 补丁(0.2.0):端口命中热区 8→24 —— 触摸手指瞄准小端口
  /// 更宽容,松手吸附也更容易命中。
  this.portSnapDistance = 24.0,
  });

  /// The node data model.
  final Node<T> node;

  /// The controller for node operations.
  final NodeFlowController<T, dynamic> controller;

  /// The visual content of the node (built by NodeWidget or custom builder).
  final Widget child;

  /// Optional shape for the node (used for port positioning).
  final NodeShape? shape;

  /// Optional builder for customizing individual port widgets.
  final PortBuilder<T>? portBuilder;

  /// Callback invoked when the node is tapped.
  final VoidCallback? onTap;

  /// Callback invoked when the node is double-tapped.
  final VoidCallback? onDoubleTap;

  /// Callback invoked when the node is right-clicked (context menu).
  final void Function(ScreenPosition screenPosition)? onContextMenu;

  /// Callback invoked when the mouse enters the node bounds.
  final VoidCallback? onMouseEnter;

  /// Callback invoked when the mouse leaves the node bounds.
  final VoidCallback? onMouseLeave;

  /// Callback invoked when a port is tapped.
  final void Function(String nodeId, String portId, bool isOutput)? onPortTap;

  /// Callback invoked when a port hover state changes.
  final void Function(String nodeId, String portId, bool isHover)? onPortHover;

  /// Callback invoked when a port is right-clicked (context menu).
  final void Function(
    String nodeId,
    String portId,
    ScreenPosition screenPosition,
  )?
  onPortContextMenu;

  /// Distance around ports that expands the hit area for easier targeting.
  final double portSnapDistance;

  @override
  Widget build(BuildContext context) {
    final theme = controller.theme ?? NodeFlowTheme.light;

    return Observer(
      builder: (context) {
        // Check visibility first - return nothing if hidden
        if (!node.isVisible) {
          return const SizedBox.shrink();
        }

        // Use visual position for rendering
        final position = node.visualPosition.value;
        final size = node.size.value;

        // Get LOD visibility state - default to full visibility if not configured
        final lodVisibility =
            controller.lod?.currentVisibility ?? DetailVisibility.full;

        // POC vendor 补丁(v0.1.5,拖动保活):选中态依赖仅在"可缩放节点"上
        // 生效 —— 先读 isResizable 短路,普通节点(不可缩放)不因 isSelected
        // 变化重建本容器。否则 down 即选中 → 容器 Observer 重建 →
        // ElementScope/RawGestureDetector 识别器重建 → 刚注册的拖动指针被
        // dispose,触摸/鼠标拖动永不触发(onStart 丢失)。选中蓝框由节点
        // 自渲染卡(内部 Observer)负责,不依赖本容器重建。
        // POC vendor 补丁(v0.4.1 阶段2 尺寸编辑模式):模式中目标节点禁整体
        // 拖动(见 _buildElementScope),把手由宿主 overlay 提供(库把手
        // 保持仅选中显示,避免与 overlay 双份)。
        final bool resizeMode =
            controller.resizeOnlyNodeId == node.id;
        final showResizer =
            node.isResizable &&
            !node.locked && // POC vendor 补丁(v0.3.0 阶段2):锁定节点禁拉伸。
            !resizeMode && // 尺寸编辑模式:宿主 overlay 大把手全权。
            node.isSelected &&
            lodVisibility.showResizeHandles &&
            controller.behavior.canUpdate;

        return Positioned(
          left: position.dx,
          top: position.dy,
          child: UnboundedSizedBox(
            width: size.width,
            height: size.height,
            child: UnboundedStack(
              clipBehavior: Clip.none, // Allow ports/handles to overflow
              children: [
                // Main node visual with gesture handling via ElementScope
                Positioned.fill(child: _buildElementScope(theme)),

                // Ports (only when LOD allows and ports exist)
                // Iterate over all ports directly to avoid duplicate rendering
                // when a port has PortType.both (would appear in both inputPorts and outputPorts)
                if (lodVisibility.showPorts && node.ports.isNotEmpty)
                  ...node.ports.map(
                    (port) => _buildPort(context, port, port.isOutput),
                  ),

                // Resize handles (shown when selected and resizable)
                if (showResizer) Positioned.fill(child: _buildResizer(theme)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds the interaction shell separately from the node's structural
  /// observer. Global interaction state changes frequently, but only the cursor
  /// and drag eligibility depend on it. Keeping those reads here prevents a
  /// cursor-only change from rebuilding node layout, ports, and resize handles.
  Widget _buildElementScope(NodeFlowTheme theme) {
    return Observer(
      builder: (context) {
        final cursor = theme.cursorTheme.cursorFor(
          ElementType.node,
          controller.interaction,
          isLocked: node.locked,
        );

        return ElementScope(
          // Session for canvas locking during drag
          createSession: () =>
              controller.createSession(DragSessionType.nodeDrag),
          // Drag lifecycle - unified for all node types
          // Check both node lock state AND behavior mode.
          // POC vendor 补丁(v0.4.1 阶段2 尺寸编辑模式):目标节点禁整体拖动
          // (触摸路由/鼠标 pan 均关闭,拖动判定只留给 resize 把手)。
          isDraggable: !node.locked &&
              controller.behavior.canDrag &&
              controller.resizeOnlyNodeId != node.id,
          onDragStart: (_) => controller.startNodeDrag(node.id),
          onDragUpdate: (details) => controller.moveNodeDrag(details.delta),
          onDragEnd: (_) => controller.endNodeDrag(),
          // Interaction callbacks
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onContextMenu: onContextMenu,
          // POC vendor 补丁(v0.5.0 阶段3 hover):鼠标悬停驱动节点 hover 态
          // (仅鼠标 MouseRegion;触摸不触发)。
          onMouseEnter: () {
            controller.setHoverNode(node.id);
            onMouseEnter?.call();
          },
          onMouseLeave: () {
            controller.setHoverNode(null);
            onMouseLeave?.call();
          },
          cursor: cursor,
          // Background/foreground layers use translucent for hit testing
          hitTestBehavior: HitTestBehavior.opaque,
          // POC(0.2.1):拖动中第二指 → 平移画布(内容跟手)。
          onViewportPan: (Offset contentDelta) {
            controller.panBy(
              ScreenOffset(
                Offset(-contentDelta.dx, -contentDelta.dy),
              ),
            );
          },
          // Autopan configuration
          autoPan: controller.autoPan,
          getViewportBounds: () => controller.viewportScreenBounds.rect,
          onAutoPan: (delta) {
            final zoom = controller.viewport.zoom;
            controller.panBy(
              ScreenOffset(Offset(-delta.dx * zoom, -delta.dy * zoom)),
            );
          },
          child: child,
        );
      },
    );
  }

  /// Isolates resize interaction updates from the node structure and ports.
  Widget _buildResizer(NodeFlowTheme theme) {
    return Observer(
      builder: (context) => ResizerWidget(
        handleSize: theme.resizerTheme.handleSize,
        color: theme.resizerTheme.color,
        borderColor: theme.resizerTheme.borderColor,
        borderWidth: theme.resizerTheme.borderWidth,
        snapDistance: theme.resizerTheme.snapDistance,
        isResizing: controller.interaction.isResizing,
        onResizeStart: (handle, globalPos) =>
            controller.startResize(node.id, handle, globalPos),
        onResizeUpdate: (globalPos) => controller.updateResize(globalPos),
        onResizeEnd: () => controller.endResize(),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildPort(BuildContext context, Port port, bool isOutput) {
    final theme = controller.theme ?? NodeFlowTheme.light;
    final portTheme = theme.portTheme;
    final isConnected = controller.isPortConnected(node.id, port.id);

    // Get the visual position from the Node model
    final effectivePortSize = port.size ?? portTheme.size;
    final visualPosition = node.getVisualPortOrigin(
      port.id,
      portSize: effectivePortSize,
      shape: shape,
    );

    // Calculate node bounds for port positioning
    final nodeBounds = Rect.fromLTWH(
      node.position.value.dx,
      node.position.value.dy,
      node.size.value.width,
      node.size.value.height,
    );

    // Port widget cascade:
    // 1. port.buildWidget (per-instance builder)
    // 2. portBuilder (global editor builder)
    // 3. PortWidget (framework default)
    final portWidget =
        port.buildWidget(context, node) ??
        (portBuilder != null
            ? portBuilder!(context, node, port)
            : PortWidget<T>(
                port: port,
                theme: portTheme,
                isConnected: isConnected,
                snapDistance: port.isConnectable ? portSnapDistance : 0,
                controller: controller,
                nodeId: node.id,
                isOutput: isOutput,
                nodeBounds: nodeBounds,
                onTap: onPortTap != null
                    ? (p) => onPortTap!(node.id, p.id, isOutput)
                    : null,
                onHover: onPortHover != null
                    ? (data) => onPortHover!(node.id, data.$1.id, data.$2)
                    : null,
                onContextMenu: onPortContextMenu != null
                    ? (pos) => onPortContextMenu!(node.id, port.id, pos)
                    : null,
              ));

    return Positioned(
      key: ValueKey(port.id),
      left: visualPosition.dx,
      top: visualPosition.dy,
      child: portWidget,
    );
  }
}
