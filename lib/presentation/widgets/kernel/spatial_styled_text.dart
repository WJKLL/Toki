// lib/presentation/widgets/kernel/spatial_styled_text.dart
// 编号：C-68 样式化文字渲染器
//
// 把 SpatialStyle（S-42）渲染成真正的像素。所有"文字类"组件
// （艺术字 / 时钟 / 日期 / 心情标签）都走这一个渲染器 ——
// 这样样式层加一个维度，所有组件自动获得，不必逐个改。
//
// ★ 三层叠加的顺序不能反（从下到上）：
//     发光 → 描边 → 填充
//   描边必须在填充**之下**，否则描边会盖住字芯、字变细；
//   发光必须在最底下，否则会糊在字面上。
//
// ★ 描边宽度要 ×2：Flutter 的 stroke 是沿字形轮廓**内外各画一半**，
//   想要"看起来粗 5px"就得传 10。这是踩过一次才知道的。
//
// ★ 渐变文字没有直接支持，用 ShaderMask + BlendMode.srcIn 把渐变
//   "印"进文字里（srcIn 只保留文字本身作为遮罩的形状）。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../domain/entities/spatial_style.dart';

/// 用 [SpatialStyle] 渲染一段文字。
class SpatialStyledText extends StatelessWidget {
  const SpatialStyledText({
    super.key,
    required this.text,
    required this.style,
    this.scale = 1,
    this.textAlign = TextAlign.center,
    this.vertical = false,
    this.wrapWidth = 0,
  });

  final String text;
  final SpatialStyle style;

  /// 组件在画面上的缩放，作用到字号/描边/发光/内边距上，
  /// 否则"放大组件"会把样式细节拉变形。
  final double scale;

  final TextAlign textAlign;

  /// **竖排**（一个字一行）—— 中文 / 日文题字常用。
  ///
  /// ★ 为什么不做成"旋转 90°"：那样标点与英文会被一起转过去，看着是错的。
  ///   竖排的正确做法是逐字换行，标点保持正立。
  final bool vertical;

  /// 自动换行宽度（逻辑像素）；0 = 不限制。
  final double wrapWidth;

  @override
  Widget build(BuildContext context) {
    // ★ 竖排 = 逐字换行。用换行符而不是把整块旋转 ——
    //   旋转会把标点与英文一起转过去，看着是错的（见字段说明）。
    final String shown = vertical ? text.split('').join('\n') : text;
    final Widget out = _render(context, shown);
    if (wrapWidth <= 0) return out;
    // 自动换行宽度：由调用方按画布宽度给（组件层知道画布多宽，这里不知道）。
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wrapWidth),
      child: out,
    );
  }

  Widget _render(BuildContext context, String text) {
    final bool need = style.strokeWidth > 0 || style.glowRadius > 0 ||
        style.isGradient || style.hasPlate || style.shadowBlur > 0;

    // 没有任何"花活"时走最省的一条：单个 Text。
    if (!need) {
      return Opacity(
        opacity: style.opacity.clamp(0.0, 1.0),
        child: Text(
          text,
          textAlign: textAlign,
          style: _base(scale: scale, withShadow: false),
        ),
      );
    }

    final List<Widget> layers = <Widget>[];

    // ① 发光：用描边画一圈再模糊，比 Shadow 更像"外发光"（Shadow 只在一边）
    if (style.glowRadius > 0) {
      layers.add(
        Text(
          text,
          textAlign: textAlign,
          style: _base(scale: scale, withShadow: false).copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = style.glowColor
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                style.glowRadius * scale,
              ),
          ),
        ),
      );
    }

    // ② 描边
    if (style.strokeWidth > 0) {
      layers.add(
        Text(
          text,
          textAlign: textAlign,
          style: _base(scale: scale, withShadow: false).copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.strokeWidth * 2 * scale
              ..strokeJoin = StrokeJoin.round
              ..color = style.strokeColor,
          ),
        ),
      );
    }

    // ③ 填充（阴影挂在它上面，避免和描边/发光各画一次）
    final Widget fill = Text(
      text,
      textAlign: textAlign,
      style: _base(scale: scale, withShadow: true),
    );
    layers.add(
      style.isGradient
          ? ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (Rect r) => LinearGradient(
                begin: _align(style.gradientAngle, from: true),
                end: _align(style.gradientAngle, from: false),
                colors: <Color>[style.color, style.gradientEnd!],
              ).createShader(r),
              child: fill,
            )
          : fill,
    );

    Widget content = Stack(
      alignment: Alignment.center,
      children: layers,
    );

    // ④ 胶囊底（玻璃 / 手账这类"贴纸"观感靠它）
    if (style.hasPlate) {
      content = Container(
        padding: EdgeInsets.symmetric(
          horizontal: style.platePadding * scale,
          vertical: style.platePadding * 0.62 * scale,
        ),
        decoration: BoxDecoration(
          color: style.plateColor,
          borderRadius: BorderRadius.circular(style.plateRadius * scale),
        ),
        child: content,
      );
    }

    return Opacity(
      opacity: style.opacity.clamp(0.0, 1.0),
      child: content,
    );
  }

  TextStyle _base({required double scale, required bool withShadow}) {
    // FontWeight.w100..w900 就是 values[0..8]
    final int wi = ((style.fontWeight / 100).round() - 1).clamp(0, 8);
    return TextStyle(
      fontFamily: style.fontFamily,
      fontSize: style.fontSize * scale,
      fontWeight: FontWeight.values[wi],
      letterSpacing: style.letterSpacing * scale,
      height: style.lineHeight,
      color: style.color,
      shadows: withShadow && style.shadowBlur > 0
          ? <Shadow>[
              Shadow(
                color: style.shadowColor,
                blurRadius: style.shadowBlur * scale,
                offset: Offset(0, style.shadowDy * scale),
              ),
            ]
          : const <Shadow>[],
    );
  }

  /// 角度 → 渐变端点。0° = 左→右，90° = 上→下。
  static Alignment _align(double deg, {required bool from}) {
    final double r = deg * math.pi / 180.0;
    final double c = math.cos(r);
    final double s = math.sin(r);
    return from ? Alignment(-c, -s) : Alignment(c, s);
  }
}
