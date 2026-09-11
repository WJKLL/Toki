// lib/core/wallpaper/depth_template_renderer.dart
// 编号：U-12 深度后处理管线（预设模板 → 深度图）
//
// 设计要点：**像素生成与焦点采样共用同一个 depthAt()** —— 否则"点击某处设为焦点"
// 算出的深度会与屏幕上看到的深度图不一致（点击处不钉住）。
//
// 精度说明：深度图用 8bit RGBA8888。位移量上限约 40px、rel 值域 1.0，
// 每级对应位移 40/256 ≈ 0.16px，远小于 1 像素；叠加纹理双线性采样后
// 无可见台阶，因此不需要 16bit / float 纹理。
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../domain/entities/depth_template.dart';

/// U-12：预设景深模板渲染器。
abstract final class DepthTemplateRenderer {
  /// 归一化半径基准（半对角线）—— 使角落处 r ≈ 1。
  static const double _halfDiagonal = 0.7071067811865476;

  /// 查询归一化坐标 (u, v) ∈ [0,1]² 处的深度值。
  ///
  /// 返回值 0 = 最远，1 = 最近（与 spatial_parallax.frag 约定一致）。
  static double depthAt(DepthTemplate t, double u, double v) {
    final double d = switch (t.kind) {
      DepthTemplateKind.radial => _radial(t, u, v),
      DepthTemplateKind.linear => _linear(t, u, v),
      DepthTemplateKind.bands => _bands(t, v),
    };
    return t.invert ? 1.0 - d : d;
  }

  /// 径向：中心最近，向外平滑衰减。
  static double _radial(DepthTemplate t, double u, double v) {
    final double dx = u - t.center.dx;
    final double dy = v - t.center.dy;
    final double r = math.sqrt(dx * dx + dy * dy) / _halfDiagonal;
    // feather 越大 → 衰减越晚 → 中心"凸起"越平缓。
    final double reach = (t.feather * 1.4).clamp(0.06, 2.0);
    return 1.0 - _smoothstep(0.0, reach, r);
  }

  /// 线性：沿 angle 方向渐变（角度按屏幕坐标，y 向下）。
  static double _linear(DepthTemplate t, double u, double v) {
    final double rad = t.angle * math.pi / 180.0;
    final double proj =
        math.cos(rad) * (u - 0.5) + math.sin(rad) * (v - 0.5);
    final double span = t.feather.clamp(0.2, 1.0);
    return (0.5 + proj / span).clamp(0.0, 1.0);
  }

  /// 上下分带：远景(上) → 中景 → 近景(下)，边界平滑过渡。
  static double _bands(DepthTemplate t, double v) {
    const double far = 0.18;
    const double mid = 0.55;
    const double near = 1.0;
    final double w = 0.02 + 0.06 * t.feather.clamp(0.0, 1.0);
    final double t1 = _smoothstep(1.0 / 3.0 - w, 1.0 / 3.0 + w, v);
    final double t2 = _smoothstep(2.0 / 3.0 - w, 2.0 / 3.0 + w, v);
    return far + (mid - far) * t1 + (near - mid) * t2;
  }

  static double _smoothstep(double e0, double e1, double x) {
    if (e1 <= e0) return x < e0 ? 0.0 : 1.0;
    final double t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// 生成 RGBA8888 像素（r = g = b = 深度，a = 255）。
  static Uint8List renderPixels(DepthTemplate t, int width, int height) {
    final Uint8List out = Uint8List(width * height * 4);
    for (int y = 0; y < height; y++) {
      final double v = (y + 0.5) / height;
      for (int x = 0; x < width; x++) {
        final double u = (x + 0.5) / width;
        final int g = (depthAt(t, u, v) * 255.0).round().clamp(0, 255);
        final int i = (y * width + x) * 4;
        out[i] = g;
        out[i + 1] = g;
        out[i + 2] = g;
        out[i + 3] = 255;
      }
    }
    return out;
  }

  /// 生成供 shader 采样的 [ui.Image]。
  static Future<ui.Image> renderImage(
    DepthTemplate t, {
    int width = 256,
    int height = 256,
  }) {
    final Uint8List pixels = renderPixels(t, width, height);
    final Completer<ui.Image> done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}
