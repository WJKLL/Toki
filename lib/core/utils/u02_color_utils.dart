// lib/core/utils/u02_color_utils.dart
// 编号：U-02 颜色工具（色值解析 / 转换，Hex ↔ ARGB，对比度）
// 说明：纯函数静态工具，零状态、零分配热点（输出直接复用 StringBuffer）。
import 'dart:math' as math;
import 'dart:ui' show Color;

abstract final class U02ColorUtils {
  /// Color → '#RRGGBB'（大写，不含 alpha）。
  static String toHex(Color color) {
    final int rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Color → '#AARRGGBB'（大写，含 alpha）。
  static String toArgbHex(Color color) {
    final int argb = color.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  /// '#RGB' / '#RRGGBB' / '#AARRGGBB' → Color；解析失败返回 null。
  static Color? fromHex(String hex) {
    final String s = hex.replaceFirst('#', '').trim();
    if (s.length == 3) {
      return _fromRgb(s[0], s[1], s[2]);
    }
    if (s.length == 6) {
      return _fromRgb(s.substring(0, 2), s.substring(2, 4), s.substring(4, 6));
    }
    if (s.length == 8) {
      final int? a = int.tryParse(s.substring(0, 2), radix: 16);
      final int? r = int.tryParse(s.substring(2, 4), radix: 16);
      final int? g = int.tryParse(s.substring(4, 6), radix: 16);
      final int? b = int.tryParse(s.substring(6, 8), radix: 16);
      if (a == null || r == null || g == null || b == null) return null;
      return Color.fromARGB(a, r, g, b);
    }
    return null;
  }

  static Color? _fromRgb(String r, String g, String b) {
    final int? ri = int.tryParse(r, radix: 16);
    final int? gi = int.tryParse(g, radix: 16);
    final int? bi = int.tryParse(b, radix: 16);
    if (ri == null || gi == null || bi == null) return null;
    return Color.fromARGB(0xFF, ri, gi, bi);
  }

  /// WCAG 相对亮度（0.0 ~ 1.0）。
  static double relativeLuminance(Color color) {
    double channel(int c) {
      final double v = c / 255.0;
      return v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final int argb = color.toARGB32();
    final double r = channel((argb >> 16) & 0xFF);
    final double g = channel((argb >> 8) & 0xFF);
    final double b = channel(argb & 0xFF);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// 两种颜色间的 WCAG 对比度（≥4.5 达标 AA）。
  static double contrastRatio(Color a, Color b) {
    final double la = relativeLuminance(a);
    final double lb = relativeLuminance(b);
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 前景文字颜色（黑 / 白）按对比度自动选择。
  static Color onColor(Color background) {
    const Color white = Color(0xFFFFFFFF);
    const Color black = Color(0xFF000000);
    return contrastRatio(background, white) >= contrastRatio(background, black)
        ? white
        : black;
  }
}
