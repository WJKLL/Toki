import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../graph/coordinates.dart';
import '../poc_debug.dart'; // POC 埋点(阶段 1 移除)
import '../plugins/autopan/auto_pan_plugin.dart';
import 'auto_pan/auto_pan_mixin.dart';
import 'drag_session.dart';
import 'non_trackpad_pan_gesture_recognizer.dart';

/// A unified interaction scope for draggable elements (nodes, ports).
///
/// This widget provides consistent gesture handling and drag lifecycle management
/// across all interactive elements in the node flow editor. It solves the problem
/// of gesture recognizer callbacks not firing when widgets rebuild during drag
/// operations (due to MobX Observer rebuilds).
///
/// ## Key Features
///
/// 1. **StatefulWidget Architecture**: The State object persists across widget
///    rebuilds, maintaining drag state even when the parent Observer rebuilds.
///
/// 2. **Local Drag Tracking**: Uses `_isDragging` to track whether this widget
///    instance started a drag, preventing duplicate start/end calls.
///
/// 3. **Dispose Cleanup**: If the widget is removed while dragging (e.g., element
///    deleted), `dispose()` ensures proper cleanup by calling `onDragEnd`.
///
/// 4. **Guard Clauses**: All drag methods check `_isDragging` state to prevent
///    invalid operations (double-start, end without start, etc.).
///
/// 5. **Pointer ID Tracking**: Tracks which pointer started the drag to prevent
///    interference from other pointers (e.g., trackpad taps during mouse drag).
///
/// ## Gesture Handling
///
/// Uses [RawGestureDetector] with [NonTrackpadPanGestureRecognizer] to:
/// - Handle mouse/touch drag gestures
/// - Reject trackpad gestures (allowing them to bubble up for canvas panning)
/// - Support double-tap and context menu (right-click) gestures
///
/// ## Widget Tree Structure
///
/// ```
/// ElementScope (StatefulWidget)
/// └── Listener (immediate tap feedback, pointer ID tracking)
///     └── RawGestureDetector (drag, double-tap, context menu)
///         └── MouseRegion (cursor, hover callbacks)
///             └── child (provided by parent)
/// ```
///
/// ## Example Usage
///
/// For element movement (nodes):
/// ```dart
/// ElementScope(
///   onDragStart: (_) => controller.startNodeDrag(nodeId),
///   onDragUpdate: (details) => controller.moveNodeDrag(details.delta),
///   onDragEnd: (_) => controller.endNodeDrag(),
///   onTap: () => controller.selectNode(nodeId),
///   cursor: SystemMouseCursors.grab,
///   child: NodeVisual(...),
/// )
/// ```
///
/// For connection creation (ports):
/// ```dart
/// ElementScope(
///   onDragStart: (details) => controller.startConnection(details.globalPosition),
///   onDragUpdate: (details) => controller.updateConnection(details.globalPosition),
///   onDragEnd: (details) => controller.completeConnection(),
///   dragStartBehavior: DragStartBehavior.down, // Start immediately on pointer down
///   child: PortVisual(...),
/// )
/// ```
///
/// ## Autopan Support
///
/// When [autoPan] is provided and enabled, the widget automatically pans the
/// viewport when the pointer approaches the edges during a drag operation.
/// The element moves with the viewport during autopan.
///
/// ```dart
/// ElementScope(
///   onDragStart: (_) => controller.startNodeDrag(nodeId),
///   onDragUpdate: (details) => controller.moveNodeDrag(details.delta),
///   onDragEnd: (_) => controller.endNodeDrag(),
///   // Enable autopan via the controller's autopan extension
///   autoPan: controller.autoPan,
///   getViewportBounds: () => controller.viewportScreenBounds.rect,
///   onAutoPan: (delta) {
///     // Pan viewport - ElementScope also calls onDragUpdate to move element
///     final zoom = controller.viewport.zoom;
///     controller.panBy(ScreenOffset(Offset(-delta.dx * zoom, -delta.dy * zoom)));
///   },
///   child: NodeVisual(...),
/// )
/// ```
///
/// See also:
/// - [NodeWidget] which uses this for node interactions
/// - [PortWidget] which uses this for connection creation
class ElementScope extends StatefulWidget {
  /// Creates an element scope with the specified interaction callbacks.
  ///
  /// The [onDragStart], [onDragUpdate], and [onDragEnd] callbacks are required
  /// and form the core drag lifecycle. Other callbacks are optional.
  const ElementScope({
    super.key,
    required this.child,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onDragCancel,
    this.createSession,
    this.isDraggable = true,
    // POC vendor 补丁(触摸优先):默认 down —— 触摸/鼠标按下元素即赢得
    // 手势竞技场,否则画布 InteractiveViewer 单指平移抢先,移动端节点
    // 拖不动。阶段 1 复核。
    this.dragStartBehavior = DragStartBehavior.down,
    // POC vendor 补丁(0.2.0,触摸体验):小元素(端口)按下即开始拖动,
    // 不做位移阈值判定 —— 点端口即拉线,跟手零延迟。
    this.instantManualTouch = false,
    // POC vendor 补丁(0.2.1,触摸体验):拖动中第二指 → 画布平移回调。
    this.onViewportPan,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.onMouseEnter,
    this.onMouseLeave,
    this.cursor,
    this.hitTestBehavior = HitTestBehavior.opaque,
    // Autopan parameters
    this.autoPan,
    this.onAutoPan,
    this.getViewportBounds,
    this.screenToGraph,
  });

  /// The child widget to wrap with interaction handling.
  ///
  /// This is typically the visual representation of the element.
  final Widget child;

  /// Whether this element can be dragged.
  ///
  /// When false, the drag gesture recognizer is not registered, allowing
  /// drag events to pass through to underlying elements.
  final bool isDraggable;

  /// Determines when a drag gesture formally starts.
  ///
  /// - [DragStartBehavior.down] (default, POC vendor): Drag starts immediately
  ///   on pointer down.
  ///
  /// - [DragStartBehavior.start]: Drag starts after the pointer has moved
  ///   beyond the drag threshold.
  final DragStartBehavior dragStartBehavior;

  /// POC vendor 补丁(0.2.0,触摸体验):true = 触摸按下立即开始拖动
  /// (不等位移阈值)—— 用于端口等小元素(点即拉线,零延迟)。
  final bool instantManualTouch;

  /// POC vendor 补丁(0.2.1,触摸体验):双指平移画布回调。
  /// 元素拖动中第二指落下 → 结束拖动并进入平移模式,回调收到"内容跟手
  /// 方向"的屏幕位移(手指右移 → 正值);宿主负责换算为视口平移。
  final void Function(Offset contentDelta)? onViewportPan;

  /// Called when a drag operation starts.
  ///
  /// Receives [DragStartDetails] with the start position. Use this to:
  /// - Set the dragged element ID in the controller
  /// - Select the element if not already selected
  /// - Disable canvas panning
  /// - Calculate connection start point (for ports)
  final void Function(DragStartDetails details) onDragStart;

  /// Called during drag with update details.
  ///
  /// Receives [DragUpdateDetails] containing:
  /// - [delta]: Movement since last update (useful for element movement)
  /// - [globalPosition]: Current pointer position (useful for connections)
  /// - [localPosition]: Position relative to this widget
  final void Function(DragUpdateDetails details) onDragUpdate;

  /// Called when a drag operation ends normally.
  ///
  /// Receives [DragEndDetails] with velocity information. Use this to:
  /// - Clear the dragged element ID
  /// - Re-enable canvas panning
  /// - Complete connections (for ports)
  final void Function(DragEndDetails details) onDragEnd;

  /// Called when a drag operation is cancelled.
  ///
  /// This is called instead of [onDragEnd] when:
  /// - The gesture recognizer cancels the gesture
  /// - The widget is disposed mid-drag
  /// - The pointer up handler detects the original pointer released
  ///
  /// If null, [onDragEnd] is called with empty [DragEndDetails] as a fallback.
  final VoidCallback? onDragCancel;

  /// Factory function to create a [DragSession] for this element.
  ///
  /// When provided, ElementScope manages the session lifecycle:
  /// - On drag start: calls [createSession], then [DragSession.start] (locks canvas)
  /// - On drag end: calls [DragSession.end] (unlocks canvas)
  /// - On drag cancel: calls [DragSession.cancel] (unlocks canvas)
  ///
  /// Elements manage their own business state (positions, sizes) internally.
  /// The session purely handles canvas lock coordination.
  ///
  /// Example:
  /// ```dart
  /// ElementScope(
  ///   createSession: () => controller.createSession(),
  ///   onDragStart: (_) => controller.startNodeDrag(nodeId),
  ///   onDragUpdate: (details) => controller.moveNodeDrag(details.delta),
  ///   onDragEnd: (_) => controller.endNodeDrag(),
  ///   // ... other callbacks
  /// )
  /// ```
  final DragSession Function()? createSession;

  /// Called when the element is tapped.
  ///
  /// Fires immediately on pointer down (before gesture arena resolution)
  /// for instant selection feedback.
  final VoidCallback? onTap;

  /// Called when the element is double-tapped.
  final VoidCallback? onDoubleTap;

  /// Called when the element is right-clicked (context menu).
  ///
  /// Receives the screen position for showing a context menu.
  final void Function(ScreenPosition screenPosition)? onContextMenu;

  /// Called when the mouse enters the element bounds.
  final VoidCallback? onMouseEnter;

  /// Called when the mouse leaves the element bounds.
  final VoidCallback? onMouseLeave;

  /// The cursor to display when hovering over the element.
  ///
  /// If null, [MouseCursor.defer] is used.
  final MouseCursor? cursor;

  /// How to behave during hit testing.
  ///
  /// Defaults to [HitTestBehavior.opaque] which captures all events within bounds.
  /// Use [HitTestBehavior.translucent] if you need events to pass through.
  final HitTestBehavior hitTestBehavior;

  // ---------------------------------------------------------------------------
  // Autopan Parameters
  // ---------------------------------------------------------------------------

  /// The autopan plugin for autopan behavior during drag operations.
  ///
  /// When provided (non-null) and enabled, autopan is active. The viewport will
  /// automatically pan when the pointer approaches the edges during a drag.
  ///
  /// Requires [onAutoPan] and [getViewportBounds] to also be provided.
  final AutoPanPlugin? autoPan;

  /// Callback invoked when autopan triggers during a drag.
  ///
  /// Receives the pan delta in graph units. The parent should:
  /// 1. Pan the viewport by this delta (converted to screen units with zoom)
  /// 2. Move the dragged element by this delta to maintain cursor position
  ///
  /// Required when [autoPan] is provided.
  final void Function(Offset delta)? onAutoPan;

  /// Returns the current viewport bounds in screen coordinates.
  ///
  /// Used to determine when the pointer is within the edge padding zone.
  /// Required when [autoPan] is provided.
  final Rect Function()? getViewportBounds;

  /// Converts a screen position to graph coordinates.
  ///
  /// When provided, enables absolute positioning mode where the element
  /// position is calculated directly from the pointer's graph position.
  /// This prevents offset accumulation issues that can occur with delta-based
  /// positioning.
  ///
  /// Example:
  /// ```dart
  /// screenToGraph: (screenPos) => controller.screenToGraph(screenPos).offset,
  /// ```
  final Offset Function(Offset screenPosition)? screenToGraph;

  @override
  State<ElementScope> createState() => _ElementScopeState();
}

class _ElementScopeState extends State<ElementScope> with AutoPanMixin {
  /// Local drag state - tracks whether THIS widget instance started a drag.
  ///
  /// This is the source of truth for drag lifecycle within this widget.
  /// It persists across Observer rebuilds because State objects survive
  /// widget rebuilds (as long as widget type and key match).
  bool _isDragging = false;

  /// The pointer ID that started the current drag.
  ///
  /// Used to ensure we only end the drag when the SAME pointer that started
  /// it ends. This prevents premature drag termination when other pointers
  /// (like trackpad gestures) end while the drag is active.
  int? _dragPointerId;

  /// The pointer ID captured from onPointerDown, used for _startDrag.
  ///
  /// Since DragStartDetails doesn't contain the pointer ID, we capture it
  /// from the Listener's onPointerDown (which fires immediately) and use
  /// it when the gesture recognizer's onStart fires (after gesture arena).
  int? _pendingPointerId;

  /// POC 补丁(v0.1.5):单击(pending tap)是否待定 —— down 不再立即触发
  /// onTap(选中),改在 up 且未发生拖动时触发:否则 down 即选中会触发
  /// 节点容器重建,在拖动手势识别前销毁 pan recognizer(触摸拖不动根因)。
  bool _pendingTap = false;

  /// POC 补丁(0.2.0):触摸长按已触发(长按后抬手不再当作单击/拖动)。
  bool _longPressFired = false;

  /// POC 补丁(v0.1.6→0.1.9,触摸手动拖动):触摸下 pan 识别器在竞技场从不
  /// 触发,改由全局 pointer 路由手动驱动拖动(不依赖命中:小元素如端口
  /// 移出自身区域后仍持续跟手)。仅 PointerDeviceKind.touch 走此通道;
  /// 鼠标仍走原 recognizer。
  int? _manualPointerId;
  Offset? _manualDownPos;

  /// POC 补丁(0.2.1):双指平移模式状态。
  int? _panPointerId;
  Offset? _panLast;

  /// The current drag session, if any.
  ///
  /// Created via [ElementScope.createSession] at drag start, manages canvas
  /// locking/unlocking automatically.
  DragSession? _session;

  // ---------------------------------------------------------------------------
  // AutoPanMixin Implementation
  // ---------------------------------------------------------------------------

  @override
  bool get isDragging => _isDragging;

  @override
  void dispose() {
    // Stop autopan timer before other cleanup (from mixin)
    stopAutoPan();
    // POC:清理全局触摸路由。
    if (_manualPointerId != null || _panPointerId != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onManualGlobal);
      _manualPointerId = null;
      _panPointerId = null;
    }
    // Guarantee cleanup: if we're still dragging when disposed, cancel the drag.
    // This handles edge cases like:
    // - Element deletion during drag
    // - Widget tree restructuring during drag
    // - Hot reload during drag
    if (_isDragging) {
      _cancelDrag();
    }
    super.dispose();
  }

  /// Starts a drag operation using the captured pointer ID.
  ///
  /// Guard: Returns early if already dragging to prevent duplicate starts.
  /// Uses the pointer ID captured from onPointerDown (stored in _pendingPointerId).
  ///
  /// If [createSession] is provided, creates a session and starts it,
  /// which automatically locks the canvas.
  void _startDrag(DragStartDetails details) {
    if (_isDragging) return;

    // If shift is pressed, canvas-level shift-drag selection takes priority.
    // Don't start node drag - let the selection drag handle this pointer.
    if (HardwareKeyboard.instance.isShiftPressed) return;

    // 拖动开始:取消待定单击(此指针将不再作为 tap 触发)。
    _pendingTap = false;

    _isDragging = true;
    _dragPointerId = _pendingPointerId;
    resetAutoPanState(); // Reset drift at drag start (from mixin)

    // Create and start session if factory provided (locks canvas automatically)
    if (widget.createSession != null) {
      _session = widget.createSession!();
      _session!.start();
    }

    widget.onDragStart(details);
  }

  /// Updates during an active drag operation.
  ///
  /// Guard: Returns early if not dragging to prevent orphaned update events.
  /// Tracks pointer position for autopan and processes delta for drift compensation.
  ///
  /// Drift handling:
  /// - **Inside bounds**: Normal 1:1 movement (drift consumed/compensated if any)
  /// - **Outside bounds**: Element stays put, drift accumulates
  /// - **Re-entry**: For [trackPointerDirectly] elements, drift is applied
  ///   immediately (snap). For others, drift is consumed gradually.
  void _updateDrag(DragUpdateDetails details) {
    if (!_isDragging) return;

    // Track pointer position for autopan (uses mixin method)
    updatePointerPosition(details.globalPosition);

    // Process delta with drift compensation
    // For trackPointerDirectly: immediate snap on re-entry
    // For positioned elements: gradual consumption
    final effectiveDelta = processDragDelta(details.delta);

    // Only call onDragUpdate if there's actual movement
    if (effectiveDelta != Offset.zero) {
      widget.onDragUpdate(
        DragUpdateDetails(
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
          delta: effectiveDelta,
          primaryDelta: details.primaryDelta,
          sourceTimeStamp: details.sourceTimeStamp,
        ),
      );
    }
  }

  /// Ends the current drag operation.
  ///
  /// Guard: Returns early if not dragging to prevent duplicate ends.
  /// Stops the autopan timer and clears pointer position and drift.
  /// Ends the session if active (unlocks canvas automatically).
  void _endDrag(DragEndDetails details) {
    if (!_isDragging) return;
    stopAutoPan(); // From AutoPanMixin
    resetAutoPanState(); // From AutoPanMixin
    _isDragging = false;
    _dragPointerId = null;

    // End session if active (unlocks canvas automatically)
    _session?.end();
    _session = null;

    widget.onDragEnd(details);
  }

  /// Cancels the current drag operation.
  ///
  /// Called when the drag is interrupted (gesture cancelled, widget disposed,
  /// or pointer released). Cancels the session if active (unlocks canvas).
  /// Then calls [onDragCancel] if provided, otherwise falls back to [onDragEnd].
  void _cancelDrag() {
    if (!_isDragging) return;
    stopAutoPan(); // From AutoPanMixin
    resetAutoPanState(); // From AutoPanMixin
    _isDragging = false;
    _dragPointerId = null;

    // Cancel session if active (unlocks canvas automatically)
    _session?.cancel();
    _session = null;

    // Use dedicated cancel callback if provided, otherwise fall back to onDragEnd
    if (widget.onDragCancel != null) {
      widget.onDragCancel!();
    } else {
      widget.onDragEnd(DragEndDetails());
    }
  }

  /// Called on pointer up to check if the drag should end.
  ///
  /// Only ends the drag if the pointer that started the drag is the one ending.
  /// This is purely based on pointer ID matching - device kind doesn't matter.
  ///
  /// IMPORTANT: This is a safety net for edge cases where the gesture recognizer
  /// doesn't fire its callbacks. We schedule the cancel for the next microtask
  /// to give the gesture recognizer's `onEnd` callback priority. If `onEnd`
  /// fires first, it sets `_isDragging = false`, and this cancel becomes a no-op.
  ///
  /// Note: This is treated as a cancel because we don't have proper DragEndDetails
  /// from a pointer up event outside the gesture recognizer flow.
  void _handlePointerUp(PointerUpEvent event) {
    // POC 补丁:单击判定在 up 且未拖动时触发(onTap=选中),错开拖动窗口。
    // (触摸路径的 up 由全局路由先处理,此处仅剩鼠标/兜底;长按后不判定。)
    if (_pendingTap &&
        !_isDragging &&
        !_longPressFired &&
        event.pointer == _pendingPointerId) {
      _pendingTap = false;
      pocLog('ES.tap.onUp');
      widget.onTap?.call();
    }
    // Only consider canceling if this is the EXACT pointer that started the drag
    if (_isDragging && event.pointer == _dragPointerId) {
      // Schedule for next microtask to give gesture recognizer's onEnd priority.
      // The gesture recognizer processes the same PointerUpEvent and should call
      // onEnd synchronously. By deferring, we ensure onEnd fires first if it's
      // going to fire at all. If it doesn't (edge case), this cancel will clean up.
      Future.microtask(() {
        // Check again - onEnd may have already handled it
        if (_isDragging) {
          _cancelDrag();
        }
      });
    }
  }

  /// POC 补丁(v0.1.6→0.1.9):触摸手动拖动 —— move 事件直接驱动拖动生命周期,
  /// 不依赖 gesture arena。越阈后才 begin(区分点击)。
  void _handleManualMove(PointerMoveEvent event) {
    if (_manualPointerId == null || event.pointer != _manualPointerId) return;
    if (!_isDragging) {
      final Offset? down = _manualDownPos;
      if (down == null) return;
      if ((event.position - down).distance < kTouchSlop) return;
      _beginManualDrag(event.position, event.localPosition);
      if (!_isDragging) return;
      // POC(0.2.1):首帧位移补偿 —— 阈值期(slop)手指已移动的量一次性补上,
      // 否则节点落后手指 ~18px(不跟手)。
      _updateDrag(
        DragUpdateDetails(
          globalPosition: event.position,
          localPosition: event.localPosition,
          delta: event.position - down,
        ),
      );
    } else {
      _updateDrag(
        DragUpdateDetails(
          globalPosition: event.position,
          localPosition: event.localPosition,
          delta: event.delta,
        ),
      );
    }
  }

  /// POC 补丁(0.2.0):统一拖动起点 —— 触觉反馈 + 生命周期开始。
  void _beginManualDrag(Offset global, Offset local) {
    _pendingTap = false;
    pocLog('ES.manual.begin');
    HapticFeedback.lightImpact();
    _startDrag(
      DragStartDetails(globalPosition: global, localPosition: local),
    );
  }

  /// POC 补丁(v0.1.9):全局 pointer 路由 —— 触摸拖动完整生命周期。
  /// 注册于 touch down;move/up/cancel 全收(不依赖命中,移出元素仍跟手)。
  void _onManualGlobal(PointerEvent event) {
    // 第二指落下(双指):结束元素拖动/取消潜在 → 进入画布平移模式
    // (内容跟手;宿主经 onViewportPan 换算视口)。
    if (event is PointerDownEvent && event.pointer != _manualPointerId) {
      final bool wasDragging = _isDragging;
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onManualGlobal);
      _manualPointerId = null;
      _manualDownPos = null;
      if (wasDragging) {
        pocLog('ES.manual.twoFinger');
        _endDrag(DragEndDetails());
      }
      if (widget.onViewportPan != null) {
        pocLog('ES.twoFingerPan.start');
        _panPointerId = event.pointer;
        _panLast = event.position;
        GestureBinding.instance.pointerRouter.addGlobalRoute(_onManualGlobal);
      }
      return;
    }

    // 双指平移模式:第二指 move 驱动平移;其 up/cancel 结束平移。
    if (_panPointerId != null) {
      if (event is PointerMoveEvent && event.pointer == _panPointerId) {
        final Offset? last = _panLast;
        if (last != null) {
          final Offset d = event.position - last;
          _panLast = event.position;
          if (d != Offset.zero) {
            widget.onViewportPan?.call(d);
          }
        }
      } else if ((event is PointerUpEvent || event is PointerCancelEvent) &&
          event.pointer == _panPointerId) {
        _panPointerId = null;
        _panLast = null;
        GestureBinding.instance.pointerRouter.removeGlobalRoute(_onManualGlobal);
        pocLog('ES.twoFingerPan.end');
      }
      return;
    }

    if (event.pointer != _manualPointerId) return;
    if (event is PointerMoveEvent) {
      _handleManualMove(event);
    } else if (event is PointerUpEvent) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onManualGlobal);
      final bool wasDragging = _isDragging;
      _manualPointerId = null;
      _manualDownPos = null;
      // 未拖动 = 单击:触发 onTap(选中)。长按已触发则不视为单击。
      if (_pendingTap && !wasDragging && !_longPressFired) {
        _pendingTap = false;
        pocLog('ES.tap.onUp');
        widget.onTap?.call();
        return;
      }
      if (wasDragging) {
        pocLog('ES.manual.end');
        _endDrag(DragEndDetails());
      }
    } else if (event is PointerCancelEvent) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onManualGlobal);
      _manualPointerId = null;
      _manualDownPos = null;
      if (_isDragging) _cancelDrag();
    }
  }

  /// POC 补丁(0.2.0):触摸长按 = 上下文菜单(与鼠标右键同路)。
  void _handleLongPress(Offset globalPosition) {
    if (_isDragging) return;
    _longPressFired = true;
    _pendingTap = false;
    // 清除潜在拖动(长按后抬手不算拖动/单击)。
    if (_manualPointerId != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onManualGlobal);
      _manualPointerId = null;
      _manualDownPos = null;
    }
    pocLog('ES.longPress');
    HapticFeedback.selectionClick();
    widget.onContextMenu?.call(ScreenPosition(globalPosition));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      // Listener fires IMMEDIATELY on pointer down, before gesture arena.
      // We capture the pointer ID here for use when the drag starts.
      // This also provides instant tap feedback (e.g., selection).
      //
      // IMPORTANT: We only capture the pointer ID if we're not already dragging.
      // If a drag is in progress, a second pointer (any device) should not
      // overwrite the original pointer ID or trigger a new tap.
      onPointerDown: (event) {
        // POC 埋点:确认元素层收到 down 且可拖。
        pocLog('ES.down kind=${event.kind} draggable=${widget.isDraggable}');
        // If already dragging, don't let another pointer interfere
        if (_isDragging) {
          return;
        }

        // If shift is pressed, canvas-level shift-drag selection takes priority.
        // Don't capture pointer or fire tap - let the selection drag handle this.
        if (HardwareKeyboard.instance.isShiftPressed) {
          return;
        }

        _pendingPointerId = event.pointer;
        // POC 补丁:选中延迟到 up(见 _pendingTap),不在此处触发 onTap。
        _pendingTap = widget.onTap != null;
        _longPressFired = false;
        // POC 补丁(v0.1.9):触摸拖动由全局 pointer 路由手动接管 ——
        // 注册后无论指针移出元素(小端口拖线)都能持续跟手。
        if (event.kind == PointerDeviceKind.touch && widget.isDraggable) {
          _manualPointerId = event.pointer;
          _manualDownPos = event.position;
          GestureBinding.instance.pointerRouter.addGlobalRoute(
            _onManualGlobal,
          );
          // POC(0.2.0):端口等小元素按下即开始拖动,零延迟。
          if (widget.instantManualTouch) {
            _pendingTap = false;
            _beginManualDrag(event.position, event.localPosition);
          }
        }
      },
      // 触摸 move/up/cancel 由全局路由处理(见 _onManualGlobal);
      // Listener up 仅保留非触摸(鼠标)拖拽兜底。
      onPointerUp: _handlePointerUp,
      child: RawGestureDetector(
        behavior: widget.hitTestBehavior,
        gestures: <Type, GestureRecognizerFactory>{
          // Custom pan recognizer that rejects trackpad gestures.
          // This allows trackpad pan to bubble up to InteractiveViewer
          // for canvas panning, while mouse/touch drag moves the element.
          if (widget.isDraggable)
            NonTrackpadPanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  NonTrackpadPanGestureRecognizer
                >(() => NonTrackpadPanGestureRecognizer(), (recognizer) {
                  // Configure drag start behavior (immediate for ports, threshold for elements)
                  recognizer.dragStartBehavior = widget.dragStartBehavior;
                  // Use local methods that track drag state and pass full details
                  // POC 埋点:确认 pan 识别器触发。
                  recognizer.onStart = (DragStartDetails d) {
                    pocLog('ES.pan.onStart');
                    _startDrag(d);
                  };
                  recognizer.onUpdate = _updateDrag;
                  recognizer.onEnd = (DragEndDetails d) {
                    pocLog('ES.pan.onEnd');
                    _endDrag(d);
                  };
                  recognizer.onCancel = _cancelDrag;
                }),

          // Double tap recognizer
          if (widget.onDoubleTap != null)
            DoubleTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  DoubleTapGestureRecognizer
                >(() => DoubleTapGestureRecognizer(), (recognizer) {
                  recognizer.onDoubleTap = widget.onDoubleTap;
                }),

          // POC 补丁(0.2.0):长按 = 上下文(触摸端无右键,长按等同右键;
          // 静止 500ms 触发,移动即放弃)。桌面鼠标长按同样生效。
          if (widget.onContextMenu != null)
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(() => LongPressGestureRecognizer(), (recognizer) {
                  recognizer.onLongPressStart = (LongPressStartDetails d) {
                    _handleLongPress(d.globalPosition);
                  };
                }),

          // Secondary tap (right-click) for context menu
          if (widget.onContextMenu != null)
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(),
                  (recognizer) {
                    recognizer.onSecondaryTapUp = (details) =>
                        widget.onContextMenu!(
                          ScreenPosition(details.globalPosition),
                        );
                  },
                ),
        },
        child: MouseRegion(
          cursor: widget.cursor ?? MouseCursor.defer,
          onEnter: widget.onMouseEnter != null
              ? (_) => widget.onMouseEnter!()
              : null,
          onExit: widget.onMouseLeave != null
              ? (_) => widget.onMouseLeave!()
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}
