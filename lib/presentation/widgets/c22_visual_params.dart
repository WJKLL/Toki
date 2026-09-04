// lib/presentation/widgets/c22_visual_params.dart
// 编号：C-22 内部件（T58 参数单一事实源，不占编号）
// 职责：C-22 底栏全部视觉/物理参数集中定义，与 KernelSU FloatingBottomBar.kt
//   视觉参数提取报告逐项一致；所有业务文件不得再出现魔法数字，
//   一律引用本类。dualPeak 真双峰着色器列为 v1.8.0 预留扩展点。
class C22VisualParams {
  C22VisualParams._();

  // ── 容器（报告 §2.1）──
  static const double containerHeight = 64.0; // 胶囊总高 64dp（4+56）
  static const double contentHeight = 56.0; // 内容区高 56dp
  static const double padding = 4.0; // 内边距 4dp
  static const double bottomSpacing = 12.0; // 底部外间距 12dp
  // v1.10.32：缩小底栏水平宽度 —— 左右留白 12→40dp（胶囊居中变窄，
  //   内部图标随 tab 宽度自适应缩放）。
  static const double sideInset = 40.0; // 左右留白 40dp（原 12dp）
  static const double contentClearance = 16.0; // 内容穿透底部安全间距
  static const double tabMinWidth = 76.0; // 标签最小宽（报告 §2.1 参考）
  // v1.10.32：内部图标自适应 —— 图标大小 = tabWidth × factor，钳制 [min, max]。
  static const double tabIconSizeFactor = 0.18; // 图标 = tabWidth × 0.18
  static const double tabIconSizeMin = 16.0; // 图标最小 16dp
  static const double tabIconSizeMax = 22.0; // 图标最大 22dp

  // ── 模糊（报告 §2.2 / Vibrancy.kt:13）──
  // v1.10.23：悬浮胶囊模糊 4dp→8dp；v1.10.24：8dp→12dp（sigma 5.4）。
  //   增强模糊 → 背景细节被抹平 → 低采样率不可察觉 → 允许进一步降采样省性能。
  //   U-03 上限 sigma≤20 仍满足（12dp → sigma 5.4）。
  // demo（Skia 低模糊）：12dp→10dp（sigma 4.5），降低毛玻璃开销与视觉糊感。
  static const double floatingBlurRadius = 10.0; // 悬浮胶囊模糊半径 10dp
  static const double normalBlurRadius = 25.0; // 普通模式蒙版模糊 25dp（预留）
  static const double vibrancySaturation =
      1.5; // 鲜艳度 saturation（Vibrancy.kt:13）
  static const double restBlurRadius = 2.0; // 指示器静止模糊 2dp（量化恒定）
  static const double pressBlurRadius = 12.0; // 指示器按压模糊 12dp（量化恒定）

  // ── 颜色（报告 §2.2/§2.4/§2.5）──
  static const double containerBlendAlpha = 0.4; // 容器混色 surfaceContainer@0.4
  static const double normalBlendAlpha = 0.87; // 普通模式蒙版混色（预留）
  static const double restTintAlpha = 0.15; // 指示器静止 tint：primary@0.15
  static const double dragTintAlpha = 0.1; // 拖动态基础 tint（0.1×(1-press)）
  static const double dragTintPressAlpha = 0.03; // 按压增量 tint（0.03×press）
  // v1.10.15（玻璃质感微调）：按压白色透明 + 外阴影
  static const double pressWhiteAlpha = 0.4; // 按压白色透明玻璃（浅色，白 @0.4）
  static const double pressShadowAlpha = 0.08; // 按压外阴影（更平柔，原 0.15）
  // v1.10.18：静止深灰透明分平台 —— 浅色 0.06（更浅），深色 0.12
  static const double lightStaticTintAlpha = 0.06;
  static const double darkStaticTintAlpha = 0.12;

  // ── 阴影（报告 §2.2）──
  static const double shadowRadius = 10.0; // 阴影模糊半径 10dp
  static const double shadowAlphaDark = 0.2; // 深色模式黑 @0.2
  static const double shadowAlphaLight = 0.1; // 浅色模式黑 @0.1
  // v1.14.4（按压跃起）：底栏整体上浮位移 + 阴影增强（符合物理直觉，非形变）。
  static const double barLiftOffset = 6.0; // 按压时底栏上浮位移（dp）
  static const double barLiftShadowRadius = 14.0; // 跃起阴影半径（原 10）

  // ── 高光（报告 §3 / T53 双光源 1:1 复刻）──
  static const double highlightWidth = 1.0; // 高光宽度
  static const double highlightAlpha = 0.75; // 底栏高光 alpha 0.75
  static const double glowColorAlpha = 0.12; // 指示器静止 faint 描边高光 alpha
  static const double innerBlurRadius = 2.0; // Bloom 内模糊半径
  static const double primaryLightIntensity = 1.0; // 主光源 intensity（T53）
  static const double secondaryLightIntensity = 0.4; // 副光源 intensity（T53）

  // ── 指示器（报告 §2.4/§2.5）──
  static const double indicatorHeight = 56.0; // 指示器高 56dp
  static const double indicatorCornerRadius = 28.0; // 全圆 56/2
  // v1.10.13（克制物理）：物理交互效果收敛为"直觉而不夸张"——
  //   按压缩放 1.39→1.12（轻微放大）；触边橡皮筋 4dp→0（撞墙仅 squash 形变，
  //   不弹跳）；squash 钳制 0.2→0.1；内阴影 8dp→5dp。
  static const double pressScale = 1.12; // 按压缩放 X（克制）
  // v1.10.32：按压高度形变增强 —— 1.05→1.10（高度变化更明显）。
  static const double pressScaleY = 1.10; // 高度按压缩放（增强）
  // v1.10.26：删除撞墙回弹（触边橡皮筋已移除）。
  // v1.10.27：速度指数平滑 + squash 幅度限制。
  // v1.10.28：进一步放慢形变 —— 平滑 0.15→0.08（方向反转渐变不生硬）、
  //   X 钳制 0.08→0.06、Y 0.06→0.04（撞边"变高"更轻微）、Y 系数 0.15→0.12、
  //   X 系数 0.6→0.5、拉伸上限 0.06→0.05。
  static const double velocitySmoothing = 0.08; // 速度指数平滑（每事件靠拢比例）
  static const double wallVelocitySmoothing = 0.5; // 撞墙速度快速归零（v1.10.30，消除回弹）
  static const double squashClampX = 0.06; // X squash 钳制（v1.10.28）
  static const double squashClampY = 0.04; // Y squash 钳制（v1.10.28，限高变化）
  static const double squashFactorX = 0.5; // X squash 速度系数（v1.10.28）
  static const double squashFactorY = 0.12; // Y squash 速度系数（v1.10.28）
  static const double dragStretchFactor = 0.04; // 拖拽拉伸速度系数
  static const double dragStretchMax = 0.05; // 拖拽拉伸上限（v1.10.28）
  static const double innerShadowRadius = 5.0; // 内阴影半径（克制，原 8dp）
  static const double innerShadowAlpha = 0.15; // 内阴影 Black @0.15

  // ── 透镜折射（v1.8.0，报告 §2.2 Lens.kt / FloatingBottomBar.kt:405-409）──
  // v1.10.6：折射带/折射量收敛 —— 14dp 对 56dp 指示器原始值过大，放大 1.39 后
  //   视觉夸张；收窄至 5dp 带 / 8dp 量，边缘轻微折射即可。
  static const double lensRefractionHeight = 5.0; // 折射带半宽（原 10）
  static const double lensRefractionAmount = 8.0; // 折射量（原 14）
  static const double lensChromaticAberration =
      0.5; // 0.5·press（FloatingBottomBar.kt:409）

  // ── 死区吸附（报告 §2.6 / T55）──
  static const double deadZoneThreshold = 0.025; // |pos-original| < 2.5% 行程
  static const double velocityThreshold = 200.0; // |v| < 200px/s
  static const double velocityCorrection = 0.3; // 速度修正 ±0.3 tab

  // ── 动画（报告 §2.5 / T56）──
  // v1.10.27：位置弹簧 0.85→1.0（临界阻尼）—— 甩出吸附无 overshoot、
  //   撞边不再大幅回弹；松手初速上限 100→8 tab/s（甩出惯性收敛）。
  static const double positionDamping = 1.0; // 位置弹簧（临界阻尼，无回弹）
  static const double positionStiffness = 1000.0;
  static const double settleVelocityMax = 8.0; // 松手吸附初速上限（tab/s，原 100）
  static const double decayDamping = 0.5;
  static const double decayStiffness = 300.0;
  static const double pressDamping = 1.0;
  static const double pressStiffness = 1000.0;
  static const double scaleXDamping = 0.85; // 形变阻尼加大（收敛快，无 overshoot）
  static const double scaleXStiffness = 250.0;
  static const double scaleYDamping = 0.9; // 形变阻尼加大
  static const double scaleYStiffness = 250.0;
  // v1.10.33：切页释放过渡拉长 —— 按压态→静态的收敛用更慢的 release 专用
  //   弹簧（press 1000→500、scale 250→150），整体过渡约 300→360ms。
  static const double releasePressStiffness = 500.0; // release press 收敛
  static const double releaseScaleStiffness = 150.0; // release scale 收敛

  // ── 页切换（T59 参考公式：100 × distance + 100 ms）──
  static const int pageSwitchBaseMs = 100;
  static const int pageSwitchPerDistanceMs = 100;
}
