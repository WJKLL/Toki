// lib/presentation/widgets/c32_ring_progress.dart
// 编号:C-32 环形进度通用组件(v1.21.0)
// 说明:从 card_combo._RingPainter **1:1 抽取**(小米运动/健康粗环:
//   浅色轨道整圈 + 主色进度弧,12 点顺时针,ringW≈直径×0.16),
//   供「今日剩余」(C-28)与「课程倒计时」(C-33)复用,视觉逐像素一致。
//   C32AnimatedRing = 环形 + 平滑动画壳:progress 目标变化 →
//   500-800ms easeInOut 补间(仅圆环区 RepaintBoundary 重绘,不重建卡片);
//   animate=false(动效开关关闭 = 低性能档)直接跳变,零 ticker。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 环形进度 painter(1:1 来自 card_combo._RingPainter)。
class RingProgressPainter extends CustomPainter {
  const RingProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  /// 剩余比例 0..1。
  final double progress;

  /// 进度主色(高对比主题色)。
  final Color color;

  /// 轨道浅色。
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset c = Offset(r, r);
    // 粗环宽 ≈ 直径 × 0.16(小米运动/健康粗环观感)。
    final double ringW = size.width * 0.16;
    final Rect ring = Rect.fromCircle(center: c, radius: r - ringW / 2);
    // 1) 浅色轨道整圈(始终显示 → 时间结束仍留完整粗环)。
    canvas.drawArc(
      ring,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..color = backgroundColor,
    );
    // 2) 进度弧:12 点起顺时针,剩余 100% 整圈、按比例顺时针缩短。
    final double ratio = progress.clamp(0.0, 1.0);
    if (ratio > 0.0) {
      canvas.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * ratio,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RingProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.backgroundColor != backgroundColor;
}

/// 带动画的环形进度(仅环形区重绘)。
class C32AnimatedRing extends StatefulWidget {
  const C32AnimatedRing({
    super.key,
    required this.progress,
    required this.color,
    required this.backgroundColor,
    this.size = 64,
    this.animate = true,
  });

  /// 目标进度 0..1(变化 → 平滑补间)。
  final double progress;

  /// 进度主色。
  final Color color;

  /// 轨道浅色。
  final Color backgroundColor;

  /// 圆环边长(默认 64,与今日剩余卡一致)。
  final double size;

  /// false = 直接跳变(动效开关关闭 / 低性能档),不启动任何动画。
  final bool animate;

  @override
  State<C32AnimatedRing> createState() => _C32AnimatedRingState();
}

class _C32AnimatedRingState extends State<C32AnimatedRing>
    with SingleTickerProviderStateMixin {
  static const Duration _kAnimDuration = Duration(milliseconds: 800);

  /// 补间动画控制器:静止时停在末端,零 ticker。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kAnimDuration,
    value: widget.progress.clamp(0.0, 1.0), // 冷启动直达当前值,不播入场
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didUpdateWidget(covariant C32AnimatedRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double target = widget.progress.clamp(0.0, 1.0);
    if (oldWidget.progress != widget.progress) {
      if (!widget.animate) {
        // 低性能档:直接跳变,零动画帧。
        _controller.value = target;
        return;
      }
      if (_controller.isAnimating) {
        // 连续变化:按剩余目标重定向(不打断正在进行的补间)。
        _controller.animateTo(
          target,
          duration: _kAnimDuration,
          curve: Curves.easeInOut,
        );
      } else {
        _controller.animateTo(target);
      }
    } else if (oldWidget.animate != widget.animate && !widget.animate) {
      _controller.stop();
      _controller.value = target;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _progress,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            size: Size.square(widget.size),
            painter: RingProgressPainter(
              progress: _progress.value,
              color: widget.color,
              backgroundColor: widget.backgroundColor,
            ),
          );
        },
      ),
    );
  }
}
