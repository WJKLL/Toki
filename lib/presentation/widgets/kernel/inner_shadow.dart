// lib/kernel/inner_shadow.dart
// 1:1 复刻参考项目 InnerShadow.kt（BlendMode.Clear 挖孔 + offset=radius 偏移 + blur）。
// 用 evenOdd path 环形替代 BlendMode.Clear（双后端兼容，无 Skia 黑 bug）。
//
// 层级（与参考一致）：参考 InnerShadowNode.draw 先 drawContent()，阴影 layer
// 再画在内容【之上】→ 阴影是玻璃面板表面上的厚度暗影，才有立体感。
// （CustomPaint(painter:) 画在 child 之下，会被半透明玻璃压住，立体感几乎消失。）
// 性能：radius<=0 或 alpha<=0 时直接透传 child，静止/无按压零绘制开销。
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 内阴影：沿 shape 向内柔和阴影，偏移 [offset]（参考项目默认 offset=radius 向下）。
/// 画在 child 之上（前景），clip 限制模糊扩散不出形状。
class InnerShadow extends StatelessWidget {
  const InnerShadow({
    super.key,
    required this.shape,
    required this.radius,
    required this.color,
    required this.alpha,
    this.offset = Offset.zero,
    required this.child,
  });

  final ShapeBorder shape;
  final double radius;
  final Color color;
  final double alpha;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (radius <= 0 || alpha <= 0) return child;
    return CustomPaint(
      foregroundPainter: _InnerShadowPainter(
        shape: shape,
        radius: radius,
        color: color,
        alpha: alpha,
        offset: offset,
      ),
      child: child,
    );
  }
}

class _InnerShadowPainter extends CustomPainter {
  _InnerShadowPainter({
    required this.shape,
    required this.radius,
    required this.color,
    required this.alpha,
    required this.offset,
  });

  final ShapeBorder shape;
  final double radius;
  final Color color;
  final double alpha;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Path outer = shape.getOuterPath(rect);
    // 内阴影 = 外形状 − 偏移后的外形状（offset 方向留白，反方向阴影）。
    final Path shifted = shape.getOuterPath(rect.shift(offset));
    final Path ring = Path.combine(PathOperation.difference, outer, shifted);

    final Paint blur = Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: radius,
        sigmaY: radius,
        tileMode: TileMode.decal,
      );
    // clip 在 saveLayer 之外：blur 扩散被限制在形状内（参考项目
    //   drawLayer 前 canvas.clipPath(clipPath) 同语义），内阴影不外溢。
    canvas.save();
    canvas.clipPath(outer);
    canvas.saveLayer(rect, blur);
    // alpha = color 自带透明度 × 传入 alpha（参考项目 layer.alpha 乘性），
    // 而非用 withValues 覆盖成 press（会导致按压时接近不透明黑）。
    canvas.drawPath(
      ring,
      Paint()..color = color.withValues(alpha: color.a * alpha),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) =>
      old.radius != radius ||
      old.color != color ||
      old.alpha != alpha ||
      old.offset != offset;
}
