// lib/presentation/features/flow/vyuh_flow_node_card.dart
// 编号:P-11 v2 域 —— 节点自渲染卡(Node.widgetBuilder;完整控制视觉)
// 说明:
//   - 背景/边框/选中/锁定/徽标/批注圆点全自绘;选中态与位置变化经
//     flutter_mobx Observer 即时重绘(自渲染通道不在库内 Observer 内);
//   - 配色实时取 MiuixTheme(vyuh_flow_theme.kindAccent);
//   - 尺寸与 node.size 一致(连线锚点依赖);端口由 vyuh NodeContainer
//     叠加在卡边界;
//   - buildLaneNodeCard:泳道(GroupNode 自绘)——虚线圆角分区 + 标题 chip
//     + 拉伸跟随(node.size Observer);阶段2。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../domain/entities/flow_doc.dart';
import 'vyuh_flow_theme.dart';

/// 节点自渲染卡(供 Node(widgetBuilder:…))。
Widget buildVyuhFlowNodeCard(BuildContext context, Node<FlowNodeData> node) {
  return Observer(builder: (BuildContext _) => _card(context, node));
}

/// 泳道自渲染卡(供 GroupNode(widgetBuilder:…);虚线框/标题 chip 自绘)。
Widget buildLaneNodeCard(BuildContext context, Node<FlowNodeData> node) {
  return Observer(builder: (BuildContext _) => _laneCard(context, node));
}

/// 泳道:虚线圆角分区 + 左上标题 chip(+ 锁定/选中/hover 态)。
Widget _laneCard(BuildContext context, Node<FlowNodeData> node) {
  final FlowNodeData d = node.data;
  final MiuixColors c = MiuixTheme.of(context).colors;
  final bool dark = c.surface.computeLuminance() < 0.5;
  final Size sz = node.size.value;
  final bool selected = node.isSelected;
  // POC vendor 补丁(v0.5.0 hover):悬停虚线变实线(提示可交互;触摸恒 false)。
  final bool hovered = node.isHovered;

  // 主色:自定义色优先,否则主题主色;派生 fill/stroke。
  final bool hasCustom = d.customStyled && d.customColor != 0;
  final Color accent =
      hasCustom ? Color(d.customColor) : laneStroke(c).withValues(alpha: 1);
  final Color stroke = selected
      ? c.primary
      : hovered
      ? c.primary.withValues(alpha: 0.75)
      : hasCustom
      ? accent.withValues(alpha: dark ? 0.75 : 0.55)
      : laneStroke(c);
  final Color fill = selected
      ? c.primary.withValues(alpha: 0.07)
      : hovered
      ? c.primary.withValues(alpha: 0.08)
      : hasCustom
      ? accent.withValues(alpha: 0.05)
      : laneFill(c);
  final Color chipBg = hasCustom ? accent : c.primaryContainer;
  final Color chipFg = hasCustom
      ? (accent.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
      : c.onPrimaryContainer;

  return SizedBox(
    width: sz.width,
    height: sz.height,
    child: CustomPaint(
      painter: _LaneFramePainter(
        stroke: stroke,
        fill: fill,
        dashed: !selected && !hovered, // 选中/悬停 → 实线高亮。
        radius: 14,
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 10,
            top: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    d.title.isEmpty ? '泳道' : d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: chipFg,
                    ),
                  ),
                ),
                if (d.locked) ...<Widget>[
                  const SizedBox(width: 5),
                  Icon(
                    Icons.lock_outline,
                    size: 11,
                    color: c.onSurfaceVariantActions,
                  ),
                ],
              ],
            ),
          ),
          if (d.note.isNotEmpty)
            Positioned(
              right: 12,
              bottom: 8,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: math.max(0, sz.width - 120),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: c.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  d.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: c.onSurfaceVariantSummary),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 泳道分区边框(虚线圆角 + 极淡填充;选中 → 实线主题主色)。
class _LaneFramePainter extends CustomPainter {
  const _LaneFramePainter({
    required this.stroke,
    required this.fill,
    required this.dashed,
    required this.radius,
  });

  final Color stroke;
  final Color fill;
  final bool dashed;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    if (fill.a > 0) {
      canvas.drawRRect(rrect, Paint()..color = fill);
    }
    final Paint line = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    if (!dashed) {
      canvas.drawRRect(rrect, line);
      return;
    }
    // 虚线:沿圆角路径分段。
    const double dash = 7;
    const double gap = 4;
    final Path path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final double len = math.min(dash, metric.length - dist);
        canvas.drawPath(metric.extractPath(dist, dist + len), line);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_LaneFramePainter old) =>
      old.stroke != stroke ||
      old.fill != fill ||
      old.dashed != dashed ||
      old.radius != radius;
}

Widget _card(BuildContext context, Node<FlowNodeData> node) {
  final FlowNodeData d = node.data;
  final MiuixColors c = MiuixTheme.of(context).colors;
  final bool dark = c.surface.computeLuminance() < 0.5;
  final Color accent = kindAccent(c, d.kind);
  final Size sz = node.size.value;
  final bool selected = node.isSelected;
  // POC vendor 补丁(v0.5.0 hover):鼠标悬停视觉(选中优先;触摸恒 false)。
  final bool hovered = node.isHovered;

  final Color cardBg =
      dark ? c.surfaceContainerHigh : c.surfaceContainerHigh;
  final Color text = c.onSurface;
  final Color sub = c.onSurfaceVariantSummary;
  final Color borderColor = selected
      ? c.primary
      : hovered
      ? c.primary.withValues(alpha: 0.8)
      : c.dividerLine;
  final double borderWidth = selected ? 2 : (hovered ? 1.6 : 1);

  return SizedBox(
    width: sz.width,
    height: sz.height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: hovered && !selected
            ? <BoxShadow>[
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: <Widget>[
            // 顶部类型色条。
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: Container(height: 3, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _kindLabel(d.kind),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                      if (d.badge > 0) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${d.badge}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                      if (d.locked) ...<Widget>[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.lock_outline,
                          size: 10,
                          color: c.onSurfaceVariantActions,
                        ),
                      ],
                      if (d.note.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 5),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: sub,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    d.title.isEmpty ? '(未命名)' : d.title,
                    maxLines: sz.height >= 80 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: text,
                    ),
                  ),
                  if (d.note.isNotEmpty && sz.height >= 80) ...<Widget>[
                    const SizedBox(height: 1),
                    Text(
                      d.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: sub),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _kindLabel(FlowNodeKind k) => switch (k) {
      FlowNodeKind.start => '开始',
      FlowNodeKind.step => '步骤',
      FlowNodeKind.decision => '判断',
      FlowNodeKind.end => '结束',
      FlowNodeKind.lane => '泳道',
    };
