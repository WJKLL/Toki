// lib/presentation/widgets/kernel/kernel_bottombar.dart
// 1:1 复刻 KernelSU 参考项目 FloatingBottomBar.kt（IosLiquidGlassNavigationBar）。
// 从 miuix_bottombar_demo（backup_08）移植，主项目适配：
//   - 图标：IconData → MiuixVectorIcon（MiuixIcon 渲染，主项目 UI 约束）；
//   - backdrop 可空：页面级快照（MiuixLayerBackdrop）按 U-03 门控可能为 null，
//     与 isBlurEnabled 联动降级为半透明纯色（无模糊/折射）；
//   - 主题：MiuixTheme（不再 import material）。
// 自研（参考项目原始参数）：DampedDragController（按压 78/56 + 阻尼拖拽）、
//   InnerShadow（offset 内阴影）、LensRefraction（lens 折射着色器）。
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        kTouchSlop,
        PointerCancelEvent,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'blur.dart';
import 'damped_drag.dart';
import 'dual_peak_highlight.dart';
import 'inner_shadow.dart';
import 'lens.dart';

/// 底栏项数据。
class KernelBarItem {
  const KernelBarItem({required this.label, required this.icon});
  final String label;

  /// 矢量图标（主项目统一出口 appIcon 惰性查找；禁止 Material IconData）。
  final MiuixVectorIcon icon;
}

/// 1:1 复刻参考项目 FloatingBottomBar 的液态玻璃悬浮底栏。
class KernelFloatingBottomBar extends StatefulWidget {
  const KernelFloatingBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.backdrop,
    required this.items,
    this.isBlurEnabled = true,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 页面级毛玻璃快照（U-03 门控，Web/Android<13 为 null → 降级半透明）。
  final MiuixLayerBackdrop? backdrop;
  final List<KernelBarItem> items;
  final bool isBlurEnabled;

  @override
  State<KernelFloatingBottomBar> createState() =>
      _KernelFloatingBottomBarState();
}

class _KernelFloatingBottomBarState extends State<KernelFloatingBottomBar>
    with TickerProviderStateMixin {
  late DampedDragController _drag;
  double _tabWidth = 0;

  /// 紧凑胶囊：每个 tab 固定宽（参考项目 FloatingBottomBarItem
  ///   defaultMinSize(minWidth = 76.dp)），整条胶囊宽度 = n*宽 + 左右 8dp 内边距，
  /// 居中悬浮（参考项目 Box(width(IntrinsicSize.Min))）。
  static const double _itemWidth = 76;
  static const double _pillHeight = 64;

  /// capture 外扩余量（dp）：pill 按压放大到 1+16dp/宽 ≈ 1.05 倍，宽高各放大
  /// ~5%；若 capture 区域不预留余量，放大部分被快照裁剪 → 毛玻璃不随按压跃起。
  static const double _pillPadX = 12;
  static const double _pillPadY = 8;

  /// 容器"跃起"缩放：按压时 pill 放大到 1 + 16dp/胶囊宽（参考项目
  ///   FloatingBottomBar.kt:336-338 layerBlock：lerp(1, 1+16dp/宽, press)）。
  double _containerScale() =>
      1 + (16 / (_itemWidth * widget.items.length + 8)) * _drag.pressProgress;

  /// Listener 手动拖拽状态。
  double _dragStartX = 0;
  double _dragStartValue = 0;
  bool _dragActive = false;

  /// 按下时是否落在【当前指示框】范围内（按当前项才缩放；点其它 tab 是切页，
  /// 不缩放，缩放交给 onTap 的切页动画，避免 press 被顶掉）。
  bool _pressedOnIndicator = false;

  /// 当前移动方向（+1 右移 → 边缘折射逆时针流动；-1 左移 → 顺时针）。
  /// 由 Listener 拖拽 dx 更新，供 LensRefraction.flowDir 使用。
  double _flowDir = 1;

  /// 速度估算（指示器速度形变"果冻"用）：上一次 move 的时间戳与 value。
  /// 拖拽中用 (Δvalue)/(Δt) 估算速度 → _drag.updateVelocity → _indicatorScale
  /// 的 velocity 项（scaleX 压扁 / scaleY 微拉），松手弹簧回正。
  Duration? _lastMoveTime;
  double _lastMoveValue = 0;

  /// 喂入 velocity 弹簧前的平滑速度（EMA 低通，时间常数 ~50ms）。
  /// (Δvalue/Δt) 在 8ms 级 move 间隔下噪声大，直接喂会造成形变毛刺抖动；
  /// 先低通再交给连续弹簧，velocity 变化圆润 → 形变柔和丝滑。
  double _smoothVel = 0;

  /// 最近一次由【底栏自身】驱动吸附的目标索引（onTap/_endDrag）。
  /// didUpdateWidget 收到同一 selectedIndex 回写时跳过，避免
  /// press→release 脉冲重复（参考项目由 currentIndex 单一驱动动画，
  /// selectedIndex 变化只更新 currentIndex，见 FloatingBottomBar.kt:267-275）。
  int? _selfAnimatedIndex;

  /// 底栏本体快照（参考项目 tabsBackdrop 语义）：捕获【整个底栏内容】
  /// （pill 毛玻璃 + onSurface 标签行）。这层本身可见（不隐藏、不包 Opacity），
  /// MiuixLayerBackdropCapture 照常捕获 → 指示器透过玻璃采样它 = 底下底栏的
  /// 1:1 渲染，无错位、无双层（快照就是本体）。
  final MiuixLayerBackdrop _barBackdrop = MiuixLayerBackdrop();

  /// 模糊生效条件：外部开关 + 页面快照存在（U-03 门控 backdrop 可空）。
  /// 任一不满足 → pill/指示器降级半透明纯色，且不挂 capture 采样（零捕获成本）。
  bool get _blurOn => widget.isBlurEnabled && widget.backdrop != null;

  @override
  void initState() {
    super.initState();
    _drag = DampedDragController(vsync: this, tabCount: widget.items.length)
      ..addListener(_onDragChanged);
    // v1.43.0：冷启动默认页非 0(待办在左、默认首页=1 等)时指示器直接落位。
    //   mount 首帧不走 didUpdateWidget,控制器初值 0 会把指示器停在 index 0,
    //   与当前页(首页)错位 —— 用 updateValueDirect 无动画落位到选中页。
    if (widget.selectedIndex > 0) {
      _drag.updateValueDirect(widget.selectedIndex.toDouble());
    }
  }

  void _onDragChanged() => setState(() {});

  @override
  void didUpdateWidget(KernelFloatingBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部页面切换（PageView 滑动）→ 指示器吸附动画（参考项目
    //   currentIndex 变化 → dampedDragAnimation.animateToValue）。
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final int next = widget.selectedIndex;
      if (_selfAnimatedIndex != null) {
        // 底栏自身驱动中（onTap/_endDrag → onSelected → PageView 跨页滚动）。
        // 跨页滚动时 onPageChanged 会依次回写每个中间页（0→3 会经过 1、2、3），
        // 这些中间页不是目标，忽略其动画 —— 否则指示器被强行拉回相邻页。
        // 只有到达目标页才清除标志，结束抑制。
        if (next == _selfAnimatedIndex) {
          _selfAnimatedIndex = null;
        }
      } else {
        _drag.animateToValue(next.toDouble());
      }
    }
  }

  @override
  void dispose() {
    _drag.removeListener(_onDragChanged);
    _drag.dispose();
    _barBackdrop.dispose();
    super.dispose();
  }

  /// iosIndicatorSpecular（FloatingBottomBar.kt:86-104）：white 0.12 / innerBlur 2dp
  ///   / 双光源 / dualPeak；经 rememberGravityRotatedHighlight 旋转 extraDegrees。
  /// [dualPeak]：true = 单光源 180° 对峰（上下缘各一条亮带）；false = 仅顶部单峰。
  ///   v1.19.6：底栏容器/指示器关闭 dualPeak —— 深色玻璃下副峰(白0.4)在底部
  ///   形成暖黄亮带,被识别为文字下方的"双横黄线"。
  Highlight _specularHighlight(
    double extraDegrees, {
    double alpha = 1,
    bool dualPeak = true,
  }) {
    final double rad = extraDegrees * math.pi / 180.0;
    final double s = math.sin(rad);
    final double c = math.cos(rad);
    // 默认光源方向 (0,-1) 旋转后 (lx, ly) = (s, -c)。
    return Highlight(
      width: 1,
      alpha: alpha,
      style: BloomStroke(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.12),
        innerBlurRadius: 2,
        primaryLight: LightSource(
          position: LightPosition(0.5 + s, 0.7 - c, -0.05),
          color: const Color(0xFFFFFFFF),
          intensity: 1,
        ),
        secondaryLight: const LightSource(
          position: LightPosition(0.5, 0.8, -0.5),
          color: Color(0xFFFFFFFF),
          intensity: 0.4,
        ),
        dualPeak: dualPeak,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = MiuixTheme.of(context).brightness == Brightness.dark;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // 磨砂感：tint surfaceContainer@0.7（微微透背景），blur 16dp（强磨砂）。
    //   v1.18.x 用户需求：底栏"只需微微透过背景、磨砂感强"（原参考项目 0.4/4dp 太透）。
    final Color containerColor = colors.surfaceContainer.withValues(alpha: 0.7);

    final Highlight baseHighlight = _specularHighlight(
      -45,
      alpha: 0.75,
      dualPeak: false,
    );
    final Highlight pillHighlight = _specularHighlight(
      90,
      alpha: _drag.pressProgress,
      dualPeak: false,
    );

    // 紧凑胶囊总宽：每格 _itemWidth + 左右 4dp 内边距（参考项目
    //   totalWidthPx = Row 宽，tabWidthPx = (W-8)/n）。
    _tabWidth = _itemWidth;
    final double totalWidth = _itemWidth * widget.items.length + 8;

    // pill 按压"跃起"：背景层放大到 (totalWidth×s, 64×s)。
    // 关键：不套 Transform.scale —— 那会把 BackdropBlur 的 localToGlobal
    // 一并缩放而绘制 dst 不缩放，导致采样错位（页面分界线错位）。
    // 用真实放大尺寸做布局，采样/绘制天然对齐（参考项目 drawBackdrop 层内 scale）。
    final double pillScale = _containerScale();
    final double pillW = totalWidth * pillScale;
    final double pillH = _pillHeight * pillScale;

    // 整个胶囊可横向拖拽（参考项目：底栏覆盖 pager，拖拽优先于页面滑动）。
    // 用 Listener 手动跟踪 pointer（绕过 gesture arena 竞争 + touch slop），
    // 拖动即时跟手（updateValueDirect），松手弹簧吸附 + 切页。
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: SizedBox(
        width: totalWidth,
        height: _pillHeight,
        // Clip.none：pill 按压放大/阴影超出胶囊本体时可见（参考项目不裁剪）。
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            // ── 底栏本体（pill 毛玻璃 + 可见标签行），被 _barBackdrop 捕获 ──
            // 方案 C：捕获【整个底栏】的渲染 → 指示器 combined 采样它 = 透过玻璃
            // 看到底栏本体 1:1（无错位/无双层）。此捕获层即本体、可见、不被
            // Opacity 包裹 → MiuixLayerBackdropCapture 快照必定有效。
            // 【外扩】capture 区域左右各扩 pill 放大余量（_pillPadX/_pillPadY）：
            //   否则 pill 按压放大(1+16dp/宽)超出 Positioned.fill 区域被快照裁剪，
            //   视觉上毛玻璃不随按压跃起、边缘被切。pill 用显式 Positioned 相对
            //   capture 中心居中（不能用 Center —— 会让 pill 在扩大的 Stack 里错位）。
            // 边缘拉伸横线由 shader 的"越界归零"消除。
            // blur 关（_blurOn=false）时本体照常显示但不包 capture（零捕获成本）。
            Positioned(
              left: -_pillPadX,
              top: -_pillPadY,
              right: -_pillPadX,
              bottom: -_pillPadY,
              child: _blurOn
                  ? MiuixLayerBackdropCapture(
                      backdrop: _barBackdrop,
                      child: _buildBarBody(
                        pillW,
                        pillH,
                        totalWidth,
                        baseHighlight,
                        containerColor,
                        isDark,
                      ),
                    )
                  : _buildBarBody(
                      pillW,
                      pillH,
                      totalWidth,
                      baseHighlight,
                      containerColor,
                      isDark,
                    ),
            ),
            // ── 拖拽指示器（几何重构：无 Transform.scale，布局即放大后尺寸，
            //    保证 FlutterFragCoord 与 localToGlobal 同坐标系 → 折射映射正确）──
            Positioned(
              // 基础位置 (4 + value*tabWidth, 4)，尺寸 W×56；
              // 放大后 W'=W*sx, H'=56*sy，中心对齐 → left/top 外扩一半差。
              left: 4 + _drag.value * _tabWidth - _indicatorHalfDelta(true),
              top: 4 - _indicatorHalfDelta(false),
              child: _buildIndicator(pillHighlight, containerColor, isDark),
            ),
          ],
        ),
      ),
    );
  }

  /// 底栏本体（pill 毛玻璃 + 可见标签行）布局。
  /// capture 区域 = 外扩 _pillPadX/_pillPadY 后的矩形：
  ///   cw = totalWidth + 2×padX，ch = _pillHeight + 2×padY（原 LayoutBuilder
  ///   拿到的 constraints 即此尺寸，直接计算等效且省一层布局）。
  Widget _buildBarBody(
    double pillW,
    double pillH,
    double totalWidth,
    Highlight baseHighlight,
    Color containerColor,
    bool isDark,
  ) {
    final double cw = totalWidth + _pillPadX * 2;
    const double ch = _pillHeight + _pillPadY * 2;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Stack(
      children: <Widget>[
        // ── 容器层：毛玻璃胶囊（按压随 pillScale 放大"跃起"）──
        // 相对 capture 中心对齐：left = (cw-pillW)/2，top = (ch-pillH)/2。
        Positioned(
          left: (cw - pillW) / 2,
          top: (ch - pillH) / 2,
          width: pillW,
          height: pillH,
          child: IgnorePointer(
            child: _buildPill(
              baseHighlight,
              containerColor,
              isDark,
              // stadium 圆角 = 高/2（放大后跟随 pillH）。
              radius: pillH / 2,
            ),
          ),
        ),
        // ── 可见标签行（onSurface 色，点击由 Listener 统一判定）──
        // 固定于底栏本体位置（capture 内偏移 = pad）。
        Positioned(
          left: _pillPadX,
          top: _pillPadY,
          width: totalWidth,
          height: _pillHeight,
          child: Padding(
            // 对齐参考项目 Row.padding(4.dp)：每格宽 = (W-8)/n = _tabWidth，
            // 与指示器 left = 4 + value*_tabWidth 精确对齐。
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < widget.items.length; i++)
                  Expanded(child: _buildTab(i, colors.onSurface)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 容器胶囊（参考项目 FloatingBottomBar.kt:322-341 drawBackdrop 容器层）。
  Widget _buildPill(
    Highlight highlight,
    Color containerColor,
    bool isDark, {
    required double radius,
  }) {
    // 胶囊半圆半径 = 高/2（与 StadiumBorder clip 一致，避免圆角缝隙露出
    // 直角模糊背景/页面背景）。
    final BorderRadius pillRadius = BorderRadius.all(Radius.circular(radius));
    final Widget tint = DecoratedBox(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: pillRadius,
      ),
      child: const SizedBox.expand(),
    );
    Widget pill = _blurOn
        ? BackdropBlur(
            backdrop: widget.backdrop!,
            shape: const StadiumBorder(),
            blurRadius: 16,
            colors: MiuixBlurDefaults.blurColors(saturation: 1.5),
            child: tint,
          )
        : tint;
    pill = DualPeakHighlight(
      highlight: highlight,
      shape: const StadiumBorder(),
      child: pill,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: pillRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF000000)
                .withValues(alpha: isDark ? 0.2 : 0.1),
            blurRadius: 10,
            offset: Offset.zero,
          ),
        ],
      ),
      child: pill,
    );
  }

  Widget _buildTab(int index, Color accent) {
    // 标签按压缩放 lerp(1, 1.2, press)。
    final double tabScale = 1 + 0.2 * _drag.pressProgress;
    // 无 GestureDetector：tap/拖拽均由外层 Listener 统一判定，
    // 避免手势竞技场（onTap）与外层拖拽竞争导致点击时灵时不灵。
    return Transform.scale(
      scale: tabScale,
      child: _buildTabLabel(index, accent),
    );
  }

  /// 标签（图标+文字，无交互，供可见标签行与快照层共用）。
  Widget _buildTabLabel(int index, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiuixIcon(vector: widget.items[index].icon, size: 24, tint: color),
        MiuixText(
          widget.items[index].label,
          style: MiuixTheme.of(context).textStyles.body2,
          color: color,
          maxLines: 1,
          // 显式关闭文本装饰：防止任何继承/默认下划线干扰
          // （用户反馈文字下方出现双横黄线）。
          decoration: TextDecoration.none,
        ),
      ],
    );
  }

  Widget _buildIndicator(
    Highlight highlight,
    Color containerColor,
    bool isDark,
  ) {
    final double press = _drag.pressProgress;
    final double w = math.max(_tabWidth, 1);
    const double h = 56;

    // 按压缩放（78/56）+ 速度形变（FloatingBottomBar.kt:415-418）。
    final (double sx, double sy) = _indicatorScale();
    final double wScaled = w * sx;
    final double hScaled = h * sy;
    // 放大后胶囊半径（非均匀形变近似按 min/2；参考项目 graphicsLayer 缩放后
    //   stadium 半径 = min(wScaled,hScaled)/2）。
    final double radius = math.min(wScaled, hScaled) / 2;

    // onDrawSurface（参考项目 FloatingBottomBar.kt:420-427）两层：
    //   ① 浅色黑 0.1×(1-p) / 深色白 0.1×(1-p)；② 叠加黑 0.03×p。
    final Color surfaceBase =
        (isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000)).withValues(
          alpha: 0.1 * (1 - press),
        );
    final Color surface = Color.alphaBlend(
      const Color(0xFF000000).withValues(alpha: 0.03 * press),
      surfaceBase,
    );

    Widget indicator = SizedBox(
      width: wScaled,
      height: hScaled,
      child: _blurOn
          // 指示器：边缘折射（中间极轻放大 + 边缘折射/彩虹/沿边缘流动）。
          // 不套 Transform.scale：尺寸即放大后，shader 内逆缩放 SDF（见 lens.frag）。
          ? LensRefraction(
              backdrop: widget.backdrop!,
              overlayBackdrop: _barBackdrop,
              baseRadius: h / 2,
              scaleX: sx,
              scaleY: sy,
              midRefraction: 0, // 中心无折射（仅边缘带折射；中间直接透出底栏本体）
              edgeRefraction: -10 * press, // 边缘带折射（向内，仅活动态）
              edgeWidth: 7, // 边缘带宽度 dp
              chromaticAberration: 0.5 * press, // 彩虹强度（仅活动态）
              flowAmount: 6 * press, // 沿边缘流动幅度 dp（仅活动态）
              flowDir: _flowDir, // 右移逆时针 / 左移顺时针
              depthEffect: false, // 关闭 depthEffect：避免中心法线归一化的方向跳变分割线
              child: Stack(
                children: <Widget>[
                  // onDrawSurface：黑 0.1(1-progress) + 黑 0.03·progress。
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.all(Radius.circular(radius)),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // 高光边框（α=press）。
                  if (press > 0)
                    Positioned.fill(
                      child: DualPeakHighlight(
                        highlight: highlight,
                        shape: const StadiumBorder(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: containerColor,
                borderRadius: BorderRadius.all(Radius.circular(radius)),
              ),
              child: const SizedBox.expand(),
            ),
    );

    // 内阴影（8dp×press，黑 0.15，offset 向下 radius；随放大后尺寸）。
    indicator = InnerShadow(
      shape: const StadiumBorder(),
      radius: 8 * press,
      color: const Color(0xFF000000).withValues(alpha: 0.15),
      alpha: press,
      offset: Offset(0, 8 * press),
      child: indicator,
    );

    // 按 stadium 裁剪指示框整体（参考项目 drawBackdrop shape=pillShape 也是胶囊形，
    // 否则 LensRefraction 的 clipRect 直角矩形会在胶囊四角外露出方形页面背景）。
    indicator = ClipPath(
      clipper: const ShapeBorderClipper(shape: StadiumBorder()),
      child: indicator,
    );

    return indicator;
  }

  /// 指示器形变系数 (sx, sy)：按压缩放 78/56 × velocity 形变。
  (double, double) _indicatorScale() {
    final double velocity = _drag.velocity / 10.0;
    final double vX = (velocity * 0.75).clamp(-0.2, 0.2);
    final double vY = (velocity * 0.25).clamp(-0.2, 0.2);
    return (_drag.scaleX / (1 - vX), _drag.scaleY * (1 - vY));
  }

  /// 指示器放大后半宽/半高差（用于 Positioned 中心对齐外扩）。
  /// [horizontal] = true 返回 (W' - W)/2，false 返回 (H' - 56)/2（均≥0）。
  double _indicatorHalfDelta(bool horizontal) {
    final double w = math.max(_tabWidth, 1);
    final (double sx, double sy) = _indicatorScale();
    if (horizontal) return math.max(w * sx - w, 0) / 2;
    return math.max(56 * sy - 56, 0) / 2;
  }

  // ── Listener 手动拖拽（A 方案：绕过 gesture arena，即时跟手）──
  // 对齐参考项目 DragGestureInspector.kt：onDragStart（按下）立即 press 缩放；
  // 移动跟手，value clamp [0,maxValue] → 拖到左右边界直接停住、不越界、不反弹；
  // 松手 round 归位到最近 index。

  void _onPointerDown(PointerDownEvent e) {
    _dragStartX = e.localPosition.dx;
    _dragStartValue = _drag.value;
    // 重置速度估算（本次按下从头算，velocity 弹簧保持上一轮回正状态继续回正）。
    _lastMoveTime = null;
    _lastMoveValue = _drag.value;
    _smoothVel = 0;
    _dragActive = false;
    // 按下落在【任意 tab 内容区】即 press（即时按压反馈，不卡手）。
    // 点其它 tab 也是先按压、松手切页时由 animateToValue 承接按压态，
    // 避免旧版"只有当前指示框内按下才缩放，按其它 tab 无反应"的卡手感。
    _pressedOnIndicator = _isOnAnyTab(e.localPosition.dx);
    if (_pressedOnIndicator) {
      _drag.press();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final double dx = e.localPosition.dx - _dragStartX;
    if (!_dragActive) {
      if (dx.abs() < kTouchSlop) return;
      _dragActive = true;
      // 从其它 tab 起手的拖拽：进入拖拽态时也要补 press（拖拽需按压缩放）。
      if (!_pressedOnIndicator) {
        _pressedOnIndicator = true;
        _drag.press();
      }
    }
    if (_tabWidth <= 0) return;
    // 即时跟手；clamp 使拖到左右边界直接停住（无橡皮筋越界）。
    if (dx != 0) _flowDir = dx > 0 ? 1.0 : -1.0;

    // ── 速度估算并喂入 _drag.updateVelocity（激活 _indicatorScale 的速度形变）──
    // 用 (Δvalue)/(Δt) 估算，单位 value/秒（0..n-1 区间）；先 EMA 低通
    // （时间常数 ~50ms）滤掉相邻事件噪声，再交给连续弹簧 → 形变柔和丝滑。
    final double newValue = _dragStartValue + dx / _tabWidth;
    final Duration now = e.timeStamp;
    if (_lastMoveTime != null) {
      final double dt = (now - _lastMoveTime!).inMicroseconds / 1e6; // 秒
      if (dt > 0.001) {
        final double v = (newValue - _lastMoveValue) / dt; // value/秒
        // 一阶低通：alpha = dt/(dt+τ)，τ≈50ms；事件越密平滑越强。
        final double alpha = dt / (dt + 0.05);
        _smoothVel += (v - _smoothVel) * alpha;
        _drag.updateVelocity(_smoothVel);
      }
    }
    _lastMoveTime = now;
    _lastMoveValue = newValue;
    // ── 新增结束 ──

    _drag.updateValueDirect(newValue);
  }

  void _onPointerUp(PointerUpEvent e) => _endDrag();

  void _onPointerCancel(PointerCancelEvent e) => _endDrag();

  /// 判断按下位置是否落在【任一 tab 内容区】（Row padding 内侧，
  /// [4, 4+n×_tabWidth)）。用于按下即反馈：不限定当前指示框，避免
  /// "按其它 tab 无反应"的卡手感（tab 内容缩放 / 指示框缩放由 press 统一驱动）。
  bool _isOnAnyTab(double dx) {
    if (_tabWidth <= 0) return false;
    return dx >= 4 && dx < 4 + _tabWidth * widget.items.length;
  }

  /// 按下位置对应的 tab 索引（Row 有 4px padding，每格宽 _tabWidth）。
  int _tabIndexAt(double dx) {
    if (_tabWidth <= 0) return widget.selectedIndex;
    final int idx = ((dx - 4) / _tabWidth).floor();
    return idx.clamp(0, widget.items.length - 1);
  }

  void _endDrag() {
    if (!_dragActive) {
      // 未拖拽 = tap：根据按下位置判定目标 tab。
      // down 已在任意 tab 上 press（按压态）；松手：
      //   点当前项 → 仅 release 回正；
      //   点其它项 → 保持按压直接切页（animateToValue 内部 press 幂等保持，
      //     位置滑动接近目标才 release → 视觉：按住放大 → 滑动 → 到位落下，连贯）。
      final int tabIndex = _tabIndexAt(_dragStartX);
      _drag.updateVelocity(0); // 松手：速度形变随弹簧回正
      if (tabIndex != widget.selectedIndex) {
        _drag.animateToValue(tabIndex.toDouble());
        _selfAnimatedIndex = tabIndex;
        widget.onSelected(tabIndex);
      } else if (_pressedOnIndicator) {
        _pressedOnIndicator = false;
        _drag.release();
      }
      return;
    }
    _dragActive = false;
    _pressedOnIndicator = false;
    _drag.updateVelocity(0); // 松手：速度形变随弹簧回正
    final int target = _drag.value.round().clamp(0, widget.items.length - 1);
    _drag.animateToValue(target.toDouble());
    if (target != widget.selectedIndex) {
      _selfAnimatedIndex = target;
      widget.onSelected(target); // 拖拽松手 → 切页
    }
  }
}
