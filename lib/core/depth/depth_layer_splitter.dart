// lib/core/depth/depth_layer_splitter.dart
// 编号：U-12 深度后处理管线（分层）
//
// ★ 为什么改成"分层 + 图层平移"
//   逐像素位移（原方案）有一个无解缺陷：**遮挡空洞（disocclusion）**。
//   主体移开后，原本被它遮住的背景区域在原图里**根本不存在**，任何逐像素采样
//   都会拉到错误内容 —— 表现就是主体边缘一圈"拖影"，且位移越大越严重。
//
//   成熟做法（iOS 空间场景 / LeiaPix 等）都是**分层**：把画面切成少数几层，
//   每层作为【完整图像】整体平移。
//     · 层内位移完全一致 → 零形变
//     · 层是整图（RGB 不裁剪、只裁 alpha）→ 平移后任何位置都有内容
//     · 近层移开后露出的是【下层的内容】→ 天然补全，没有空洞
//
// ★ 两个关键实现选择
//   1) 层图的 RGB 用【整张原图】，只有 alpha 按层裁剪。
//      这样层图任意位置都有颜色，平移后不会出现透明洞（否则就得做 inpainting）。
//   2) 层图四周加 margin（默认 56px = 最大位移 + 余量），margin 用【边缘复制】填充。
//      渲染时从 margin 里"取窗"，于是平移不会把画布边缘拉空。
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'depth_inference.dart';

/// 一个视差图层。
class DepthLayer {
  const DepthLayer({required this.image, required this.centerDepth});

  /// 层图：尺寸 = 工作尺寸 + 2×margin，四周为边缘复制的余量。
  final ui.Image image;

  /// 该层中心深度（0 = 最远，1 = 最近），用于计算位移量。
  final double centerDepth;
}

/// 分层结果：含渲染所需的几何信息。
class DepthLayerSet {
  const DepthLayerSet({
    required this.layers,
    required this.workWidth,
    required this.workHeight,
    required this.margin,
  });

  /// 已按 centerDepth 升序（**远 → 近**，渲染顺序即此）。
  final List<DepthLayer> layers;

  /// 工作尺寸（不含 margin）。
  final int workWidth;
  final int workHeight;

  /// 层图四周的余量。
  final int margin;

  void dispose() {
    for (final DepthLayer l in layers) {
      l.image.dispose();
    }
  }
}

abstract final class DepthLayerSplitter {
  /// 把【原图 + 深度图】切成 [layerCount] 个图层。
  static Future<DepthLayerSet?> split({
    required ui.Image photo,
    required DepthResult depth,
    int layerCount = 2,
    // ⚠️ 羽化宽度必须【近乎为零】，这是本方案最容易踩的坑：
    //    层边界处只要有像素被两层 alpha 同时覆盖，它就会被两层内容半透明叠加，
    //    而两层位移不同 → 双影 + 对比度下降。用户实测表现："AI 计算后渲染的
    //    背景大范围不明白光（发白/发雾），一般位于深度图黑色部分" —— 也就是
    //    背景在归一化深度上跨越层边界的那一段。
    //    离线实测重叠区像素占比（3 层）：
    //      feather 0.08 → 最高 23.5% / 0.03 → 8.2% / 0.015 → 3.8%
    //    3.8% 在一张 1440×2626 的图上仍是肉眼可见的一大片，故再压到 0.004
    //    （≈ 硬边界，仅留 1~2 像素过渡以抑制锯齿）。
    double feather = 0.004,
    // 1440：多数手机照片缩到 1440 后损失已经很小；再大则分层耗时明显上升
    // （每层都要遍历全部像素）。
    int maxSide = 1440,
    // ★ 暂不使用 margin：加 margin 需要走 Picture.toImage + 边缘复制，
    //   而"位移=0 时离线合成正常、App 却发白"的差异只可能来自这条路径。
    //   现在层图尺寸 = 工作尺寸。
    //   ⚠️ 由此带来的"位移时画面边缘会露空"已在渲染侧解决：layer_compose.frag
    //   用 uZoom 把采样范围收窄到 [c, 1-c]，等效于给每层补回了 margin（详见该
    //   文件顶部说明）。所以这里可以继续保持 margin = 0，不必再走 Picture 路径。
    int margin = 0,
  }) async {
    if (layerCount < 2) layerCount = 2;

    // 工作尺寸：等比缩放到最长边 maxSide（分层要遍历全部像素，太大很慢）
    final double s =
        math.min(1.0, maxSide / math.max(photo.width, photo.height));
    final int w = math.max(8, (photo.width * s).round());
    final int h = math.max(8, (photo.height * s).round());

    final Uint8List src = await _rgbaOf(photo, w, h);
    // ★ 大幅模糊版：用来填充"不属于本层"的区域。
    //   层图的 RGB 若直接用整张原图，最远层里就【含着主体】—— 主体层移开后
    //   会露出"原位置的另一个主体"（实测："底图的人物会露出"）。
    //   把非本层区域换成原图的模糊版，移开后露出的就是柔和的背景色调。
    final Uint8List soft =
        await _blurredRgba(photo, w, h, math.max(10.0, w * 0.035));
    final Float32List dw = _resampleDepth(depth, w, h);

    // ★ 2 层时的切点用 Otsu 自动求，而不是固定 0.5 等分。
    //   等分的边界会【横穿背景】（实测："背景被分割"、树干断裂）——
    //   因为背景的深度往往跨越中点。Otsu 找的是"类间方差最大"的阈值，
    //   落点在深度分布的两个峰之间，通常正是主体与背景的分界处。
    final double split = layerCount == 2
        ? _otsuSplit(dw, 64).clamp(0.12, 0.88)
        : 0.5;

    // ── 层下界（alpha 与"归属"都用它）──────────────────────────
    final List<double> los = <double>[];
    for (int i = 0; i < layerCount; i++) {
      los.add(layerCount == 2 ? (i == 0 ? 0.0 : split) : i / layerCount);
    }

    // ★ alpha 必须【累积】，不能互补 —— 这是"移动错位时露出底部白色"的根因。
    //
    //   互补设计（各层 alpha 之和 = 1）：静止时合成结果正确，但**平移会破坏
    //   互补关系** —— 边界处两层各自移开，位置 P 上两层的 alpha 都可能变成 0，
    //   于是没有任何层覆盖它，直接露出页面底色（浅色）→ 白缝。
    //
    //   累积设计（画家算法）：最远层 alpha 恒为 1，整幅铺满作底；更近的层只
    //   负责"向上叠加"，覆盖从自己下界直到最近的全部区域。这样任何层移开后
    //   留下的空隙，都仍有更远层在铺底，永远不露白。
    double alphaAt(int i, double d) =>
        i == 0 ? 1.0 : _smoothstep(los[i] - feather, los[i] + feather, d);

    // ★ 但 RGB 不能跟着 alpha 走，必须按【归属 own】混合 —— 这是"露出底图主体"的根因。
    //
    //   alpha 回答"覆盖到什么程度"（累积），own 回答"这块像素是不是这层自己的"。
    //   两者的差别恰好落在最远层：它 alpha 恒为 1（必须铺底），若 RGB 直接用整张
    //   原图，那层里就【含着清晰的主体】—— 主体层不动、背景层移开时，主体轮廓
    //   外侧会露出"另一个清晰的主体"（实测："会露出底图主体"）。
    //
    //   归属 = 本层 alpha − 下一层 alpha（最后一层就是它自己的 alpha）：
    //     背景区：a0=1、a1=0 → 层0 own=1（原图）、层1 own=0（模糊版）
    //     主体区：a0=1、a1=1 → 层0 own=0（模糊版）、层1 own=1（原图）
    //   于是层 0 在主体位置存的是【模糊版】，移开后只会露出柔和色块。
    //
    //   深度分箱查找表：避免每像素重复算 smoothstep（顺带比原实现更快）。
    const int bins = 1024;
    final List<Float32List> lut = <Float32List>[];
    for (int i = 0; i < layerCount; i++) {
      final Float32List t = Float32List(bins);
      for (int b = 0; b < bins; b++) {
        t[b] = alphaAt(i, b / (bins - 1));
      }
      lut.add(t);
    }

    final List<DepthLayer> layers = <DepthLayer>[];
    for (int i = 0; i < layerCount; i++) {
      final double lo = los[i];
      final double hi = layerCount == 2
          ? (i == 0 ? split : 1.0)
          : (i + 1) / layerCount;

      final Float32List aOf = lut[i];
      final Float32List? aNext = i + 1 < layerCount ? lut[i + 1] : null;

      final Uint8List rgba = Uint8List(w * h * 4);
      bool any = false;
      for (int p = 0; p < w * h; p++) {
        final int bi = (dw[p] * (bins - 1)).round().clamp(0, bins - 1);
        final double a = aOf[bi];
        if (a <= 0.0) continue; // 本层不覆盖这里 → 留全透明，合成时无影响
        // 归属：本层覆盖、且不被任何更近的层覆盖的那部分。
        final double own = aNext == null
            ? a
            : (a - aNext[bi]).clamp(0.0, 1.0);
        final int o = p * 4;
        // 本层区域用原图，其余用模糊版：避免平移后露出错位的其它层内容。
        rgba[o] = (src[o] * own + soft[o] * (1.0 - own)).round().clamp(0, 255);
        rgba[o + 1] = (src[o + 1] * own + soft[o + 1] * (1.0 - own))
            .round()
            .clamp(0, 255);
        rgba[o + 2] = (src[o + 2] * own + soft[o + 2] * (1.0 - own))
            .round()
            .clamp(0, 255);
        rgba[o + 3] = (a * 255.0).round().clamp(0, 255);
        any = true;
      }
      if (!any) continue; // 该层没有像素（深度分布集中时的空层）

      final ui.Image flat = await _decode(rgba, w, h);
      final ui.Image padded = margin > 0 ? await _addMargin(flat, margin) : flat;
      if (margin > 0) flat.dispose();
      layers.add(
        DepthLayer(image: padded, centerDepth: (lo + hi) / 2.0),
      );
    }

    if (layers.isEmpty) return null;
    layers.sort((DepthLayer a, DepthLayer b) =>
        a.centerDepth.compareTo(b.centerDepth));
    return DepthLayerSet(
      layers: layers,
      workWidth: w,
      workHeight: h,
      margin: margin,
    );
  }

  static double _smoothstep(double e0, double e1, double x) {
    if (e1 <= e0) return x < e0 ? 0.0 : 1.0;
    final double t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Otsu 阈值：在深度直方图上找"类间方差最大"的切点。
  ///
  /// 比固定 0.5 等分好：等分的边界会横穿背景（实测"背景被分割"、树干断裂），
  /// 而 Otsu 的落点在深度分布的两个峰之间 —— 通常正是主体与背景的分界。
  static double _otsuSplit(Float32List depth, int bins) {
    final Float64List hist = Float64List(bins);
    for (int i = 0; i < depth.length; i++) {
      final int b = (depth[i] * (bins - 1)).round().clamp(0, bins - 1);
      hist[b] += 1.0;
    }
    final double total = depth.length.toDouble();
    double sumAll = 0;
    for (int i = 0; i < bins; i++) {
      sumAll += i * hist[i];
    }
    double sumB = 0;
    double wB = 0;
    double best = -1;
    int bestT = bins ~/ 2;
    for (int t = 0; t < bins; t++) {
      wB += hist[t];
      if (wB <= 0) continue;
      final double wF = total - wB;
      if (wF <= 0) break;
      sumB += t * hist[t];
      final double mB = sumB / wB;
      final double mF = (sumAll - sumB) / wF;
      final double between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        bestT = t;
      }
    }
    return bestT / (bins - 1);
  }

  /// 原图 → 工作尺寸的 RGBA 字节。
  static Future<Uint8List> _rgbaOf(ui.Image img, int w, int h) async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      // ★ 必须用 high（双三次），**不能**用 medium：
      //   Skia 下 FilterQuality.medium 对【缩小】会走 mipmap 采样 —— 先把图降到
      //   1/2 分辨率再插值，细节直接丢失，整片糊掉/发白。这里是从原图缩到工作
      //   尺寸（典型 0.7 倍），正是 mipmap 最容易触发的区间。
      //   这解释了为什么"几何模板清晰、AI 分层发糊"：
      //     · 几何模板：原图 ui.Image 原样进 shader 采样，**全程没有一次缩放**
      //     · AI 分层：原图先缩到工作尺寸（mipmap → 糊）→ 再缩放到显示尺寸
      Paint()..filterQuality = FilterQuality.high,
    );
    final ui.Picture pic = rec.endRecording();
    final ui.Image scaled = await pic.toImage(w, h);
    pic.dispose();
    final ByteData? bd =
        await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
    scaled.dispose();
    return bd!.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  }

  /// 深度图（可能不是同尺寸）→ 工作尺寸的双线性重采样。
  static Float32List _resampleDepth(DepthResult d, int w, int h) {
    final Float32List out = Float32List(w * h);
    for (int y = 0; y < h; y++) {
      final double sy = (y + 0.5) / h * d.height - 0.5;
      final int y0 = sy.floor().clamp(0, d.height - 1);
      final int y1 = math.min(y0 + 1, d.height - 1);
      final double fy = (sy - y0).clamp(0.0, 1.0);
      for (int x = 0; x < w; x++) {
        final double sx = (x + 0.5) / w * d.width - 0.5;
        final int x0 = sx.floor().clamp(0, d.width - 1);
        final int x1 = math.min(x0 + 1, d.width - 1);
        final double fx = (sx - x0).clamp(0.0, 1.0);
        final double v00 = d.data[y0 * d.width + x0];
        final double v01 = d.data[y0 * d.width + x1];
        final double v10 = d.data[y1 * d.width + x0];
        final double v11 = d.data[y1 * d.width + x1];
        final double top = v00 + (v01 - v00) * fx;
        final double bot = v10 + (v11 - v10) * fx;
        out[y * w + x] = top + (bot - top) * fy;
      }
    }
    return out;
  }

  static Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
    final Completer<ui.Image> done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  /// 原图的大幅模糊版（用于填充层的非本层区域）。
  static Future<Uint8List> _blurredRgba(
    ui.Image img,
    int w,
    int h,
    double sigma,
  ) async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.saveLayer(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    c.restore();
    final ui.Picture pic = rec.endRecording();
    final ui.Image out = await pic.toImage(w, h);
    pic.dispose();
    final ByteData? bd =
        await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    out.dispose();
    return bd!.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  }

  // ignore: unused_element —— margin 当前默认 0（为排除变量而关闭），保留以备恢复
  /// 四周加 [m] 像素余量，用**边缘复制**填充。
  ///
  /// 层图在边缘处 alpha 可能为 0（该层不覆盖那里），复制过去仍是 0 —— 这是对的：
  /// 那块本就该由其它层显示。真正要避免的是"有内容的边缘"被拉空。
  static Future<ui.Image> _addMargin(ui.Image src, int m) async {
    if (m <= 0) return src;
    final int w = src.width;
    final int h = src.height;
    final int W = w + 2 * m;
    final int H = h + 2 * m;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    final Paint p = Paint()..filterQuality = FilterQuality.low;
    final double mf = m.toDouble();

    c.drawImage(src, Offset(mf, mf), p);
    // 四边
    c.drawImageRect(src, Rect.fromLTWH(0, 0, 1, h.toDouble()),
        Rect.fromLTWH(0, mf, mf, h.toDouble()), p);
    c.drawImageRect(src, Rect.fromLTWH(w - 1.0, 0, 1, h.toDouble()),
        Rect.fromLTWH(w + mf, mf, mf, h.toDouble()), p);
    c.drawImageRect(src, Rect.fromLTWH(0, 0, w.toDouble(), 1),
        Rect.fromLTWH(mf, 0, w.toDouble(), mf), p);
    c.drawImageRect(src, Rect.fromLTWH(0, h - 1.0, w.toDouble(), 1),
        Rect.fromLTWH(mf, h + mf, w.toDouble(), mf), p);
    // 四角
    c.drawImageRect(src, const Rect.fromLTWH(0, 0, 1, 1),
        Rect.fromLTWH(0, 0, mf, mf), p);
    c.drawImageRect(src, Rect.fromLTWH(w - 1.0, 0, 1, 1),
        Rect.fromLTWH(w + mf, 0, mf, mf), p);
    c.drawImageRect(src, Rect.fromLTWH(0, h - 1.0, 1, 1),
        Rect.fromLTWH(0, h + mf, mf, mf), p);
    c.drawImageRect(src, Rect.fromLTWH(w - 1.0, h - 1.0, 1, 1),
        Rect.fromLTWH(w + mf, h + mf, mf, mf), p);

    final ui.Picture pic = rec.endRecording();
    final ui.Image out = await pic.toImage(W, H);
    pic.dispose();
    return out;
  }
}
