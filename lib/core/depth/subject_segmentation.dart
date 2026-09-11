// lib/core/depth/subject_segmentation.dart
// 编号：S-39 主体分割服务（平台无关契约）
//
// ★ 为什么需要它（真机实测驱动）
//   深度分层只能回答"远近"，回答不了"这是不是人"：
//     · 插画上模型把浅蓝格子裙估成 2.52 m —— 比画面右侧背景柱子的 2.14 m 还远，
//       于是裙子和背景被切进同一层，跟着一起动（用户实测："躯干和背后的背景
//       混成同一层"）；
//     · 反过来，任何"离相机近的东西"（前景柱子、栏杆）又会被 Otsu 判成主体，
//       主体层里混进大块背景。
//   分割 mask 提供的是【语义】，用它去约束【深度】的层归属，两个症状一次解决：
//     mask 内 → 强制主体层；mask 外 → 强制背景层。
//
// ★ 与 S-31 深度推理的分工
//   S-31 负责"每个像素有多远"；S-39 负责"每个像素是不是主体"。两者都拿到后，
//   分层才既有正确的边界（语义）又有正确的运动（深度）。
//
// ★ 注册制（对齐 DepthInferenceRegistry）
//   主项目注册 ONNX 实现；镜像（鸿蒙）可注册自己的实现，未注册时
//   `instance` 为 null，调用方降级回纯深度分层，**不抛异常**。
import 'dart:math' as math;
import 'dart:typed_data';

/// 主体分割结果：前景概率 0..1（soft mask，可与深度加权融合）。
///
/// 尺寸与【原图同宽高比】—— letterbox 的 padding 已在实现里裁掉，
/// 因此可以直接按归一化 uv 与原图/深度图对齐。
class SubjectMask {
  SubjectMask({
    required this.width,
    required this.height,
    required this.data,
  });

  final int width;
  final int height;

  /// 逐像素前景概率（0..1），行优先。
  final Float32List data;

  int get length => width * height;

  /// 前景占比（0..1）—— 实现侧用它做"真人 / 插画"的调度判据。
  double get coverage {
    if (data.isEmpty) return 0;
    int n = 0;
    for (int i = 0; i < data.length; i++) {
      if (data[i] > 0.5) n++;
    }
    return n / data.length;
  }

  /// 读某点的前景概率（归一化坐标 u,v ∈ 0..1，最近邻）。
  double at(double u, double v) {
    if (width <= 0 || height <= 0) return 0;
    final int x = (u * width).floor().clamp(0, width - 1);
    final int y = (v * height).floor().clamp(0, height - 1);
    return data[y * width + x];
  }

  /// 形态学膨胀（返回新 mask）—— 把主体覆盖范围外扩 [radius] 像素。
  ///
  /// ★ 为什么要扩：
  ///   背景层的位移比主体层大，背景层里那片"填充内容"会滑到主体轮廓之外
  ///   露出来 —— 实测表现就是"背景不是一体的、移动时一块一块"。先把 mask
  ///   扩出去，滑出来的填充就被主体层重新盖住；而主体层的 RGB 恒为原图，
  ///   所以扩大覆盖范围在视觉上完全无代价。
  ///
  /// 在 mask 自己的分辨率上做（典型 561×1024，比工作尺寸 1440×2600 小一个
  /// 数量级），比放到工作尺寸上做快得多。
  SubjectMask dilated(int radius) {
    if (radius <= 0) return this;
    final int r = radius.clamp(0, 64);
    // 可分离膨胀：先横后纵，各取 (2r+1) 窗口的最大值。
    final Float32List tmp = Float32List(data.length);
    for (int y = 0; y < height; y++) {
      final int base = y * width;
      for (int x = 0; x < width; x++) {
        double m = 0;
        final int x0 = math.max(0, x - r);
        final int x1 = math.min(width - 1, x + r);
        for (int k = x0; k <= x1; k++) {
          final double v = data[base + k];
          if (v > m) m = v;
        }
        tmp[base + x] = m;
      }
    }
    final Float32List out = Float32List(data.length);
    for (int y = 0; y < height; y++) {
      final int y0 = math.max(0, y - r);
      final int y1 = math.min(height - 1, y + r);
      for (int x = 0; x < width; x++) {
        double m = 0;
        for (int k = y0; k <= y1; k++) {
          final double v = tmp[k * width + x];
          if (v > m) m = v;
        }
        out[y * width + x] = m;
      }
    }
    return SubjectMask(width: width, height: height, data: out);
  }

  /// 双线性重采样到 [w]×[h]。
  ///
  /// 供 DepthLayerSplitter 对齐到它自己的工作尺寸用 —— mask 是软概率，
  /// 放大到工作尺寸不会有副作用。
  Float32List resample(int w, int h) {
    final Float32List out = Float32List(w * h);
    if (width <= 0 || height <= 0) return out;
    for (int y = 0; y < h; y++) {
      final double sy = (y + 0.5) / h * height - 0.5;
      final int y0 = sy.floor().clamp(0, height - 1);
      final int y1 = math.min(y0 + 1, height - 1);
      final double fy = (sy - y0).clamp(0.0, 1.0);
      for (int x = 0; x < w; x++) {
        final double sx = (x + 0.5) / w * width - 0.5;
        final int x0 = sx.floor().clamp(0, width - 1);
        final int x1 = math.min(x0 + 1, width - 1);
        final double fx = (sx - x0).clamp(0.0, 1.0);
        final double top = data[y0 * width + x0] +
            (data[y0 * width + x1] - data[y0 * width + x0]) * fx;
        final double bot = data[y1 * width + x0] +
            (data[y1 * width + x1] - data[y1 * width + x0]) * fx;
        out[y * w + x] = top + (bot - top) * fy;
      }
    }
    return out;
  }
}

/// 主体分割服务契约。
abstract interface class SubjectSegmentation {
  /// 当前平台是否可用（模型加载失败 / 未注册 → false）。
  ///
  /// 与 S-31 的 DepthInference 保持一致：模型加载本身是异步的，故这里也是 Future。
  Future<bool> isAvailable();

  /// 对原图字节跑一次分割。
  ///
  /// 失败或不可用一律返回 null —— 调用方**必须**能降级回纯深度分层，
  /// 不允许让整条空间壁纸链路因为分割失败而中断。
  Future<SubjectMask?> segment(Uint8List imageBytes);
}

/// 注册表：未注册 → [instance] 为 null（调用方降级）。
abstract final class SubjectSegmentationRegistry {
  static SubjectSegmentation? _impl;

  /// 注册平台实现（镜像的鸿蒙实现也走这里）。
  static void register(SubjectSegmentation impl) => _impl = impl;

  static SubjectSegmentation? get instance => _impl;
}
