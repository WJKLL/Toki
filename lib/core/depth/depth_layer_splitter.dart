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
import 'subject_segmentation.dart';

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
    this.subjectMask,
  });

  /// 已按 centerDepth 升序（**远 → 近**，渲染顺序即此）。
  final List<DepthLayer> layers;

  /// 工作尺寸（不含 margin）。
  final int workWidth;
  final int workHeight;

  /// 层图四周的余量。
  final int margin;

  /// 最终生效的主体 mask（闭运算 + 深度一致性过滤 + 膨胀之后的那份）。
  ///
  /// ★ 之所以带出来：调试时界面上该显示**真正参与分层的那一份**，而不是模型
  ///   原始输出 —— 两者不一致会让预览继续误导判断（这一点已经吃过亏）。
  final SubjectMask? subjectMask;

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
    // ★ 主体 mask（S-39）。非空时**强制 2 层**且层归属由它决定，不再按深度切；
    //   为空则退回原来的 Otsu 深度分层 —— 这是分割模型不可用/失败时的降级路径。
    SubjectMask? subject,
    // ★ 主体 mask 的膨胀量（**原图逻辑像素**，调用方通常传"层间位移差"）。
    //   背景层的位移比主体层大，背景层里那片"填充内容"会滑到主体轮廓之外，
    //   露出来就是"一块一块"。把主体层的覆盖范围外扩同样的距离即可盖住它 ——
    //   而膨胀区显示的是【原图】内容，所以看不出被扩大过。
    double subjectDilate = 0,
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
    final Float32List dw = _resampleDepth(depth, w, h);

    // ★ 主体 mask（S-39）：语义来源，优先于深度阈值。
    //
    //   为什么必须优先：深度只回答"远近"，回答不了"这是不是人"。实测插画上
    //   浅蓝格子裙被估成 2.52 m（比画面右侧背景柱子的 2.14 m 还远），纯深度
    //   阈值的等深线会横穿人体 —— 一小半身体被切进背景层，跟着背景一起动
    //   （用户实测："躯干和背后的背景混成同一层"）。反过来，前景柱子虽然离
    //   相机近，却会因此被 Otsu 判成主体。mask 同时修正这两个方向。
    //
    //   有 mask → 强制 2 层：层 0 = 背景（mask 外），层 1 = 主体（mask 内）。
    //   没 mask → 原逻辑（Otsu + 累积 alpha + 深度归属）。
    //
    //   ★ 还要把 mask【膨胀】一个"层间位移差"：
    //     背景层位移比主体层大，背景层里那片填充会滑到主体轮廓之外露出来 ——
    //     实测表现就是"背景不是一体的、移动时一块一块"。膨胀后主体层的覆盖
    //     范围外扩同样的距离，正好把滑出来的填充重新盖住；而膨胀区显示的是
    //     原图内容，因此视觉上完全看不出被扩大过。
    // ★ 先用【深度】把 mask 补全，再膨胀。
    //
    //   补全：分割模型漏抠的身体部位（实测："人物右腿背景无法分开"）会掉进
    //   背景层跟着背景动；以 mask 为种子沿深度连续方向生长即可补回。
    //   生长判断只需要粗深度，按 mask 分辨率降采样后做，比在工作尺寸上快
    //   一个数量级（mask 典型 561×1024，工作尺寸 1440×2600）。
    SubjectMask? subj = subject;
    if (subj != null) {
      final int sw = subj.width;
      final int sh = subj.height;
      if (sw > 0 && sh > 0 && w > 0 && h > 0) {
        // ① 闭运算：填补 mask 内部的凹陷与断裂（不推大整体轮廓）。
        subj = subj.closed(math.max(2, (sw * 0.02).round()));

        // ② ★ 深度连通筛选：剔掉"与身体之间隔着深度台阶"的误判块
        //    （实测那片实心背景就是它），同时保住手指/手臂这类与身体
        //    深度连续的边缘部位（全局阈值会把它们误剔）。
        //    按 mask 分辨率降采样深度即可（判断不需要高精度）。
        final Float32List lowDepth = Float32List(sw * sh);
        for (int y = 0; y < sh; y++) {
          final int sy = (y * h ~/ sh).clamp(0, h - 1);
          final int row = sy * w;
          for (int x = 0; x < sw; x++) {
            final int sx = (x * w ~/ sw).clamp(0, w - 1);
            lowDepth[y * sw + x] = dw[row + sx];
          }
        }
        subj = SubjectMask(
          width: sw,
          height: sh,
          data: _keepConnected(
            subj.data,
            lowDepth,
            sw,
            sh,
            // 相邻深度容差：略宽松，手指与手掌之间本身也有深度跳变
            tol: 0.15,
            // 种子 = mask 核心区域（高置信度的那部分）
            seedMin: 0.75,
          ),
        );
      }
      if (subjectDilate > 0.5 && photo.width > 0) {
        final SubjectMask s = subj;
        // 逻辑像素 → mask 自身分辨率的像素（在 mask 分辨率上膨胀，快一个数量级）
        subj = s.dilated((subjectDilate * s.width / photo.width).round());
      }
    }
    final Float32List? mw = subj?.resample(w, h);
    if (mw != null) layerCount = 2;

    // ★ 2 层时的切点用 Otsu 自动求，而不是固定 0.5 等分。
    //   等分的边界会【横穿背景】（实测："背景被分割"、树干断裂）——
    //   因为背景的深度往往跨越中点。Otsu 找的是"类间方差最大"的阈值，
    //   落点在深度分布的两个峰之间，通常正是主体与背景的分界处。
    final double split = layerCount == 2
        ? _otsuSplit(dw, 64).clamp(0.12, 0.88)
        : 0.5;

    // ★ 填充源：用来填"不属于本层"的区域。
    //   层图的 RGB **不能**直接用整张原图 —— 最远层里会【含着主体】，主体层
    //   移开后就会露出"原位置的另一个主体"。
    //
    //   演进过程（全部由真机反馈驱动）：
    //     ① 直接用原图      → 露出一个清晰的主体（"底图的人物会露出"）
    //     ② 整图大模糊      → 人物糊了，但形状与配色仍在，是一块"被抠掉的部分"
    //     ③ ★ 背景色扩散    → 背景的颜色沿边界长进主体区域，露出的是背景的自然
    //                          延续，而不是一块对不上的色斑
    //   （必须放在 split 之后 —— 扩散要先知道哪些像素算背景。）
    final Uint8List soft = _diffusedFill(
      src: src,
      w: w,
      h: h,
      depth: dw,
      split: split,
    );

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
        final double a;
        final double own;
        if (mw != null) {
          // ── 有语义 mask 的 2 层 ──
          //
          // 层 1（主体）：own = 1（整层原图），alpha = **陡化后**的 mask。
          //
          //   ★ 陡化是必须的：isnet/modnet 输出的是 soft 概率，背景区域也有
          //     0.3~0.5 的值。直接拿它当 alpha，背景就会被 30~50% 地拉进主体层，
          //     主体一动、那部分背景就跟着动 —— 实测："人物右腿背景又跟着一起
          //     了"。主体遮罩预览里整幅画面泛红，正是这个原因。
          //     smoothstep(0.45, 0.75) 把中间值压掉：只有真正判定为主体的像素
          //     才完全不透明；因为是渐变而非硬阈值，边缘不会出锯齿。
          //
          // 层 0（背景）：alpha 恒 1 铺底；own 用更靠前的 smoothstep(0.35, 0.65)
          //   把"原图↔填充"的混合带压窄。
          final double m = mw[p];
          a = i == 0 ? 1.0 : _smoothstep(0.45, 0.75, m);
          own = i == 0 ? 1.0 - _smoothstep(0.35, 0.65, m) : 1.0;
        } else {
          final int bi = (dw[p] * (bins - 1)).round().clamp(0, bins - 1);
          a = aOf[bi];
          // 归属：本层覆盖、且不被任何更近的层覆盖的那部分。
          own = aNext == null ? a : (a - aNext[bi]).clamp(0.0, 1.0);
        }
        if (a <= 0.0) continue; // 本层不覆盖这里 → 留全透明，合成时无影响
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
      // 带出最终生效的 mask，供界面与实际渲染做一致对照。
      subjectMask: subj,
    );
  }

  /// 在 mask 内部做【深度连通】筛选：只保留与核心区域深度连续地连通的像素。
  ///
  /// ★ 为什么从"全局阈值"换成"连通性"（实测："手指被分割了一点"）
  ///   [_depthConsistency] 用的是全局判据 —— 比核心中位数远 0.18 就剔。
  ///   这对误判的背景块有效，但会误伤身体的边缘部位：手指、手臂这类细长结构
  ///   深度估计噪声大，很容易越线，于是被整段切掉。
  ///
  ///   而两者的真正区别不在"深度绝对值"，而在【与身体是否深度连续地相连】：
  ///     · 手指/手臂 —— 与手掌、躯干之间深度是渐变的 → 保留；
  ///     · 误判背景块 —— 与人体之间隔着深度台阶  → 剔除。
  ///   于是改为在 mask 内部从核心区域做 BFS，只走"局部深度连续"的邻居。
  ///
  /// [tol] 相邻像素深度容差；[seedMin] 作为种子的 mask 核心阈值。
  static Float32List _keepConnected(
    Float32List mask,
    Float32List depth,
    int w,
    int h, {
    required double tol,
    required double seedMin,
  }) {
    final Float32List out = Float32List(mask.length);
    final Int32List seen = Int32List(mask.length);
    final Int32List queue = Int32List(mask.length);
    int head = 0;
    int tail = 0;

    for (int i = 0; i < mask.length; i++) {
      if (mask[i] >= seedMin) {
        out[i] = mask[i];
        seen[i] = 1;
        queue[tail++] = i;
      }
    }
    if (tail == 0) return mask; // 没有核心区域 → 不动它，交给后续陡化处理

    while (head < tail) {
      final int i = queue[head++];
      final int y = i ~/ w;
      final int x = i - y * w;
      final double di = depth[i];
      for (int d = 0; d < 4; d++) {
        final int nx = x + (d == 0 ? -1 : (d == 1 ? 1 : 0));
        final int ny = y + (d == 2 ? -1 : (d == 3 ? 1 : 0));
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final int n = ny * w + nx;
        if (seen[n] != 0) continue;
        if (mask[n] <= 0.0) continue; // 只在 mask 内部走（不外扩）
        if ((depth[n] - di).abs() > tol) continue; // 必须与邻居深度连续
        seen[n] = 1;
        out[n] = mask[n];
        queue[tail++] = n;
      }
    }
    return out;
  }

  /// 把"mask 判为主体、但深度明显属于背景"的像素剔掉。
  ///
  /// 已被 [_keepConnected] 取代：全局阈值会误伤手指/手臂这类深度噪声大的
  /// 边缘部位（实测："手指被分割了一点"）。保留备查。
  ///
  /// ★ 为什么需要（实测：主体层素材截图）
  ///   主体层素材里，人物之外还含着一片实心不透明的背景（树荫/路面）——
  ///   分割模型误判了一块。这类误判区域**几乎总是深度比人体远得多**，
  ///   于是可以用深度一致性识别并剔除。
  ///
  /// ★ 注意这是【收缩】，不是早先失败过的"生长"
  ///   生长只增不减、一旦蔓延无法回收（试了两版都失败）。这里只减不增：
  ///   以 mask 核心区域（>0.75）的深度中位数为基准，明显更远的像素一律剔出。
  ///   人体各部位（腿、手臂）与躯干深度接近，不会被误伤。
  // ignore: unused_element
  static Float32List _depthConsistency(
    Float32List mask,
    Float32List depth,
  ) {
    final List<double> core = <double>[];
    for (int i = 0; i < mask.length; i++) {
      if (mask[i] > 0.75) core.add(depth[i]);
    }
    if (core.length < 16) return mask;
    core.sort();
    final double med = core[core.length ~/ 2];
    // 比核心深度再远 0.18 个归一化单位以上 → 判定为背景误判。
    final double floorDepth = med - 0.18;
    final Float32List out = Float32List.fromList(mask);
    for (int i = 0; i < out.length; i++) {
      if (out[i] > 0.0 && depth[i] < floorDepth) out[i] = 0.0;
    }
    return out;
  }

  /// 以 mask 为**种子**、沿【深度连续】方向生长，把分割模型漏抠的身体部位补回来。
  ///
  /// ★ 为什么需要（实测："人物右腿背景无法分开"）
  ///   分割模型对身体边缘部位（被遮挡的腿、与背景配色接近的衣物）经常漏抠。
  ///   漏掉的部分会掉进背景层、跟着背景一起动 —— 用户看到的就是"腿和背景分不开"。
  ///   但深度信息还在：腿与躯干的深度是连续的，而腿与背景之间有台阶。
  ///
  /// ★ 为什么这次能成，而早先的"单点种子区域生长"不行
  ///   那次以**一个点**为种子、用全局梯度阈值判断，实测阈值从 0.028 到 0.065
  ///   就从"几乎不长"直接跳到"泄漏 84%"，中间没有稳定区间（深度图是软的，
  ///   梯度不够锐利）。这次种子是**整片语义 mask**（几乎不会误判），判据换成
  ///   更稳的"相邻像素深度差"，并额外用 [maxSteps] 限制生长距离，因此不会
  ///   顺着平坦的背景一路蔓延出去。
  ///
  /// [tol] 相邻像素深度容差（归一化深度单位）；[maxSteps] 最大生长步数；
  /// [minDepth] 深度下限 —— 低于它的像素一律不生长。
  // ★ 已废弃：实机两版（先纯"局部深度连续"、后加"深度下限"）都会把周围背景
  //   收纳进主体层。改用 SubjectMask.closed（形态学闭运算）。保留备查。
  // ignore: unused_element
  static Float32List _growByDepth(
    Float32List mask,
    Float32List depth,
    int w,
    int h, {
    required double tol,
    required int maxSteps,
    double minDepth = 0.0,
  }) {
    final Float32List out = Float32List(mask.length);
    final Int32List dist = Int32List(mask.length);
    final Int32List queue = Int32List(mask.length);
    int head = 0;
    int tail = 0;

    for (int i = 0; i < mask.length; i++) {
      if (mask[i] > 0.5) {
        out[i] = 1.0;
        dist[i] = 1;
        queue[tail++] = i;
      }
    }

    while (head < tail) {
      final int i = queue[head++];
      final int step = dist[i];
      if (step >= maxSteps) continue;
      final int y = i ~/ w;
      final int x = i - y * w;
      final double di = depth[i];
      for (int d = 0; d < 4; d++) {
        final int nx = x + (d == 0 ? -1 : (d == 1 ? 1 : 0));
        final int ny = y + (d == 2 ? -1 : (d == 3 ? 1 : 0));
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final int n = ny * w + nx;
        if (dist[n] != 0) continue;
        if ((depth[n] - di).abs() > tol) continue;
        // ★ 深度下限：背景所在的深度不再蔓延。
        //   只看"局部连续"是不够的 —— 人物周围的背景（路面、花瓣）深度常常
        //   和身体接近，光看局部差会把整片背景一起吞进来（实测："渲染图带着
        //   周围背景一起动了"）。以 mask 外区域的深度中位数作为背景水平，
        //   低于它就不再生长。
        if (depth[n] < minDepth) continue;
        dist[n] = step + 1;
        out[n] = 1.0;
        queue[tail++] = n;
      }
    }
    return out;
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

  /// 背景色【扩散填充】：用周围背景的颜色把非背景区域补全。
  ///
  /// 为什么不用"整图大模糊"（[_blurredRgba]）：
  ///   模糊得到的是【局部平均色】—— 背景有明暗渐变或结构时，主体位置会呈现
  ///   一块与周围对不上的色斑，真机上看就是"被抠掉的部分"。
  ///   扩散填充让背景的颜色【沿边界长进】主体区域，位移后露出的是背景的自然
  ///   延续，而不是一块平均色。
  ///
  /// 做法（低分辨率迭代扩散）：
  ///   1) 把原图块平均降到长边 [longSide] 的低分辨率网格，只统计【背景】像素
  ///      （深度 < [split]），得到每个格子的背景色与"已知度"；
  ///   2) 反复松弛 [rounds] 轮：未知格子取四邻域按已知度加权的平均色，并把自身
  ///      已知度往上提一点 —— 颜色于是从背景边界逐层"渗"进主体区域；
  ///   3) 双线性放大回工作尺寸。
  ///
  /// 在低分辨率上迭代是有意为之：既快（约 1.6 万格 × 48 轮），又天然平滑 ——
  /// 主体背后本来就没有被拍到的内容，任何方案都只能"猜"，而平滑渐变是最不容易
  /// 露馅的猜法。
  static Uint8List _diffusedFill({
    required Uint8List src,
    required int w,
    required int h,
    required Float32List depth,
    required double split,
  }) {
    const int longSide = 96;
    const int rounds = 48;

    final double s = longSide / math.max(w, h);
    final int lw = math.max(4, (w * s).round());
    final int lh = math.max(4, (h * s).round());
    final int ln = lw * lh;

    final Float32List cr = Float32List(ln);
    final Float32List cg = Float32List(ln);
    final Float32List cb = Float32List(ln);
    final Float32List ck = Float32List(ln); // 已知度 0..1

    // ── 1) 块平均降采样（只累积背景像素）──
    for (int y = 0; y < h; y++) {
      final int row = (y * lh ~/ h).clamp(0, lh - 1) * lw;
      for (int x = 0; x < w; x++) {
        final int p = y * w + x;
        if (depth[p] >= split) continue; // 非背景：不贡献颜色
        final int i = row + (x * lw ~/ w).clamp(0, lw - 1);
        final int o = p * 4;
        cr[i] += src[o];
        cg[i] += src[o + 1];
        cb[i] += src[o + 2];
        ck[i] += 1.0;
      }
    }
    // 颜色取平均；已知度 = 该格子里背景像素的占比。
    final double blockArea = (w / lw) * (h / lh);
    for (int i = 0; i < ln; i++) {
      final double n = ck[i];
      if (n > 0) {
        cr[i] /= n;
        cg[i] /= n;
        cb[i] /= n;
      }
      ck[i] = (n / blockArea).clamp(0.0, 1.0);
    }

    // ── 2) 松弛扩散：颜色从背景边界逐层向主体区域渗透 ──
    for (int it = 0; it < rounds; it++) {
      for (int y = 0; y < lh; y++) {
        for (int x = 0; x < lw; x++) {
          final int i = y * lw + x;
          if (ck[i] >= 0.999) continue; // 已完全已知，不再改动
          double sr = 0;
          double sg = 0;
          double sb = 0;
          double sk = 0;
          for (int d = 0; d < 4; d++) {
            final int nx = x + (d == 0 ? -1 : (d == 1 ? 1 : 0));
            final int ny = y + (d == 2 ? -1 : (d == 3 ? 1 : 0));
            if (nx < 0 || nx >= lw || ny < 0 || ny >= lh) continue;
            final int j = ny * lw + nx;
            final double k = ck[j];
            if (k <= 0.0) continue;
            sr += cr[j] * k;
            sg += cg[j] * k;
            sb += cb[j] * k;
            sk += k;
          }
          if (sk <= 1e-6) continue;
          cr[i] = sr / sk;
          cg[i] = sg / sk;
          cb[i] = sb / sk;
          // 已知度提升：下一轮这个格子就能把颜色继续往更深处传。
          ck[i] = math.min(1.0, ck[i] + sk * 0.14);
        }
      }
    }

    // ── 3) 双线性放大回工作尺寸 ──
    double bilerp(
      Float32List c,
      int i00,
      int i01,
      int i10,
      int i11,
      double fx,
      double fy,
    ) {
      final double t = c[i00] + (c[i01] - c[i00]) * fx;
      final double b = c[i10] + (c[i11] - c[i10]) * fx;
      return t + (b - t) * fy;
    }

    final Uint8List out = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      final double sy = (y + 0.5) / h * lh - 0.5;
      final int y0 = sy.floor().clamp(0, lh - 1);
      final int y1 = math.min(y0 + 1, lh - 1);
      final double fy = (sy - y0).clamp(0.0, 1.0);
      for (int x = 0; x < w; x++) {
        final double sx = (x + 0.5) / w * lw - 0.5;
        final int x0 = sx.floor().clamp(0, lw - 1);
        final int x1 = math.min(x0 + 1, lw - 1);
        final double fx = (sx - x0).clamp(0.0, 1.0);
        final int i00 = y0 * lw + x0;
        final int i01 = y0 * lw + x1;
        final int i10 = y1 * lw + x0;
        final int i11 = y1 * lw + x1;
        final int o = (y * w + x) * 4;
        out[o] = bilerp(cr, i00, i01, i10, i11, fx, fy).round().clamp(0, 255);
        out[o + 1] = bilerp(
          cg,
          i00,
          i01,
          i10,
          i11,
          fx,
          fy,
        ).round().clamp(0, 255);
        out[o + 2] = bilerp(
          cb,
          i00,
          i01,
          i10,
          i11,
          fx,
          fy,
        ).round().clamp(0, 255);
        out[o + 3] = 255;
      }
    }
    return out;
  }

  /// 原图的大幅模糊版（填充层的非本层区域）。
  ///
  /// 已被 [_diffusedFill] 取代（背景色扩散更自然，见其说明），保留以备对照与回退。
  // ignore: unused_element
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
