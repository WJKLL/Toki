// lib/presentation/widgets/kernel/spatial_styled_image.dart
// 编号：C-69 样式化图案渲染器（Logo / 贴纸 / 表情 / 内置图标）
//
// 与 C-68（文字渲染器）并列：组件的两大内容类型之一。
//   · 文字类：艺术字 / 时钟 / 日期 / 心情  → C-68
//   · 图案类：Logo / 贴纸 / 表情 / 图标    → 本文件
//
// ★ 可调维度
//   尺寸 / 着色 / 圆形裁切 / 圆角 / 填充方式 / 阴影 / 不透明度
//
// ★ 着色（tint）的一个陷阱
//   用 BlendMode.srcIn 着色是"保留 alpha、替换 RGB" —— 对**带透明的 PNG**
//   正确（Logo / 图标都是这种）；但对不透明的照片会变成一整块纯色。
//   所以这里只在调用方显式给了 tint 时才着色，且文档写明适用场景。
//
// ★ 为什么裁切放在这里而不是调用方
//   图案在画面上要参与视差与缩放，外层会套 Transform；裁切必须在**内层**完成，
//   否则变换会把裁切边界一起放大、圆形变椭圆。
import 'package:flutter/widgets.dart';

/// 用统一样式渲染一张图案。
class SpatialStyledImage extends StatelessWidget {
  const SpatialStyledImage({
    super.key,
    required this.image,
    this.size = 120,
    this.tint,
    this.circle = false,
    this.rounded = 0,
    this.cover = true,
    this.shadowBlur = 0,
    this.shadowDy = 0,
    this.shadowColor = const Color(0x99000000),
    this.opacity = 1,
  });

  /// 已解码的图（调用方持有并复用；本组件不负责 dispose）。
  final ImageProvider image;

  /// 显示边长（逻辑像素）。
  final double size;

  /// 着色；null = 保留原色。**只对带透明的 PNG 有意义**（见文件头说明）。
  final Color? tint;

  /// 圆形裁切（头像 / 圆形徽标）。
  final bool circle;

  /// 圆角半径（[circle] 为 true 时忽略）。
  final double rounded;

  /// true = cover（填满、可能裁掉边），false = contain（完整显示、可能留边）。
  final bool cover;

  final double shadowBlur;
  final double shadowDy;
  final Color shadowColor;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    Widget img = Image(
      image: image,
      width: size,
      height: size,
      fit: cover ? BoxFit.cover : BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );

    if (tint != null) {
      img = ColorFiltered(
        colorFilter: ColorFilter.mode(tint!, BlendMode.srcIn),
        child: img,
      );
    }

    // 裁切在内层（见文件头）：先裁成形状，再让外层去做变换/阴影。
    img = ClipRRect(
      borderRadius: circle
          ? BorderRadius.circular(size / 2)
          : BorderRadius.circular(rounded),
      child: img,
    );

    if (shadowBlur > 0) {
      img = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: circle
              ? BorderRadius.circular(size / 2)
              : BorderRadius.circular(rounded),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: shadowColor,
              blurRadius: shadowBlur,
              offset: Offset(0, shadowDy),
            ),
          ],
        ),
        child: img,
      );
    }

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: img,
    );
  }
}
