// lib/presentation/features/wallpaper/spatial_ui_kit.dart
// 编号：C-71 空间图片编辑器 · UI 原语库（自 P-24 提取）
//
// ★ v2.1.0 项目整理：以下 15 个控件原本内联在 P-24 文件末尾（840 行），
//   它们与 State 的 50+ 个字段【零耦合】—— 只吃构造参数、只吐 Widget，
//   放在同一个文件里纯粹是就地生长的结果。提取后：
//     · P-24 从 3590 行降到 2745 行，只留「状态 + 逻辑 + 骨架」；
//     · 控件可被其它页面复用，改控件样式不必穿越整个编辑器；
//     · 二者可以各自演进，互不制造 diff 噪音。
//
// 命名：这些控件此前是 library-private（`_MiSlider` 等），跨文件引用要求
//   公开命名，故统一加 `Spatial` 前缀。**行为与样式一行未改**（纯搬移 + 改名），
//   唯一的实质改动是顶部补了本文件的 import。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../core/depth/depth_layer_splitter.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/wallpaper/wallpaper_history_service.dart';
import '../../widgets/c21_collapsing_title_bar.dart';

/// 涂刷轨迹的实时反馈：红色 = 画笔（加主体），蓝色 = 橡皮（去主体）。
///
/// 只画本次轨迹（归一化坐标 + 归一化半径），不做任何像素写入 ——
/// 真正的落盘在松手后统一进行。
class SpatialBrushTrailPainter extends CustomPainter {
  const SpatialBrushTrailPainter({
    required this.trail,
    required this.radius,
    required this.erase,
  });

  final List<Offset> trail;
  final double radius;
  final bool erase;

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty || size.isEmpty) return;
    final double r = radius * size.shortestSide;
    final Paint p = Paint()
      ..color = (erase
              ? const Color(0xFF3B82F6)
              : const Color(0xFFFF3B30))
          .withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    if (trail.length == 1) {
      canvas.drawCircle(
        Offset(trail.first.dx * size.width, trail.first.dy * size.height),
        r,
        p,
      );
      return;
    }
    for (int i = 1; i < trail.length; i++) {
      final Offset a =
          Offset(trail[i - 1].dx * size.width, trail[i - 1].dy * size.height);
      final Offset b =
          Offset(trail[i].dx * size.width, trail[i].dy * size.height);
      // 用圆头粗线把相邻点连起来 —— 与 stamp 的插值行为一致，不会出现断续
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = p.color
          ..strokeWidth = r * 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SpatialBrushTrailPainter old) =>
      old.trail.length != trail.length ||
      old.radius != radius ||
      old.erase != erase;
}

/// 层素材预览：棋盘格衬底 + 指定图层的原始像素。
///
/// 为什么要看这个：深度图预览走的是另一条渲染路径（逐像素 shader），它正确
/// 并不能推出分层渲染正确。真正参与合成的是【层图】—— 里面含 alpha、含"猜"
/// 出来的填充内容，而这一切在深度图预览里完全看不到。
class SpatialLayerMaterialView extends StatelessWidget {
  const SpatialLayerMaterialView({
    super.key,
    required this.layerSet,
    required this.index,
  });

  final DepthLayerSet layerSet;
  final int index;

  @override
  Widget build(BuildContext context) {
    final List<DepthLayer> ls = layerSet.layers;
    if (ls.isEmpty) return const SizedBox.shrink();
    final DepthLayer l = ls[index.clamp(0, ls.length - 1)];
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 棋盘格在下：层的 alpha 为 0 处会透出它，一眼可辨。
        const CustomPaint(painter: SpatialCheckerPainter()),
        RawImage(image: l.image, fit: BoxFit.fill),
      ],
    );
  }
}

/// 棋盘格衬底（让 alpha=0 的区域一眼可辨）。
class SpatialCheckerPainter extends CustomPainter {
  const SpatialCheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 14;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF43434E),
    );
    final Paint dark = Paint()..color = const Color(0xFF2C2C34);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final int ix = (x / cell).floor();
        final int iy = (y / cell).floor();
        if ((ix + iy).isEven) continue;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 焦点标记：小圆点 + 描边，指示当前"钉住"的层。
class SpatialFocusMarker extends StatelessWidget {
  const SpatialFocusMarker({
    super.key,
    required this.color,
    required this.outline,
  });

  final Color color;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: outline.withValues(alpha: 0.9), width: 2),
        ),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

/// S-40 历史列表的一行：缩略图 + 时间 / 占用 + 导出 / 删除。
///
/// 缩略图由每行自己异步读、读完 setState —— 列表可能有 20 条，
/// 一次性全读进内存没有必要；`cacheWidth` 限制解码宽度，
/// 避免把整张 4K 原图解码进内存（那正是"缓存一直涨"的老问题）。
class SpatialHistoryTile extends StatefulWidget {
  const SpatialHistoryTile({
    super.key,
    required this.entry,
    required this.timeText,
    required this.sizeText,
    required this.isCurrent,
    required this.onOpen,
    required this.onExport,
    required this.onDelete,
  });

  final WallpaperHistoryEntry entry;
  final String timeText;
  final String sizeText;
  final bool isCurrent;
  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  State<SpatialHistoryTile> createState() => SpatialHistoryTileState();
}

class SpatialHistoryTileState extends State<SpatialHistoryTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    unawaited(
      WallpaperHistoryService.readFile(widget.entry.previewPath)
          .then((Uint8List? b) {
        if (mounted) setState(() => _thumb = b);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final body1 = MiuixTheme.of(context).textStyles.body1;
    final body2 = MiuixTheme.of(context).textStyles.body2;
    final Uint8List? t = _thumb;
    return Row(
      children: <Widget>[
        // 点缩略图 / 文字区 → 载入该条继续编辑
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: t == null
                        ? ColoredBox(
                            color: colors.onSurfaceVariantSummary
                                .withValues(alpha: 0.18),
                          )
                        : Image.memory(t, fit: BoxFit.cover, cacheWidth: 168),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          MiuixText(widget.timeText, style: body1),
                          if (widget.isCurrent) ...<Widget>[
                            const SizedBox(width: 6),
                            MiuixText(
                              '编辑中',
                              style: body2,
                              color: colors.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      MiuixText(
                        widget.sizeText,
                        style: body2,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        C21CapsuleIconButton(
          key: ValueKey<String>('wallpaper.history.export.${widget.entry.id}'),
          icon: appIcon('download'),
          tooltip: '导出到相册',
          onTap: widget.onExport,
        ),
        C21CapsuleIconButton(
          key: ValueKey<String>('wallpaper.history.delete.${widget.entry.id}'),
          icon: appIcon('delete'),
          tooltip: '删除',
          onTap: widget.onDelete,
        ),
      ],
    );
  }
}

// ── 澎湃样式的三个基础控件（签名兼容 Miuix，供整体替换）──────────
//
// ★ 为什么做成"签名兼容"而不是逐个重写调用点
//   上一版只换了外壳（顶栏 / 工具行），页面上仍有 10 个滑杆、4 个开关、
//   18 个按钮是 Miuix 的**设置项**样式 —— 所以整页看起来是拼的，不是复刻。
//   这里把参数签名对齐（insideMargin / summary / colors 这些收下但不用），
//   调用点只改一个类名就能整体切换，不会再出现"漏了几个没改"。

/// 参数滑杆（澎湃样式）。兼容 `MiuixSliderPreference` 的调用签名。
class SpatialMiSlider extends StatelessWidget {
  const SpatialMiSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onValueChange,
    this.summary,
    this.enabled = true,
    this.insideMargin,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onValueChange;

  /// 参数名下的那句解释（澎湃也会给一行小字说明当前值意味着什么）。
  final String? summary;
  final bool enabled;

  /// 兼容 Miuix 的调用签名；本组件自己控边距，收了不用。
  final EdgeInsets? insideMargin;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // 禁用态：整体压暗，比"灰字"更接近澎湃的处理
      opacity: enabled ? 1.0 : 0.38,
      child: SpatialParamSlider(
        title: title,
        subtitle: summary,
        value: value,
        min: min,
        max: max,
        valueText: value.toStringAsFixed(2),
        onChanged: enabled ? onValueChange : (double _) {},
      ),
    );
  }
}

/// 开关（澎湃样式）：细长药丸 + 白色圆钮。兼容 `MiuixSwitchPreference`。
class SpatialMiSwitch extends StatelessWidget {
  const SpatialMiSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.summary,
    this.insideMargin,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? summary;

  /// 兼容参数，收了不用。
  final EdgeInsets? insideMargin;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MiuixText(title, style: MiuixTheme.of(context).textStyles.body1),
                if (summary != null) ...<Widget>[
                  const SizedBox(height: 2),
                  MiuixText(
                    summary!,
                    style: MiuixTheme.of(context).textStyles.body2,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 46,
              height: 26,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: value
                    ? colors.primary
                    : colors.onSurface.withValues(alpha: 0.18),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFFFFFF),
                  ),
                  child: SizedBox(width: 20, height: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按钮（澎湃样式）。兼容 `MiuixButton` 的调用签名。
///
/// 选中态**沿用旧调用的 `colors` 参数**来判断 —— 调用方传了
/// `buttonColorsPrimary` 就是选中，不必再逐个改调用点。
class SpatialMiButton extends StatelessWidget {
  const SpatialMiButton({
    super.key,
    required this.child,
    this.onPressed,
    this.colors,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// 兼容参数：非 null 即"选中/主操作"，本组件据此换配色。
  final Object? colors;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null;
    final bool primary = colors != null;
    final MiuixColors mi = MiuixTheme.of(context).colors;
    return Opacity(
      opacity: on ? 1.0 : 0.35,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: primary ? SpatialMiAccent.fill : const Color(0x1FFFFFFF),
          ),
          child: Center(
            // ★ 必须【无条件】给文字定色。
            //   这一页虽然用 MiuixThemeController 强制了深色，但外面那层
            //   Material 仍带着 App 浅色主题的 DefaultTextStyle（深字）——
            //   透传的 Text 会继承它，深字压在深底上就等于"文字不显示"。
            //   旧版 MiuixButton 自己管颜色，所以没暴露这个问题。
            child: DefaultTextStyle(
              style: TextStyle(
                color: primary ? const Color(0xFF1A1A1A) : mi.onSurface,
                fontSize: 14,
                fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 澎湃那套按钮/控件用到的两个固定色（不跟主题走）。
abstract final class SpatialMiAccent {
  /// 主操作 / 选中：金色
  static const Color fill = Color(0xFFFFD54F);
}

/// S-41 摇杆：拖这个盘控制晃动方向（-1..1）。
///
/// 为什么需要它：
///   · Web / 桌面根本没有传感器；
///   · 真机上也有用户不想一直举着手机晃；
///   · 它同时也是**无障碍输入** —— 不方便动手机的人一样能用。
///
/// ★ 松手【不回正】：调壁纸时更需要把某个角度定住慢慢看，
///   而不是像游戏摇杆那样弹回中间。要回正请点「回正」。
class SpatialJoystickPad extends StatelessWidget {
  const SpatialJoystickPad({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Offset value;
  final ValueChanged<Offset> onChanged;

  static const double _size = 132;
  static const double _knob = 36;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    const double r = (_size - _knob) / 2;
    return Center(
      child: GestureDetector(
        key: const ValueKey<String>('wallpaper.joystick'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (DragStartDetails d) => _report(d.localPosition, r),
        onPanUpdate: (DragUpdateDetails d) => _report(d.localPosition, r),
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.onSurfaceVariantSummary.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Transform.translate(
                offset: Offset(value.dx * r, value.dy * r),
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _report(Offset local, double r) {
    final Offset d = local - const Offset(_size / 2, _size / 2);
    onChanged(
      Offset((d.dx / r).clamp(-1.0, 1.0), (d.dy / r).clamp(-1.0, 1.0)),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 编辑器 UI 组件（对齐小米澎湃相册编辑器）
//
// 结构：
//   顶栏     ✕ · ↶ · ↷ · [保存] · ⋮        （SpatialRoundIconButton / SpatialSavePill）
//   控件区   当前子工具的滑卡 / 开关
//   二级行   子工具 —— 圆角方块 + 图标 + 文字，选中描一圈高亮环（SpatialToolTile）
//   一级行   主分类 —— 更小，选中用胶囊底色（SpatialCategoryPill）
// ══════════════════════════════════════════════════════════════

/// 顶栏圆形描边图标按钮（澎湃那套：一圈细描边 + 居中图标）。
class SpatialRoundIconButton extends StatelessWidget {
  const SpatialRoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final MiuixVectorIcon icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool on = onTap != null;
    final Color fg = on
        ? colors.onSurface
        : colors.onSurfaceVariantSummary.withValues(alpha: 0.35);
    // 用 Semantics 而不是 material 的 Tooltip —— 本页只引 widgets 层，
    // 不为了一个悬浮提示把整个 material 拉进来。
    return Semantics(
      label: tooltip,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: fg.withValues(alpha: on ? 0.45 : 0.2),
                width: 1.2,
              ),
            ),
            child: Center(
              child: MiuixIcon(vector: icon, size: 19, tint: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏右侧的胶囊按钮（澎湃的「保存」）。
class SpatialSavePill extends StatelessWidget {
  const SpatialSavePill({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool on = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: on
              ? colors.onSurface.withValues(alpha: 0.12)
              : colors.onSurface.withValues(alpha: 0.05),
        ),
        child: MiuixText(
          '保存',
          style: MiuixTheme.of(context).textStyles.body1,
          color: on
              ? colors.onSurface
              : colors.onSurfaceVariantSummary.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

/// 一级工具（主分类）：图标 + 文字，选中时整块变成胶囊底色。
class SpatialCategoryPill extends StatelessWidget {
  const SpatialCategoryPill({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final MiuixVectorIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Color fg =
        selected ? colors.onSurface : colors.onSurfaceVariantSummary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? colors.onSurface.withValues(alpha: 0.14)
              : const Color(0x00000000),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MiuixIcon(vector: icon, size: 21, tint: fg),
            const SizedBox(height: 4),
            MiuixText(
              label,
              style: MiuixTheme.of(context).textStyles.body2,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级工具（子工具）：圆角方块 + 图标 + 文字，**选中描一圈高亮环**。
///
/// 这一圈环是澎湃编辑器最显眼的识别特征 —— 用它而不是填充色，
/// 是为了让"选中"在深色底上也一眼可辨，同时不遮挡图标本身。
class SpatialToolTile extends StatelessWidget {
  const SpatialToolTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final MiuixVectorIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // 澎湃的高亮环是暖金色；这里沿用主题的 primary，观感一致又不写死颜色。
    final Color ring = colors.primary;
    final Color fg =
        selected ? colors.onSurface : colors.onSurfaceVariantSummary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        // ★ 固定 68×68 圆角方块（澎湃的工具块就是这个尺寸与圆角）。
        //   之前是按内容撑开，块的大小会随文字长短变化，一列看过去参差不齐。
        width: 68,
        height: 68,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: colors.onSurface.withValues(alpha: selected ? 0.10 : 0.05),
          border: Border.all(
            color: selected ? ring : const Color(0x00000000),
            width: 1.6,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            MiuixIcon(vector: icon, size: 22, tint: fg),
            const SizedBox(height: 5),
            MiuixText(
              label,
              style: MiuixTheme.of(context).textStyles.body2,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }
}

/// 参数滑卡（澎湃风格）：圆角轨道 + 圆形滑块，左侧标题、右侧数值。
///
/// 与 MiuixSliderPreference 的差别：那个是"设置项"比例（整行、大留白），
/// 编辑器里参数是密集高频操作，所以轨道更矮、数值靠右对齐、上下留白更小。
class SpatialParamSlider extends StatelessWidget {
  const SpatialParamSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.valueText,
    this.subtitle,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? valueText;

  /// 参数名下的一行小字（说明当前值意味着什么）。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final double t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              MiuixText(
                title,
                style: MiuixTheme.of(context).textStyles.body2,
                color: colors.onSurfaceVariantSummary,
              ),
              const Spacer(),
              MiuixText(
                valueText ?? value.toStringAsFixed(2),
                style: MiuixTheme.of(context).textStyles.body2,
                color: colors.onSurface,
              ),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            MiuixText(
              subtitle!,
              style: MiuixTheme.of(context).textStyles.body2,
              color: colors.onSurfaceVariantSummary,
            ),
          ],
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              const double knob = 20;
              final double usable = (c.maxWidth - knob).clamp(1.0, 1e6);
              void seek(Offset local) => onChanged(
                    (min + (local.dx - knob / 2) / usable * (max - min))
                        .clamp(min, max),
                  );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails d) => seek(d.localPosition),
                onHorizontalDragUpdate: (DragUpdateDetails d) =>
                    seek(d.localPosition),
                child: SizedBox(
                  height: 30,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      // 轨道
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: colors.onSurface.withValues(alpha: 0.14),
                        ),
                      ),
                      // 已选段
                      Container(
                        height: 6,
                        width: knob / 2 + usable * t,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: colors.primary.withValues(alpha: 0.55),
                        ),
                      ),
                      // 滑块
                      Transform.translate(
                        offset: Offset(usable * t, 0),
                        child: Container(
                          width: knob,
                          height: knob,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: colors.primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
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
}
