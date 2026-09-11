// lib/core/depth/subject_edit_mask.dart
// 编号：U-14 主体手动修正层（涂刷 / 擦除）
//
// ★ 为什么要有它（本轮结论）
//   自动分割在物体边界模糊时永远有误差 —— 我们为此在"深度阈值 / 连通性 /
//   深度下限"之间来回摇摆了十几轮，因为它本质上是【想让算法替用户做判断】。
//   而"哪块像素是人"这件事，用户点一下、刷一笔，比任何启发式都准。
//
// ★ 与 AI 结果的关系：互补，不是替代
//   编辑层是叠加在【AI 管线之后】的一层覆盖：
//     AI mask → 闭运算 → 深度连通筛选 → 深度下限 → 膨胀 → ★应用本层
//   所以用户只需要修 AI 做错的那一两处，不必从零开始画；
//   而 AI 那份也仍然在承担绝大部分工作。
//
// ★ 为什么用「有符号」而不是两张图
//   +1 = 用户刷过（强制为主体）
//   −1 = 用户擦过（强制为背景）
//    0 = 未编辑（沿用 AI 的判断）
//   一张图同时表达三种状态，内存与遍历都省一半。

import 'dart:math' as math;
import 'dart:typed_data';

/// 主体手动修正层（分辨率与 AI mask 一致）。
class SubjectEditMask {
  SubjectEditMask(this.width, this.height)
      : data = Float32List(width * height);

  final int width;
  final int height;

  /// 0 = 未编辑，>0 = 涂为主体，<0 = 擦为背景。
  final Float32List data;

  /// 是否没有任何笔迹（没有任何编辑 → 整条管线可以被短路掉）。
  bool get isEmpty {
    for (int i = 0; i < data.length; i++) {
      if (data[i] != 0) return false;
    }
    return true;
  }

  /// 清空全部笔迹。
  void clear() => data.fillRange(0, data.length, 0);

  /// 单点涂刷。[u]/[v] 为归一化坐标，[radius] 为归一化半径（相对短边）。
  ///
  /// 圆盘用硬边而非羽化：笔迹要"所见即所得"，边缘的自然度交给后续处理。
  void stamp(double u, double v, double radius, {required bool erase}) {
    final double cx = u * width;
    final double cy = v * height;
    final double r = math.max(1.0, radius * math.min(width, height));
    final double value = erase ? -1.0 : 1.0;

    final int x0 = math.max(0, (cx - r).floor());
    final int x1 = math.min(width - 1, (cx + r).ceil());
    final int y0 = math.max(0, (cy - r).floor());
    final int y1 = math.min(height - 1, (cy + r).ceil());
    final double r2 = r * r;

    for (int y = y0; y <= y1; y++) {
      final double dy = y - cy;
      final double dy2 = dy * dy;
      final int row = y * width;
      for (int x = x0; x <= x1; x++) {
        final double dx = x - cx;
        if (dx * dx + dy2 > r2) continue;
        data[row + x] = value;
      }
    }
  }

  /// 两点之间连续涂刷。
  ///
  /// ★ 必须做插值：手指快速划过时事件点之间会隔十几个像素，只 stamp 端点会
  ///   留下断续的圆点，用户看到的是一条虚线的笔迹。
  void stroke(
    double u0,
    double v0,
    double u1,
    double v1,
    double radius, {
    required bool erase,
  }) {
    final double dx = (u1 - u0) * width;
    final double dy = (v1 - v0) * height;
    final double dist = math.sqrt(dx * dx + dy * dy);
    // 步长取笔刷半径的 1/3：既不留缝，也不至于重复涂太多
    final double rPx = math.max(1.0, radius * math.min(width, height));
    final int steps = math.max(1, (dist / (rPx / 3.0)).ceil());
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      stamp(u0 + (u1 - u0) * t, v0 + (v1 - v0) * t, radius, erase: erase);
    }
  }

  /// 把笔迹叠加到 [mask] 上（就地修改）。
  ///
  /// 用户刷过 → 1.0；擦过 → 0.0；未编辑 → 保持 AI 的结果不动。
  void applyTo(Float32List mask) {
    final int n = math.min(data.length, mask.length);
    for (int i = 0; i < n; i++) {
      final double e = data[i];
      if (e > 0) {
        mask[i] = 1.0;
      } else if (e < 0) {
        mask[i] = 0.0;
      }
    }
  }

  SubjectEditMask copy() {
    final SubjectEditMask m = SubjectEditMask(width, height);
    m.data.setAll(0, data);
    return m;
  }
}
