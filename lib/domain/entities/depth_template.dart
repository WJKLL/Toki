// lib/domain/entities/depth_template.dart
// 编号：U-12 深度后处理管线（预设景深模板部分）
//
// 决策 B4（2026-09-11）：AI 失败时的降级产物 = 【2~3 套固定模板 + 可手动修正】。
// 本文件定义模板的纯数据模型；像素生成见 core/wallpaper/depth_template_renderer.dart。
//
// 约定（与 spatial_parallax.frag 一致）：
//   深度值 0 = 最远，1 = 最近。焦点深度在该区间内取值。
//
// 为什么模板要单独成一类：
//   1. 降级链最后一环 —— 设备弱 / 模型加载失败 / 推理异常时的兜底产物；
//   2. 开发期深度来源 —— 在 S-31 深度推理服务落地前，渲染链路可独立验证；
//   3. 手动分层的起点 —— 用户选一个最接近的模板后再手动画几笔修正。
import 'dart:ui' show Offset;

/// 预设模板形态。
enum DepthTemplateKind {
  /// 径向：中心近、边缘远（"凸起"感）—— 适合人像 / 主体居中的图。
  radial,

  /// 线性：沿指定角度渐变 —— 适合风景 / 地面延伸。
  linear,

  /// 上下分带：近景 / 中景 / 远景三段 —— 适合明确分层的前中后景。
  bands,
}

/// 预设景深模板（不可变）。
class DepthTemplate {
  const DepthTemplate({
    required this.kind,
    required this.label,
    this.angle = 135,
    this.center = const Offset(0.5, 0.5),
    this.feather = 0.72,
    this.invert = false,
  });

  /// 形态。
  final DepthTemplateKind kind;

  /// 面向用户的名字。
  final String label;

  /// 渐变方向（度；仅 [DepthTemplateKind.linear] 使用）。
  final double angle;

  /// 径向中心（归一化 0..1；仅 [DepthTemplateKind.radial] 使用）。
  final Offset center;

  /// 过渡柔和度 0.1..1.0：越大越平缓，越小越"同心环"。
  final double feather;

  /// 反转（近 ↔ 远）。
  final bool invert;

  DepthTemplate copyWith({
    DepthTemplateKind? kind,
    String? label,
    double? angle,
    Offset? center,
    double? feather,
    bool? invert,
  }) {
    return DepthTemplate(
      kind: kind ?? this.kind,
      label: label ?? this.label,
      angle: angle ?? this.angle,
      center: center ?? this.center,
      feather: feather ?? this.feather,
      invert: invert ?? this.invert,
    );
  }

  /// 内置模板表（B4 决策的 2~3 套）。
  static const List<DepthTemplate> presets = <DepthTemplate>[
    DepthTemplate(
      kind: DepthTemplateKind.radial,
      label: '中心凸起',
    ),
    DepthTemplate(
      kind: DepthTemplateKind.linear,
      label: '斜向纵深',
    ),
    DepthTemplate(
      kind: DepthTemplateKind.bands,
      label: '前中后景',
    ),
  ];
}
