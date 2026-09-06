// lib/presentation/features/flow/vyuh_flow_theme.dart
// 编号:P-11 v2 域 —— vyuh 画布主题的 Miuix token 注入(实时取色)
// 说明:节点/连线/网格/选区/端口配色取自当前 MiuixTheme.colors,深浅与
//   Monet 换色即时跟随;画布形状语言保持 vyuh 默认(见 PLAN §2)。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../domain/entities/flow_doc.dart';

/// 节点语义色(Miuix token;start 主色 / decision 次级 / end 错误)。
Color kindAccent(MiuixColors c, FlowNodeKind kind) => switch (kind) {
      FlowNodeKind.start => c.primary,
      FlowNodeKind.decision => c.secondary,
      FlowNodeKind.end => c.error,
      FlowNodeKind.step => c.onSurfaceVariantSummary,
      FlowNodeKind.lane => c.primary, // 泳道:与开始同主色族(虚线框语义)。
    };

/// 泳道虚线框描边色(深浅可读)。
Color laneStroke(MiuixColors c) =>
    c.primary.withValues(alpha: c.surface.computeLuminance() < 0.5 ? 0.55 : 0.4);

/// 泳道底色(极淡主色填充)。
Color laneFill(MiuixColors c) =>
    c.primary.withValues(alpha: c.surface.computeLuminance() < 0.5 ? 0.09 : 0.05);

/// 缩略图主题(Miuix token 实时取色;阶段2)。
MinimapTheme vyuhMinimapTheme(BuildContext context) {
  final MiuixColors c = MiuixTheme.of(context).colors;
  final bool dark = c.surface.computeLuminance() < 0.5;
  return MinimapTheme(
    backgroundColor: dark
        ? c.surfaceContainerHigh.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.92),
    nodeColor: c.primary,
    viewportColor: c.primary,
    viewportFillOpacity: 0.12,
    viewportBorderOpacity: 0.55,
    borderColor: c.dividerLine,
    borderWidth: 1,
    borderRadius: 12,
    padding: const EdgeInsets.all(5),
  );
}

/// 构建注入 Miuix token 的 vyuh 主题(每次调用按当前主题实时取色)。
NodeFlowTheme vyuhFlowTheme(BuildContext context) {
  final MiuixColors c = MiuixTheme.of(context).colors;
  final bool dark = c.surface.computeLuminance() < 0.5;
  final NodeFlowTheme base = dark ? NodeFlowTheme.dark : NodeFlowTheme.light;

  final Color canvas = dark
      ? c.surface.withValues(alpha: 0.6)
      : c.surfaceVariant.withValues(alpha: 0.4);
  final Color line = c.outline.withValues(alpha: dark ? 0.5 : 0.45);
  final Color grid = dark
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.black.withValues(alpha: 0.05);

  return base.copyWith(
    backgroundColor: canvas,
    nodeTheme: base.nodeTheme.copyWith(
      backgroundColor: c.surfaceContainerHigh,
      selectedBackgroundColor: c.surfaceContainerHighest,
      borderColor: c.dividerLine,
      selectedBorderColor: c.primary,
      selectedBorderWidth: 2,
      borderRadius: BorderRadius.circular(14),
    ),
    // 阶段2:拉伸把手触摸友好(Miuix 配色;命中区 = handleSize + 2×snap)。
    resizerTheme: base.resizerTheme.copyWith(
      handleSize: 11,
      snapDistance: 8,
      color: c.surfaceContainerHighest,
      borderColor: c.primary,
      borderWidth: 1.6,
    ),
    connectionTheme: base.connectionTheme.copyWith(
      color: line,
      selectedColor: c.primary,
      highlightColor: c.primary,
      strokeWidth: 2,
      selectedStrokeWidth: 3,
      // 3c-2:默认端点 = 单箭头(终点三角);none/both 由数据显式覆盖。
      endPoint: const ConnectionEndPoint(
        shape: MarkerShapes.triangle,
        size: Size(12, 12),
      ),
    ),
    temporaryConnectionTheme: base.temporaryConnectionTheme.copyWith(
      color: c.primary,
      strokeWidth: 2.5,
    ),
    gridTheme: base.gridTheme.copyWith(color: grid),
    selectionTheme: base.selectionTheme.copyWith(
      color: c.primary.withValues(alpha: dark ? 0.16 : 0.12),
      borderColor: c.primary,
    ),
    portTheme: base.portTheme.copyWith(
      color: line,
      connectedColor: c.primary,
      highlightColor: c.primary,
      borderColor: c.surface,
    ),
  );
}
