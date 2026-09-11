// lib/core/depth/depth_post_process.dart
// 编号：U-12 深度后处理管线
//
// 目前只实现「保边平滑」一步；规格书 §3.5 的完整链路是
//   归一化 → 双边滤波 → 引导滤波 → 边缘强化
// 后续按需补齐（边缘强化 / 质量评分见 S-34）。
//
// ★ 为什么需要保边平滑
//   位移量 = (深度 − 焦点) × 强度，而真实深度图上**物体内部深度并不均匀**
//   （人物鼻尖比耳朵近）。后果有两个：
//     1) 主体自己会扭动 —— "主体不动"的观感出不来；
//     2) 想让焦点带覆盖整个主体就得把带宽开很大，反而把背景也圈进来，
//        并在画面里切出可见的等深线边界（实测反馈："切割出来一片区域"、
//        "参数拉大会有好几条分割线"）。
//   把物体内部抹平、同时保住物体边界的跳变之后，**小带宽就能整片钉住主体**。
//
// ★ 与「深度分层」的本质区别（这一点很关键）
//   分层：按【深度值】全局切 → 等深线是不规则曲线，会在人物身上切出**假边界**；
//   保边平滑：按【邻域深度差】加权 → 边界处权重趋 0，**只在同一物体内部**平滑。
//
// ★ 实现取舍
//   用线性衰减权重而非 exp(高斯)：409,600 像素 × 9 邻域 × 最多 6 轮迭代下，
//   exp 的开销不可接受（Dart 侧实测会到秒级）；线性衰减视觉等价且无需查表。
import 'dart:typed_data';

import 'depth_inference.dart';

abstract final class DepthPostProcess {
  /// 保边平滑。
  ///
  /// [strength] 0..1：≤0.01 时原样返回；越大迭代轮数越多、sigma 越宽。
  static DepthResult smooth(DepthResult src, double strength) {
    if (strength <= 0.01) return src;
    final int iterations = (1 + (strength * 5).round()).clamp(1, 6);
    // sigma = "多深的差算作不同物体"。太小几乎不生效；太大会把背景一起抹平，
    // 反而让主体与背景连成一片。
    final double sigma = 0.03 + 0.12 * strength;
    final Float32List out = _edgeAware(
      src.data,
      src.width,
      src.height,
      iterations: iterations,
      sigma: sigma,
    );
    return DepthResult(
      width: src.width,
      height: src.height,
      data: out,
      minMeters: src.minMeters,
      maxMeters: src.maxMeters,
    );
  }

  /// 邻域加权平均：权重随深度差线性衰减，深度差 ≥ sigma 视为不同物体（权重 0）。
  static Float32List _edgeAware(
    Float32List src,
    int w,
    int h, {
    required int iterations,
    required double sigma,
  }) {
    Float32List cur = src;
    final double invSigma = 1.0 / sigma;
    for (int it = 0; it < iterations; it++) {
      final Float32List next = Float32List(cur.length);
      for (int y = 0; y < h; y++) {
        final int rowBase = y * w;
        for (int x = 0; x < w; x++) {
          final int i = rowBase + x;
          final double c = cur[i];
          double sum = c;
          double wsum = 1.0;
          for (int dy = -1; dy <= 1; dy++) {
            final int yy = y + dy;
            if (yy < 0 || yy >= h) continue;
            final int base = yy * w;
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final int xx = x + dx;
              if (xx < 0 || xx >= w) continue;
              final double v = cur[base + xx];
              final double a = (v - c).abs() * invSigma;
              if (a >= 1.0) continue;
              final double wt = 1.0 - a;
              sum += v * wt;
              wsum += wt;
            }
          }
          next[i] = sum / wsum;
        }
      }
      cur = next;
    }
    return cur;
  }
}
