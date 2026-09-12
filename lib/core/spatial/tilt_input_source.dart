// lib/core/spatial/tilt_input_source.dart
// 编号：S-41 倾斜输入源（平台无关契约）
//
// ★ 为什么要有这一层抽象（与 S-31 深度推理同样的理由）
//   `sensors_plus` 是平台插件，**不支持 OpenHarmony**。鸿蒙侧要走
//   @ohos.sensor + MethodChannel 自写实现，再经 register() 注入。
//   因此本文件【零第三方依赖】，只定义契约与注册点 —— 与项目既有的
//   DepthInferenceRegistry / PlatFileOpsRegistry 是同一套注册制。
//
// 镜像同步注意：`sensors_plus_tilt_source.dart` 依赖 sensors_plus，
//   属「主项目独有」，镜像的 pubspec 不应含该依赖，同步时需排除。
//
// 三路输入统一成【归一化倾斜量】(-1..1)，调用方不关心背后是什么：
//   · 手机传感器（真机倾斜）—— 本契约的实现
//   · 摇杆（拖动）          —— Web/桌面/无障碍，以及不想动手机时
//   · 程序化轨迹            —— 导出与演示（仍在 P-24 页面内，不走本契约）
import 'dart:async';
import 'dart:ui' show Offset;

/// 倾斜输入契约。
///
/// 输出为归一化倾斜量：dx = 左右倾，dy = 前后倾，均在 -1..1。
/// 1 = 满幅（约 34°），调用方直接乘最大位移即可。
abstract interface class TiltInputSource {
  /// 该平台是否真的能给出倾斜数据（无传感器 / 权限拒绝 → false）。
  Future<bool> isAvailable();

  /// 倾斜流。**不保证以零开头**；调用方应自己处理"还没数据"的状态。
  Stream<Offset> get stream;

  /// 把【当前姿态】记为"零位"。
  ///
  /// ★ 必须要有：每个人握手机的姿势不同（有人几乎平放、有人竖着 30°），
  ///   不校准的话一进页面画面就是偏的，用户还得自己歪着手机去找正。
  void recalibrate();

  Future<void> dispose();
}

/// 注册表：未注册 → [instance] 为 null ⇒ 调用方降级到自动晃动。
abstract final class TiltInputSourceRegistry {
  static TiltInputSource? _impl;

  static void register(TiltInputSource impl) => _impl = impl;

  static TiltInputSource? get instance => _impl;
}
