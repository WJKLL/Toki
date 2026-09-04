// lib/presentation/widgets/c34_responsive_card_grid.dart
// 编号:C-34 响应式卡片网格容器(v1.22.0 静态;v1.23.0 拖拽排序;
//   v1.24.7 拖拽排序语义修正:松手落点与拖拽预览一致、hover 无滞后)
// 说明:首页网格区 —— 可变尺寸(1×1/2×1/2×2)行流排布 + 响应式列数
//   (<600→2 / 600-1099→3 / ≥1100→4),固定行高(kGridRowHeight)。
//   拖拽交互(仿 iOS 阻尼手感):
//   - 长按 300ms(位移超 touchSlop 自动放弃,让位给滚动/点击)→ 触觉 + 浮起
//     (easeOutBack 缩放 1.08,带轻微回弹阻尼);
//   - 拖拽中卡片 Transform 跟手(独立 feedback 层),其它卡 150ms 平滑让位
//     (AnimatedPositioned),hover 目标按最近卡中心判插入位;
//   - 松手 → 落位回弹(1.08→1.0 easeOutBack)+ controller.reorder 防抖持久化;
//   - 拖拽期间 dragActiveProvider=true:首页禁滚、分钟 Timer 跳过。
// 性能:静止零 ticker;拖拽 move 仅一次 setState(布局为纯函数,<16ms);
//   整网格 + 单卡双层 RepaintBoundary,让位动画仅动受影响卡。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/home_card.dart';
import '../../domain/entities/tool_item.dart';
import '../../core/widgets/mini_toast.dart';
import '../providers/drag_active_provider.dart';
import '../providers/home_cards_provider.dart';
import 'cards/card_class_countdown.dart';
import 'cards/card_combo.dart';
import 'cards/card_dashboard.dart';
import 'cards/card_shell.dart';
import 'cards/card_steam_tool.dart';

/// 网格行高单位(px):large 2 行 = 104×2+12 = 220 ≥ 组合卡内容(196)。
const double kGridRowHeight = 104;

/// 卡间距(水平/垂直同值)。
const double kGridCardGap = 12;

/// 长按激活时长(仿 iOS 拖拽激活节奏)。
const Duration kGridLongPressDelay = Duration(milliseconds: 300);

/// 让位动画时长(拖拽中平滑跟手;v1.23.1 放缓:150→300ms,
/// 被挤开的卡有更从容的位移节奏)。
const Duration kGridSlotAnimDuration = Duration(milliseconds: 300);

/// 落位/浮起回弹时长(阻尼手感)。
const Duration kGridSettleDuration = Duration(milliseconds: 180);

/// v1.34.2:长按成立后,手指再移动超过该距离才判定为「拖拽排序」;
/// 未超过即松手 → 进入编辑态(iOS 式)。小于 kTouchSlop,保证拖动跟手不迟滞。
const double kGridDragStartSlop = 8;

/// 飞行收尾缩放系数:浮起放大 1.08 → 收回 1.0 的比例(1/1.08)。
const double kGridFloatShrink = 0.926;

/// 响应式列数(按设备宽度)。
int gridColumnsForWidth(double width) {
  if (width >= 1100) return 4;
  if (width >= 600) return 3;
  return 2;
}

/// 单卡放置结果。
class GridPlacement {
  const GridPlacement({
    required this.card,
    required this.col,
    required this.row,
    required this.colspan,
    required this.rowspan,
  });

  final HomeCardData card;
  final int col;
  final int row;
  final int colspan;
  final int rowspan;

  double width(double cellW) => colspan * cellW + (colspan - 1) * kGridCardGap;

  double height() => rowspan * kGridRowHeight + (rowspan - 1) * kGridCardGap;

  double left(double cellW) => col * (cellW + kGridCardGap);

  double top() => row * (kGridRowHeight + kGridCardGap);
}

/// 行流放置纯函数(跨行卡恒行首,无缺口)。
({List<GridPlacement> placements, int totalRows}) placeGrid(
  List<HomeCardData> cards,
  int cols,
) {
  final Map<int, int> used = <int, int>{};
  int usedOf(int r) => used[r] ?? 0;
  final List<GridPlacement> out = <GridPlacement>[];
  int bottomRow = 0;

  for (final HomeCardData card in cards) {
    final int cs = card.size.colspan;
    final int rs = card.size.rowspan;
    int r = 0;
    int col = 0;
    if (rs > 1) {
      while (true) {
        final bool rowHeadFree = usedOf(r) == 0;
        final bool nextFits = usedOf(r + 1) + cs <= cols;
        if (rowHeadFree && nextFits) break;
        r++;
      }
    } else {
      while (usedOf(r) + cs > cols) {
        r++;
      }
      col = usedOf(r);
    }
    for (int rr = r; rr < r + rs; rr++) {
      used[rr] = math.max(usedOf(rr), col + cs);
    }
    out.add(
      GridPlacement(card: card, col: col, row: r, colspan: cs, rowspan: rs),
    );
    bottomRow = math.max(bottomRow, r + rs - 1);
  }
  return (placements: out, totalRows: bottomRow + 1);
}

/// C-34 响应式卡片网格(尺寸 + 拖拽排序)。
class C34ResponsiveCardGrid extends ConsumerStatefulWidget {
  const C34ResponsiveCardGrid({super.key});

  @override
  ConsumerState<C34ResponsiveCardGrid> createState() =>
      _C34ResponsiveCardGridState();
}

class _C34ResponsiveCardGridState extends ConsumerState<C34ResponsiveCardGrid>
    with SingleTickerProviderStateMixin {
  // ── 拖拽会话状态 ──
  Offset? _pressDown; // Stack 内坐标
  int? _downHit; // down 命中的卡下标(供 LongPress 回调定位)
  bool _dragging = false;
  String? _dragId;
  int _dragOldIndex = -1;
  bool _dragLandscape = false; // 激活时的方向(落位写回对应套)
  Offset _dragGrab = Offset.zero; // 手指相对卡左上
  Offset _feedbackPos = Offset.zero; // feedback 左上(Stack 内)
  int _hoverIndex = -1; // base(去 dragged)中的插入位

  // ── 编辑态(v1.34.2:长按静止松手进入;iOS 式微缩 + 工具卡右上 ✕)──
  // 长按由手势竞技场 LongPressGestureRecognizer(300ms)识别 —— 长按胜出时
  // 卡内 tap 被 reject(松手不会误 push);随后:继续移动 = 拖拽排序;
  // 直接松手 = 进入编辑态。
  bool _editing = false;
  int? _armedIndex;

  // v1.24.6:拖拽期渲染布局缓存(供 hover 判定:含空槽,避免激活抖动)。
  List<GridPlacement>? _renderPlacements;
  Rect? _dragSlotRect;

  // ── 松手「自动落入目标槽」飞行动画(v1.24.4)──
  bool _flying = false;
  String? _flyingId;
  Offset _flightFrom = Offset.zero;
  Offset _flightTo = Offset.zero;
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(_onFlightTick);
  late Animation<Offset> _flightPos = _buildFlight();

  Animation<Offset> _buildFlight() {
    // v1.24.5:去 easeOutBack 终点过冲 —— 短距落位时过冲表现为
    // 「先弹一下再归位」;改 easeOutCubic 平滑无过冲飞入。
    return Tween<Offset>(
      begin: _flightFrom,
      end: _flightTo,
    ).animate(CurvedAnimation(parent: _flight, curve: Curves.easeOutCubic));
  }

  void _onFlightTick() {
    if (mounted) setState(() {}); // 飞行 240ms 内的逐帧定位
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  // ── 拖拽生命周期 ──

  void _onPointerDown(
    PointerDownEvent e,
    List<HomeCardData> cards,
    int cols,
    bool landscape,
  ) {
    if (_dragging) return;
    final List<GridPlacement> place = placeGrid(cards, cols).placements;
    final Offset local = e.localPosition;
    int? hit;
    for (int i = 0; i < place.length; i++) {
      final Rect r = _rectOf(place[i], _cellW);
      if (r.contains(local)) {
        hit = i;
        break;
      }
    }
    _downHit = hit;
    if (hit == null) {
      // v1.34.2:编辑态下点网格空白 → 退出编辑态(用户约定)。
      if (_editing) _setEditing(false);
      return;
    }
    _pressDown = local;
  }

  /// 长按成立(竞技场 300ms 胜出,卡内 tap 已被 reject):
  /// 触觉提示并置「待定」—— 继续移动=拖拽排序,直接松手=编辑态(iOS 式)。
  void _onLongPress() {
    if (!mounted || _dragging) return;
    final int? idx = _downHit;
    if (idx == null) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _armedIndex = idx);
  }

  void _activateDrag(
    int index,
    List<HomeCardData> cards,
    List<GridPlacement> place,
    bool landscape,
  ) {
    unawaited(HapticFeedback.mediumImpact());
    final HomeCardData card = cards[index];
    final GridPlacement p = place[index];
    final Offset topLeft = Offset(p.left(_cellW), p.top());
    setState(() {
      _dragging = true;
      _dragId = card.id;
      _dragOldIndex = index;
      _dragLandscape = landscape;
      _dragGrab = (_pressDown ?? topLeft) - topLeft;
      _feedbackPos = topLeft;
      _hoverIndex = index; // base 移除后原位插入
    });
    ref.read(dragActiveProvider.notifier).begin();
  }

  void _onPointerMove(
    PointerMoveEvent e,
    List<HomeCardData> cards,
    int cols,
    bool landscape,
  ) {
    if (_dragging) {
      final Offset local = e.localPosition;
      setState(() {
        _feedbackPos = local - _dragGrab;
        _hoverIndex = _computeHover(local, cards);
      });
      return;
    }
    // 长按已成立(armed):移动超阈值 → 转为拖拽排序(浮起跟手)。
    final int? armed = _armedIndex;
    if (armed != null && _pressDown != null) {
      if ((e.localPosition - _pressDown!).distance > kGridDragStartSlop) {
        setState(() => _armedIndex = null);
        final List<GridPlacement> placed = placeGrid(cards, cols).placements;
        if (armed < placed.length) {
          _activateDrag(armed, cards, placed, landscape);
        }
      }
      return;
    }
    // 未 armed:竞技场已接管长按/滚动判定(LongPress 超位移自动 reject),
    // 此处无需手动取消 timer。
  }

  /// 手指抬起:armed 状态下直接松手 → 进入编辑态(工具卡 ✕ 显现)。
  void _onPointerUp() {
    _pressDown = null;
    _downHit = null;
    final int? armed = _armedIndex;
    if (armed != null) {
      // 同步收尾:清 armed + 进入编辑态(LongPress 已 reject 卡 tap,
      // 此 up 不会误 push 工具页)。
      setState(() {
        _armedIndex = null;
        _editing = true;
      });
      return;
    }
    if (!_dragging) return;
    _finishDrag();
  }

  /// 系统取消(滚动/手势被抢):仅放弃长按待定,不进编辑态。
  void _onPointerCancel() {
    _pressDown = null;
    _downHit = null;
    if (_armedIndex != null) {
      setState(() => _armedIndex = null);
    }
    if (!_dragging) return;
    _finishDrag();
  }

  /// 计算 hover 插入位(v1.24.6 修复「激活抖动」;v1.24.7 修正下标映射):
  /// 判定基于**含空槽的当前渲染布局**——渲染卡列表 = 移除被拖卡后的
  /// base 列表(display 仅在 base 中插入被拖卡,滤除后顺序不变),故
  /// 渲染卡视觉下标 i 即 base 下标 i,**映射为恒等**。旧实现把渲染下标
  /// 误当 display 下标再 -1,导致手指已越过渲染卡时插入位滞后一格,
  /// 让位动画与 hover 判定互相追赶,形成「卡片先聚拢又归位」的往复。
  /// 手指停留在空槽内时 hover 保持不变,其它卡不会先补位又被挤回。
  int _computeHover(Offset local, List<HomeCardData> cards) {
    final List<GridPlacement> placed =
        _renderPlacements ?? const <GridPlacement>[];
    if (placed.isEmpty) return _hoverIndex;
    // 1) 命中渲染卡:按卡中心左右决定插前(i)/插后(i+1)。
    for (int i = 0; i < placed.length; i++) {
      final Rect r = _rectOf(placed[i], _cellW);
      if (!r.contains(local)) continue;
      int t = i;
      if (local.dx > r.center.dx) t = i + 1;
      return t.clamp(0, cards.length - 1);
    }
    // 2) 手指仍在空槽(被拖卡让出的位置)→ 保持现状,不让位不抖动。
    if (_dragSlotRect != null && _dragSlotRect!.contains(local)) {
      return _hoverIndex;
    }
    // 3) 行间隙/空白:就近卡(中心距离)+ 左右方向。
    double bestD = double.infinity;
    int bestDisp = -1;
    for (int i = 0; i < placed.length; i++) {
      final double d = (local - _rectOf(placed[i], _cellW).center).distance;
      if (d < bestD) {
        bestD = d;
        bestDisp = i;
      }
    }
    if (bestDisp < 0) return _hoverIndex;
    final Rect br = _rectOf(placed[bestDisp], _cellW);
    int t = bestDisp;
    if (local.dx > br.center.dx) t = bestDisp + 1;
    return t.clamp(0, cards.length - 1);
  }

  /// 松手:写回顺序(防抖持久化)→ feedback 从手指位置**自动飞入目标槽**
  /// (240ms easeOutBack 轻微过冲再落定),槽位卡同时以 1.08→1.0 收尾,
  /// 全程无"跳脱/空中消失"。
  void _finishDrag() {
    unawaited(HapticFeedback.lightImpact());
    final String? dragId = _dragId;
    final int oldIndex = _dragOldIndex;
    final int hover = _hoverIndex < 0 ? oldIndex : _hoverIndex;
    final bool landscape = _dragLandscape;
    final Offset from = _feedbackPos;
    ref.read(dragActiveProvider.notifier).end();
    if (dragId != null) {
      ref
          .read(gridCardsProvider.notifier)
          .reorder(landscape: landscape, oldIndex: oldIndex, newIndex: hover);
    }
    final Offset to = _targetTopLeft(dragId);
    setState(() {
      _dragging = false;
      _dragId = null;
      _dragOldIndex = -1;
      _hoverIndex = -1;
    });
    if (dragId == null || (to - from).distance < 1) return;
    setState(() {
      _flying = true;
      _flyingId = dragId;
      _flightFrom = from;
      _flightTo = to;
    });
    _flightPos = _buildFlight();
    unawaited(
      _flight.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        // v1.24.5:落定直接归位(无收尾缩放),消除「弹一下」。
        setState(() {
          _flying = false;
          _flyingId = null;
        });
      }),
    );
  }

  // ── 编辑态(v1.34.2)──────────────────────────────────────────

  void _setEditing(bool value) {
    if (_editing == value) return;
    setState(() => _editing = value);
  }

  /// 工具卡 ✕:从首页移除;移除后若无剩余工具卡 → 自动退出编辑态。
  void _removeTool(ToolLaunchCardData card) {
    unawaited(HapticFeedback.lightImpact());
    unawaited(ref.read(homeToolItemsProvider.notifier).remove(card.toolId));
    final ToolItem? item = ToolItem.byId(card.toolId);
    showMiniToast(context, '已从首页移除 · ${item?.name ?? card.toolId}');
    if (_editing && ref.read(homeToolItemsProvider).isEmpty) {
      _setEditing(false);
    }
  }

  /// 计算某卡在(写回后的)当前方向网格中的槽位左上角。
  Offset _targetTopLeft(String? id) {
    if (id == null) return _feedbackPos;
    final GridOrderState order = ref.read(gridCardsProvider);
    final List<HomeCardData> list = _dragLandscape
        ? order.landscape
        : order.portrait;
    final int cols = gridColumnsForWidth(MediaQuery.sizeOf(context).width);
    final List<GridPlacement> place = placeGrid(list, cols).placements;
    for (final GridPlacement p in place) {
      if (p.card.id == id) return Offset(p.left(_cellW), p.top());
    }
    return _feedbackPos;
  }

  // ── 布局渲染 ──

  double _cellW = 0;

  Rect _rectOf(GridPlacement p, double cellW) =>
      Rect.fromLTWH(p.left(cellW), p.top(), p.width(cellW), p.height());

  @override
  Widget build(BuildContext context) {
    // v1.23.1:竖/横屏各一套顺序(旋转时自动切换 + 让位动画)。
    final Size screenSize = MediaQuery.sizeOf(context);
    final bool landscape = screenSize.width > screenSize.height;
    final List<HomeCardData> cards = ref.watch(
      gridCardsProvider.select(
        (GridOrderState s) => landscape ? s.landscape : s.portrait,
      ),
    );
    final int cols = gridColumnsForWidth(screenSize.width);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availW = constraints.maxWidth;
        _cellW = (availW - (cols - 1) * kGridCardGap) / cols;

        // 活动卡:拖拽中 = 手指跟随;飞行中 = 从手指位置飞入目标槽。
        final String? activeId = _dragging
            ? _dragId
            : (_flying ? _flyingId : null);
        int activeIdx = -1;
        if (activeId != null) {
          activeIdx = cards.indexWhere((HomeCardData c) => c.id == activeId);
        }
        final HomeCardData? activeCard = activeIdx < 0
            ? null
            : cards[activeIdx];
        final List<HomeCardData> display;
        if (_dragging && activeCard != null) {
          // 拖拽中:去掉 dragged,再按 hover 插入(让位预览)。
          display = <HomeCardData>[
            for (final HomeCardData c in cards)
              if (c.id != activeCard.id) c,
          ]..insert(_hoverIndex.clamp(0, cards.length - 1), activeCard);
        } else {
          // 静止 / 飞行期:provider 已是最终顺序。
          display = cards;
        }

        final ({List<GridPlacement> placements, int totalRows}) result =
            placeGrid(display, cols);
        final double gridH =
            result.totalRows * kGridRowHeight +
            (result.totalRows - 1) * kGridCardGap;

        // 缓存渲染布局供 hover 判定(拖拽期含空槽;静止/飞行期清空)。
        if (_dragging && activeId != null) {
          _renderPlacements = <GridPlacement>[
            for (final GridPlacement p in result.placements)
              if (p.card.id != activeId) p,
          ];
          Rect? slot;
          for (final GridPlacement p in result.placements) {
            if (p.card.id == activeId) {
              slot = _rectOf(p, _cellW);
              break;
            }
          }
          _dragSlotRect = slot;
        } else {
          _renderPlacements = null;
          _dragSlotRect = null;
        }

        return PopScope<Object?>(
          // v1.34.2 编辑态:拦截系统返回/侧滑 —— 仅退出编辑态(不退出应用)。
          canPop: !_editing,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop && _editing) _setEditing(false);
          },
          child: RawGestureDetector(
            // v1.34.2:长按识别交给手势竞技场(LongPress 300ms)—— 长按胜出
            // 时卡内 tap 被 reject,松手不会误 push 工具页;快速点按不受影响。
            gestures: <Type, GestureRecognizerFactory>{
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                      () => LongPressGestureRecognizer(
                        duration: kGridLongPressDelay,
                      ),
                      (LongPressGestureRecognizer instance) {
                        instance.onLongPress = _onLongPress;
                      },
                    ),
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (PointerDownEvent e) =>
                  _onPointerDown(e, cards, cols, landscape),
              onPointerMove: (PointerMoveEvent e) =>
                  _onPointerMove(e, cards, cols, landscape),
              onPointerUp: (_) => _onPointerUp(),
              onPointerCancel: (_) => _onPointerCancel(),
              child: IgnorePointer(
                // 拖拽/飞行/长按已成立(armed):屏蔽卡内点击/按压反馈。
                ignoring: _dragging || _flying || _armedIndex != null,
            child: RepaintBoundary(
              child: SizedBox(
                height: gridH,
                width: availW,
                // clip none:旋转/飞行动画中允许短暂超出容器,避免被裁剪跳变。
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    for (final GridPlacement p in result.placements)
                      if (p.card.id != activeId)
                        AnimatedPositioned(
                          duration: kGridSlotAnimDuration,
                          curve: Curves.easeOut,
                          left: p.left(_cellW),
                          top: p.top(),
                          width: p.width(_cellW),
                          height: p.height(),
                          child: RepaintBoundary(
                            key: ValueKey<String>(p.card.id),
                            child: _slotChild(p),
                          ),
                        ),
                    // feedback:拖拽跟手 / 飞行自动落入目标槽。
                    if (activeCard != null)
                      Positioned(
                        left: (_flying ? _flightPos.value.dx : _feedbackPos.dx),
                        top: (_flying ? _flightPos.value.dy : _feedbackPos.dy),
                        width:
                            activeCard.size.colspan * _cellW +
                            (activeCard.size.colspan - 1) * kGridCardGap,
                        height:
                            activeCard.size.rowspan * kGridRowHeight +
                            (activeCard.size.rowspan - 1) * kGridCardGap,
                        child: IgnorePointer(
                          // v1.24.5:飞行期将浮起放大(1.08)同步收回 1.0,
                          // 落定与槽位(1.0)替换时无缩放突变(消除「弹一下」)。
                          child: AnimatedScale(
                            scale: _flying ? kGridFloatShrink : 1.0,
                            duration: kGridSettleDuration,
                            curve: Curves.easeOut,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0.94, end: 1.08),
                              duration: kGridSettleDuration,
                              curve: Curves.easeOutBack,
                              builder:
                                  (
                                    BuildContext context,
                                    double scale,
                                    Widget? child,
                                  ) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: child,
                                    );
                                  },
                              child: CardShadow(
                                // v1.25.0:拖拽浮起/飞行期阴影抬升档
                                // (1.08 浮起 + 阴影加深 → 离桌感;落定
                                // 与槽位常态阴影同帧替换)。
                                elevated: true,
                                child: _cardWidget(activeCard),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          ),
          ),
        );
      },
    );
  }

  /// 槽位子卡:固定尺寸 + 阴影。
  /// v1.34.2:编辑态整卡微缩(0.94)+ 卡主体 IgnorePointer 禁点(防误触跳转),
  /// 工具卡右上 ✕ 常驻树由 editing 驱动淡入/淡出。
  Widget _slotChild(GridPlacement p) {
    final double w = p.width(_cellW);
    final double h = p.height();
    final HomeCardData card = p.card;
    return SizedBox(
      width: w,
      height: h,
      child: CardShadow(
        child: AnimatedScale(
          scale: _editing ? 0.94 : 1.0,
          duration: kGridSettleDuration,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 编辑态:卡主体禁点(不跳转);✕ 独立命中区可点。
              IgnorePointer(
                ignoring: _editing,
                child: _cardWidget(card),
              ),
              if (card is ToolLaunchCardData)
                Positioned(
                  top: 4,
                  right: 4,
                  child: _ToolRemoveBadge(
                    editing: _editing,
                    card: card,
                    onRemove: _removeTool,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 卡内容分发(摘要不入网格;此处穷尽其余类型)。
  Widget _cardWidget(HomeCardData card) {
    return switch (card) {
      SummaryCardData _ => const SizedBox.shrink(),
      ComboCardData d => C28ComboCard(data: d),
      DashboardCardData d => C29DashboardCard(data: d),
      ClassCountdownCardData d => C33ClassCountdownCard(data: d),
      ToolLaunchCardData d => C37SteamToolCard(data: d),
    };
  }
}

/// 工具卡右上 ✕ 移除钮(v1.34.2,编辑态专属):
/// 常驻树由 [editing] 驱动 AnimatedScale 弹入/收起(scale 0 时变换奇异,
/// 不参与命中,不会挡卡主体点击);编辑态外 onTap 为 null 双保险。
class _ToolRemoveBadge extends StatelessWidget {
  const _ToolRemoveBadge({
    required this.editing,
    required this.card,
    required this.onRemove,
  });

  final bool editing;
  final ToolLaunchCardData card;
  final ValueChanged<ToolLaunchCardData> onRemove;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return AnimatedScale(
      scale: editing ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      alignment: Alignment.center,
      child: GestureDetector(
        key: ValueKey<String>('toolRemove.${card.toolId}'),
        behavior: HitTestBehavior.opaque,
        onTap: editing ? () => onRemove(card) : null,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: MiuixIcon(
              vector: MiuixIcons.basic.close,
              size: 12,
              tint: colors.onSurfaceVariantActions,
            ),
          ),
        ),
      ),
    );
  }
}
