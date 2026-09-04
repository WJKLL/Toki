// lib/core/utils/u03_blur_policy.dart
// 编号：U-03 毛玻璃策略工具（C-10 / §11.7 毛玻璃功耗控制）
// 规则：
//   1. 平台门槛：模糊（BackdropFilter / RenderEffect）仅 Android 13+（API 33）开启；
//      Android 11–12 与 Web 一律禁用，回退半透明纯色 + 细边框。
//   2. 区域限制（≤40% 视口）由调用方（C-10/C-12 使用点）保证。
//   3. 参数限制：sigma ≤ 20、禁用多层嵌套模糊（调用方保证）。
abstract final class U03BlurPolicy {
  /// Android 13+ 才允许真实模糊。
  static const int minAndroidSdkForBlur = 33;

  /// 最大模糊强度 sigma（dp），超出必须降级（§11.7.3）。
  static const double maxBlurSigma = 20;

  /// 模糊允许区域占视口面积上限（§11.7.2）。
  static const double maxAreaRatio = 0.40;

  /// 裁决：用户开关 × 平台能力 → 是否允许真实高斯模糊。
  static bool allowBlur({
    required bool userEnabled,
    required bool isWeb,
    required int? androidSdkInt,
  }) {
    if (!userEnabled) return false;
    if (isWeb) return false; // §11.7.1 Web 一律禁用
    if (androidSdkInt != null && androidSdkInt < minAndroidSdkForBlur) {
      return false; // Android <13 回退
    }
    return true;
  }

  /// 降级原因文案（设置页 C-05 / 开关 summary 置灰说明用）。
  static String reason({
    required bool userEnabled,
    required bool isWeb,
    required int? androidSdkInt,
  }) {
    if (allowBlur(
      userEnabled: userEnabled,
      isWeb: isWeb,
      androidSdkInt: androidSdkInt,
    )) {
      return '已启用';
    }
    if (!userEnabled) return '已关闭';
    if (isWeb) return 'Web 端不支持毛玻璃，已自动降级为半透明';
    return 'Android 13+ 支持毛玻璃，当前设备已自动降级';
  }

  /// 模糊强度钳制到 [maxBlurSigma]（§11.7.3）。
  static double clampSigma(double sigma) => sigma.clamp(0.0, maxBlurSigma);
}
