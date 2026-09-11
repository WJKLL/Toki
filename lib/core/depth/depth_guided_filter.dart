// lib/core/depth/depth_guided_filter.dart
// 编号：U-13 引导滤波（边缘保持的深度优化）
//
// ★ 为什么要它 —— 本轮的根本结论
//   单目深度模型输出的是【平滑】的深度图：训练损失对大误差敏感、对高频边缘
//   不敏感，于是物体边界处深度是"渐变过渡"，而不是"台阶"。
//
//   这正好解释了我们这一路遇到的全部现象：
//     · 身体掉进背景       —— 阈值切在渐变带里；
//     · 背景被收纳         —— 渐变带里深度"看起来连续"，连通性走得通；
//     · 手指忽而被剔忽而被留 —— 同一条渐变带，两种判据给出相反结论；
//     · 换参数总在两者间摇摆 —— 因为【判据本身选错了】。
//
//   而物体边界本来就画在图像上：亮度/颜色在那里有明显跳变。
//   引导滤波以原图为引导，让深度图的边缘【对齐图像的真实边缘】。
//
// ★ 算法（He et al. 快速引导滤波，O(n)）
//   局部线性模型：q_i = a_k · I_i + b_k   （i 落在窗口 k 内）
//     a_k = cov_k(I, p) / (var_k(I) + eps)
//     b_k = mean_k(p) − a_k · mean_k(I)
//   再对 a、b 各做一次均值滤波，得到逐像素结果：
//     q_i = mean(a)_i · I_i + mean(b)_i
//
//   → 引导图有【明显边缘】处 var(I) 大 ⇒ a 小 ⇒ 深度不被平均掉，边缘保住；
//   → 引导图【平坦】处深度被平滑 ⇒ 去掉噪声。
//
// ★ 为什么不用原生 OpenCV
//   本项目要移植鸿蒙，原生实现等于堵死镜像路线。引导滤波是 O(n) 的可分离
//   算法（4 次 box filter），纯 Dart 在深度图分辨率（典型 280×640）上只要
//   几毫秒，完全够用。
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'depth_inference.dart';

abstract final class DepthGuidedFilter {
  /// 以 [photo] 为引导，优化 [depth] 的边缘。
  ///
  /// [radiusRatio] 滤波半径 = 深度图短边 × 该比例（默认 6%）；
  /// [eps] 正则项：越大越平滑、边缘保留越弱。
  static Future<DepthResult> apply({
    required DepthResult depth,
    required ui.Image photo,
    double radiusRatio = 0.06,
    double eps = 4e-3,
  }) async {
    final int w = depth.width;
    final int h = depth.height;
    if (w < 4 || h < 4) return depth;

    final Float32List guide = await _luminance(photo, w, h);
    final int r = math.max(2, (math.min(w, h) * radiusRatio).round());
    final Float32List q = _filter(guide, depth.data, w, h, r, eps);

    return DepthResult(
      width: w,
      height: h,
      data: q,
      minMeters: depth.minMeters,
      maxMeters: depth.maxMeters,
    );
  }

  /// 原图 → 缩放到 (w,h) 的亮度（0..1）。
  ///
  /// 只取亮度：引导滤波需要的是"哪里有边缘"，灰度足够，还能省一半内存。
  static Future<Float32List> _luminance(
    ui.Image photo,
    int w,
    int h,
  ) async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.drawImageRect(
      photo,
      Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      // 必须 high：medium 在"缩小"时会走 mipmap，边缘细节先丢一半 ——
      // 而引导滤波的全部价值就在于那些边缘。
      Paint()..filterQuality = FilterQuality.high,
    );
    final ui.Picture pic = rec.endRecording();
    final ui.Image small = await pic.toImage(w, h);
    pic.dispose();
    final ByteData? bd =
        await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();
    if (bd == null) return Float32List(w * h);

    final Uint8List px =
        bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    final Float32List out = Float32List(w * h);
    for (int i = 0; i < w * h; i++) {
      final int o = i * 4;
      // Rec.601 亮度
      out[i] =
          (0.299 * px[o] + 0.587 * px[o + 1] + 0.114 * px[o + 2]) / 255.0;
    }
    return out;
  }

  /// 快速引导滤波主体。
  static Float32List _filter(
    Float32List i,
    Float32List p,
    int w,
    int h,
    int r,
    double eps,
  ) {
    final int n = w * h;
    final Float32List meanI = _box(i, w, h, r);
    final Float32List meanP = _box(p, w, h, r);

    final Float32List ii = Float32List(n);
    final Float32List ip = Float32List(n);
    for (int k = 0; k < n; k++) {
      ii[k] = i[k] * i[k];
      ip[k] = i[k] * p[k];
    }
    final Float32List corrI = _box(ii, w, h, r);
    final Float32List corrIP = _box(ip, w, h, r);

    final Float32List a = Float32List(n);
    final Float32List b = Float32List(n);
    for (int k = 0; k < n; k++) {
      final double varI = corrI[k] - meanI[k] * meanI[k];
      final double covIP = corrIP[k] - meanI[k] * meanP[k];
      final double ak = covIP / (varI + eps);
      a[k] = ak;
      b[k] = meanP[k] - ak * meanI[k];
    }

    final Float32List meanA = _box(a, w, h, r);
    final Float32List meanB = _box(b, w, h, r);
    final Float32List q = Float32List(n);
    for (int k = 0; k < n; k++) {
      q[k] = (meanA[k] * i[k] + meanB[k]).clamp(0.0, 1.0);
    }
    return q;
  }

  /// 半径为 r 的均值滤波：可分离（先横后纵）+ 滑动窗口，整体 O(n)。
  ///
  /// 边界处窗口自动收窄（用实际计数），避免边缘被拉黑。
  static Float32List _box(Float32List src, int w, int h, int r) {
    final Float32List tmp = Float32List(src.length);
    for (int y = 0; y < h; y++) {
      final int base = y * w;
      double sum = 0;
      int cnt = 0;
      final int firstEnd = math.min(r, w - 1);
      for (int k = 0; k <= firstEnd; k++) {
        sum += src[base + k];
        cnt++;
      }
      for (int x = 0; x < w; x++) {
        tmp[base + x] = sum / cnt;
        final int add = x + r + 1;
        final int rem = x - r;
        if (add < w) {
          sum += src[base + add];
          cnt++;
        }
        if (rem >= 0) {
          sum -= src[base + rem];
          cnt--;
        }
      }
    }

    final Float32List out = Float32List(src.length);
    for (int x = 0; x < w; x++) {
      double sum = 0;
      int cnt = 0;
      final int firstEnd = math.min(r, h - 1);
      for (int k = 0; k <= firstEnd; k++) {
        sum += tmp[k * w + x];
        cnt++;
      }
      for (int y = 0; y < h; y++) {
        out[y * w + x] = sum / cnt;
        final int add = y + r + 1;
        final int rem = y - r;
        if (add < h) {
          sum += tmp[add * w + x];
          cnt++;
        }
        if (rem >= 0) {
          sum -= tmp[rem * w + x];
          cnt--;
        }
      }
    }
    return out;
  }
}
