// === 文件: lib/presentation/widgets/kernel/glow_tokens.dart ===
// 编号:LIVEVIEW-02 / GLOW-01 光感材质 token(2026-09-09 一期)
// 说明:HDS 沉浸光感的三档参数 + 三色光池。数值取自官方参考实现
//   (见 RESEARCH_immersive_glow_hds.md §2.1 等级 × 6 参数表)。
//
// 性能约定(不可违背):
//   - blurSigma 仅作文档参考 —— 真实模糊一律走 BackdropBlur(P0 缓存)+ U-03 钳制(≤20);
//   - 本 token 只驱动**纯 Canvas 绘制**(无 blur pass、无 shader、无 Ticker);
//   - 档位默认 adaptive(=gentle;系统「减弱动画」→ smooth)。
import 'package:flutter/painting.dart' show Color;

/// 光感档位(对齐 HDS smooth / gentle / exquisite)。
enum GlowLevel { smooth, gentle, exquisite }

/// 光感材质参数。
class GlowTokens {
  const GlowTokens({
    required this.level,
    required this.blurSigma,
    required this.fillOpacity,
    required this.glowOpacity,
    required this.shadowOpacity,
    required this.specularOpacity,
    required this.scatterOpacity,
  });

  final GlowLevel level;

  /// 文档值(HDS σ:8/22/34)。**不用于实际模糊** —— 模糊统一走 U-03 钳制。
  final double blurSigma;

  /// 白底填充强度。
  final double fillOpacity;

  /// 三色光池强度。
  final double glowOpacity;

  /// 边缘暗部强度。
  final double shadowOpacity;

  /// 扫光 / 高光强度。
  final double specularOpacity;

  /// 散射强度(二期启用,一期不消费)。
  final double scatterOpacity;

  // ── 三档(官方参考实现数值,一字未改)────────────────────────
  static const GlowTokens smooth = GlowTokens(
    level: GlowLevel.smooth,
    blurSigma: 8,
    fillOpacity: 0.58,
    glowOpacity: 0.05,
    shadowOpacity: 0.08,
    specularOpacity: 0.12,
    scatterOpacity: 0.08,
  );

  static const GlowTokens gentle = GlowTokens(
    level: GlowLevel.gentle,
    blurSigma: 22,
    fillOpacity: 0.30,
    glowOpacity: 0.28,
    shadowOpacity: 0.16,
    specularOpacity: 0.38,
    scatterOpacity: 0.90,
  );

  static const GlowTokens exquisite = GlowTokens(
    level: GlowLevel.exquisite,
    blurSigma: 34,
    fillOpacity: 0.13,
    glowOpacity: 0.34,
    shadowOpacity: 0.24,
    specularOpacity: 0.48,
    scatterOpacity: 0.48,
  );

  /// 三色光池:青绿 / 靛紫 / 琥珀(官方默认调色板)。
  static const List<Color> glowColors = <Color>[
    Color(0xFF72E3C0),
    Color(0xFF7C8DF7),
    Color(0xFFFFC178),
  ];

  static GlowTokens of(GlowLevel level) => switch (level) {
    GlowLevel.smooth => smooth,
    GlowLevel.gentle => gentle,
    GlowLevel.exquisite => exquisite,
  };

  /// 档位强度乘数 —— 官方三档的光池参数差距(0.05/0.28/0.34)在实机上
  /// 「标准 ↔ 丰富」几乎看不出区别,故按档位再拉开一次,保证可感知;
  /// 但过高会在边缘结成明显色斑(实测 2.2 偏强)→ 收敛到 1.7。
  double get alphaMultiplier => switch (level) {
    GlowLevel.smooth => 0.5,
    GlowLevel.gentle => 1.0,
    GlowLevel.exquisite => 1.7,
  };

  /// 能力门禁(官方 adaptive):系统「减弱动画」→ smooth,否则 gentle。
  ///
  /// 与 HDS 一致:设备是否支持 IMMERSIVE 材质由原生侧探测,本项目当前
  /// 一律按 gentle 起步(OpenHarmony/HarmonyOS 均无系统级材质可用)。
  static GlowLevel adaptive({required bool reduceMotion}) =>
      reduceMotion ? GlowLevel.smooth : GlowLevel.gentle;
}
