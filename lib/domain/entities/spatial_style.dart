// lib/domain/entities/spatial_style.dart
// 编号：S-42 空间组件【样式层】
//
// ★★ 为什么要有这一层（PLAN_components_v2.0.md §3.2）
//   之前只有 SpatialComponent.clock 一个数字钟，样式**硬编码**在里面。
//   那不是"少做了几个组件"，而是**没有样式层** —— 再加十个组件也只是
//   十份硬编码。所以先把"长什么样"抽出来，让所有组件共用：
//
//     Component（是什么：时间/文字/图象/表情/环境）
//       └─ style: SpatialStyle（长什么样）
//
//   样式层一旦立起来：艺术字、时钟、Logo、表情、天气**全都受益**；
//   反之每加一个组件硬编码一次，就还是会回到"太 low"。
//
// ★ 可调维度（用户要求"自定义程度要高"）
//   字体 / 字重 / 字号 / 字距 / 行高
//   纯色 或 渐变（两色 + 角度）
//   描边（宽度 + 颜色）
//   发光（半径 + 颜色）
//   阴影（模糊 + 偏移 + 颜色）
//   胶囊底（底色 + 圆角 + 内边距）—— 用于玻璃 / 手账那类"贴纸"观感
//   整体不透明度
//
// ★ 不可变 + copyWith：预设就是几个常量，用户改了就从预设 copyWith 出一份，
//   既不会互相污染，也不必写一堆 setter。
import 'dart:ui' show Color;

/// 组件样式（所有组件共用）。
class SpatialStyle {
  const SpatialStyle({
    this.fontFamily,
    this.fontWeight = 600,
    this.fontSize = 34,
    this.letterSpacing = 0,
    this.lineHeight = 1.15,
    this.color = const Color(0xFFFFFFFF),
    this.gradientEnd,
    this.gradientAngle = 90,
    this.strokeWidth = 0,
    this.strokeColor = const Color(0xFF000000),
    this.glowRadius = 0,
    this.glowColor = const Color(0xFFFFFFFF),
    this.shadowBlur = 0,
    this.shadowDy = 0,
    this.shadowColor = const Color(0x99000000),
    this.plateColor,
    this.plateRadius = 18,
    this.platePadding = 0,
    this.opacity = 1,
  });

  /// 字体族；null = 跟随系统默认。字体的运行时加载（.ttf/.otf 导入）另开一期，
  /// 这一层先把"选哪个字体名"的位置留出来。
  final String? fontFamily;

  /// 100~900。
  final double fontWeight;
  final double fontSize;
  final double letterSpacing;

  /// 行高倍数。
  final double lineHeight;

  /// 起始色（纯色时就是它）。
  final Color color;

  /// 结束色；**非 null 即启用渐变**（从 [color] 到 [gradientEnd]）。
  final Color? gradientEnd;

  /// 渐变角度（度，0 = 从左到右，90 = 从上到下）。
  final double gradientAngle;

  /// 描边宽度（0 = 不描边）。
  final double strokeWidth;
  final Color strokeColor;

  /// 外发光半径（0 = 不发光）。
  final double glowRadius;
  final Color glowColor;

  /// 投影模糊与纵向偏移（0 = 不投影）。
  final double shadowBlur;
  final double shadowDy;
  final Color shadowColor;

  /// 胶囊底色；**非 null 才画底**（玻璃/手账那类贴纸观感靠它）。
  final Color? plateColor;

  /// 胶囊圆角与内边距。
  final double plateRadius;
  final double platePadding;

  /// 整体不透明度。
  final double opacity;

  /// 是否是渐变。
  bool get isGradient => gradientEnd != null;

  /// 是否画胶囊底。
  bool get hasPlate => plateColor != null && platePadding > 0;

  SpatialStyle copyWith({
    String? fontFamily,
    double? fontWeight,
    double? fontSize,
    double? letterSpacing,
    double? lineHeight,
    Color? color,
    Color? gradientEnd,
    bool clearGradient = false,
    double? gradientAngle,
    double? strokeWidth,
    Color? strokeColor,
    double? glowRadius,
    Color? glowColor,
    double? shadowBlur,
    double? shadowDy,
    Color? shadowColor,
    Color? plateColor,
    bool clearPlate = false,
    double? plateRadius,
    double? platePadding,
    double? opacity,
  }) {
    return SpatialStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontSize: fontSize ?? this.fontSize,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      color: color ?? this.color,
      gradientEnd: clearGradient ? null : (gradientEnd ?? this.gradientEnd),
      gradientAngle: gradientAngle ?? this.gradientAngle,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeColor: strokeColor ?? this.strokeColor,
      glowRadius: glowRadius ?? this.glowRadius,
      glowColor: glowColor ?? this.glowColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowDy: shadowDy ?? this.shadowDy,
      shadowColor: shadowColor ?? this.shadowColor,
      plateColor: clearPlate ? null : (plateColor ?? this.plateColor),
      plateRadius: plateRadius ?? this.plateRadius,
      platePadding: platePadding ?? this.platePadding,
      opacity: opacity ?? this.opacity,
    );
  }
}

/// 样式预设。
///
/// ★ 为什么预设比"开放全部参数"更重要
///   参数全开时 90% 的用户调不出好看的东西（把描边和发光一起开就会糊）。
///   预设是**已经调好的审美起点**，用户从它出发微调，而不是从零开始。
abstract final class SpatialStylePresets {
  /// 极简：白字 + 轻微投影。最安全，配任何图都不违和。
  static const SpatialStyle minimal = SpatialStyle(
    fontWeight: 600,
    fontSize: 34,
    color: Color(0xFFFFFFFF),
    shadowBlur: 12,
    shadowDy: 2,
    shadowColor: Color(0x66000000),
  );

  /// 玻璃：半透明胶囊底 + 白字 —— 鸿蒙/iOS 那个味。
  static const SpatialStyle glass = SpatialStyle(
    fontWeight: 600,
    fontSize: 28,
    color: Color(0xFFFFFFFF),
    plateColor: Color(0x33FFFFFF),
    plateRadius: 20,
    platePadding: 14,
    shadowBlur: 18,
    shadowDy: 3,
    shadowColor: Color(0x55000000),
  );

  /// 霓虹：青→紫渐变 + 外发光。
  static const SpatialStyle neon = SpatialStyle(
    fontWeight: 800,
    fontSize: 36,
    color: Color(0xFF4DE1FF),
    gradientEnd: Color(0xFFB36BFF),
    gradientAngle: 120,
    glowRadius: 18,
    glowColor: Color(0xFF7FE7FF),
    letterSpacing: 1.5,
  );

  /// 手账：奶油底 + 深棕字，像贴纸。
  static const SpatialStyle journal = SpatialStyle(
    fontWeight: 700,
    fontSize: 26,
    color: Color(0xFF4A3B2A),
    plateColor: Color(0xFFFDF3DC),
    plateRadius: 14,
    platePadding: 12,
    strokeWidth: 0,
    shadowBlur: 10,
    shadowDy: 3,
    shadowColor: Color(0x44000000),
  );

  /// 描边字：粗描边 + 亮填充，压在花哨背景上也读得清。
  static const SpatialStyle outlined = SpatialStyle(
    fontWeight: 900,
    fontSize: 38,
    color: Color(0xFFFFFFFF),
    strokeWidth: 5,
    strokeColor: Color(0xFF1A1A1A),
    letterSpacing: 0.5,
  );

  /// 预设清单：(名字, 样式)。UI 直接遍历它出按钮。
  static const List<(String, SpatialStyle)> all = <(String, SpatialStyle)>[
    ('极简', minimal),
    ('玻璃', glass),
    ('霓虹', neon),
    ('手账', journal),
    ('描边字', outlined),
  ];
}
