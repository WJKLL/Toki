// lib/core/widgets/steam_logo_icon.dart
// 编号：C-38 Steam 徽标自绘组件（v1.34.0 新增,Steam 工具 P-08 配套）
// 说明：以 CustomPainter 绘制 **官方 Steam 剪影造型**(路径源自 simple-icons
//   steam.svg 单色剪影,程序化转换为 Flutter Path,非手绘近似):
//   造型 = 粗圆环 + 环内卧式蒸汽机(右测飞轮/双圆环 + 顶管 + 左侧汽缸管),
//   颜色单一 tint —— 调用方传 MiuixTheme 取色(浅色 onSurface / 深色自动),
//   与 app_icons 矢量体系同语义(S-02 约定:未知图标名回退箭头,本组件为
//   自绘兜底,不占 MiuixIcons 槽位)。
// 性能:Path 静态只构建一次(static final);CustomPainter 仅首帧绘制一次,
//   静态 icon 复用同一 painter,零逐帧分配。
import 'package:flutter/widgets.dart';

/// Steam 徽标单色图标(自绘;尺寸/tint 由调用方控制)。
class SteamLogoIcon extends StatelessWidget {
  const SteamLogoIcon({super.key, required this.size, required this.tint});

  final double size;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SteamLogoPainter(tint),
    );
  }
}

class _SteamLogoPainter extends CustomPainter {
  const _SteamLogoPainter(this.color);

  final Color color;

  /// 官方剪影路径(viewBox 0..24,生成自 simple-icons steam.svg;
  /// 4 个子路径:主体外圈 / 左下汽缸细节 / 右侧飞轮外环 / 飞轮中心孔)。
  static final Path _path = Path()
    ..moveTo(11.979, 0)
    ..cubicTo(5.678, 0, 0.511, 4.86, 0.022, 11.037)
    ..lineTo(6.454, 13.695)
    ..cubicTo(6.999, 13.324, 7.657, 13.105, 8.366, 13.105)
    ..cubicTo(8.429, 13.105, 8.491, 13.109, 8.554, 13.111)
    ..lineTo(11.415, 8.969)
    ..lineTo(11.415, 8.91)
    ..cubicTo(11.415, 6.415, 13.443, 4.386, 15.939, 4.386)
    ..cubicTo(18.433, 4.386, 20.463, 6.417, 20.463, 8.913)
    ..cubicTo(20.463, 11.409, 18.433, 13.438, 15.939, 13.438)
    ..lineTo(15.834, 13.438)
    ..lineTo(11.758, 16.349)
    ..cubicTo(11.758, 16.401, 11.762, 16.454, 11.762, 16.508)
    ..cubicTo(11.762, 18.383, 10.247, 19.904, 8.372, 19.904)
    ..cubicTo(6.737, 19.904, 5.356, 18.731, 5.041, 17.177)
    ..lineTo(0.436, 15.27)
    ..cubicTo(1.862, 20.307, 6.486, 24, 11.979, 24)
    ..cubicTo(18.606, 24, 23.978, 18.627, 23.978, 12)
    ..cubicTo(23.978, 5.373, 18.605, 0, 11.979, 0)
    ..lineTo(11.979, 0)
    ..moveTo(7.54, 18.21)
    ..lineTo(6.067, 17.6)
    ..cubicTo(6.329, 18.143, 6.781, 18.599, 7.381, 18.85)
    ..cubicTo(8.678, 19.389, 10.174, 18.774, 10.713, 17.475)
    ..cubicTo(10.976, 16.845, 10.977, 16.156, 10.718, 15.526)
    ..cubicTo(10.459, 14.896, 9.968, 14.405, 9.341, 14.143)
    ..cubicTo(8.717, 13.883, 8.051, 13.894, 7.463, 14.113)
    ..lineTo(8.986, 14.743)
    ..cubicTo(9.942, 15.143, 10.395, 16.243, 9.995, 17.198)
    ..cubicTo(9.598, 18.155, 8.498, 18.608, 7.541, 18.21)
    ..lineTo(7.54, 18.21)
    ..lineTo(7.54, 18.21)
    ..moveTo(18.955, 8.907)
    ..cubicTo(18.955, 7.245, 17.602, 5.892, 15.94, 5.892)
    ..cubicTo(14.275, 5.892, 12.925, 7.245, 12.925, 8.907)
    ..cubicTo(12.925, 10.572, 14.275, 11.922, 15.94, 11.922)
    ..cubicTo(17.603, 11.922, 18.955, 10.572, 18.955, 8.907)
    ..lineTo(18.955, 8.907)
    ..moveTo(13.682, 8.902)
    ..cubicTo(13.682, 7.65, 14.695, 6.636, 15.947, 6.636)
    ..cubicTo(17.196, 6.636, 18.213, 7.65, 18.213, 8.902)
    ..cubicTo(18.213, 10.153, 17.196, 11.167, 15.947, 11.167)
    ..cubicTo(14.694, 11.167, 13.682, 10.153, 13.682, 8.902)
    ..lineTo(13.682, 8.902);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // viewBox 24 → 目标尺寸等比缩放。
    canvas.scale(size.width / 24, size.height / 24);
    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true;
    canvas.drawPath(_path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SteamLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
