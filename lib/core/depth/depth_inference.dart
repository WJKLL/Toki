// lib/core/depth/depth_inference.dart
// 编号：S-31 深度推理服务（平台无关契约）
//
// ★ 为什么要有这一层抽象：
//   Flutter 侧的 ONNX Runtime 包（flutter_onnxruntime）**不支持 OpenHarmony**
//   （实测其 pubspec 的平台声明只有 android/ios/macos/windows/linux/web）。
//   鸿蒙侧的可行路径是 `@ohos/onnxruntime`（ORT 1.23.2 预编译 arm64 .so）
//   + 自写 MethodChannel 插件，详见 PLAN_wallpaper_v1.52.md §9-A2。
//
//   因此本文件【零第三方依赖】，只定义契约与注册点：
//     - 支持 ONNX Runtime 的平台 → 注册 OnnxDepthInference（见 onnx_depth_inference.dart）
//     - 鸿蒙（暂）→ 不注册 → isAvailable() 为 false → 页面降级到预设景深模板
//   这与项目既有的 PlatFileOpsRegistry（SYNC_RULES §1.2 的注册制）是同一模式。
//
// 鸿蒙同步注意：`onnx_depth_inference.dart` 依赖 flutter_onnxruntime，
//   镜像的 pubspec 不应包含该依赖，故该文件属「主项目独有」，同步时需排除。
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 深度图结果。
///
/// 约定（与 shaders/spatial_parallax.frag 一致）：值域 0..1，**0 = 最远，1 = 最近**。
/// 模型原始输出是米制绝对深度，由推理实现负责归一化。
class DepthResult {
  const DepthResult({
    required this.width,
    required this.height,
    required this.data,
    this.minMeters = 0,
    this.maxMeters = 0,
  });

  final int width;
  final int height;

  /// 长度 = width × height，行优先。
  final Float32List data;

  /// 归一化时采用的原始深度范围（米）；仅用于诊断展示。
  final double minMeters;
  final double maxMeters;

  /// 转成灰度 [ui.Image]，供 shader 作为深度纹理采样。
  ///
  /// 8bit 精度足够：位移上限约 40px ÷ 256 级 ≈ 0.16 px/级，叠加纹理双线性采样
  /// 后无可见台阶（台阶检测数据见 PLAN_wallpaper_v1.52.md §6.6）。
  Future<ui.Image> toImage() {
    final Uint8List rgba = Uint8List(width * height * 4);
    for (int i = 0; i < data.length; i++) {
      final int g = (data[i] * 255.0).round().clamp(0, 255);
      final int p = i * 4;
      rgba[p] = g;
      rgba[p + 1] = g;
      rgba[p + 2] = g;
      rgba[p + 3] = 255;
    }
    final Completer<ui.Image> done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}

/// 深度推理契约。
abstract interface class DepthInference {
  /// 当前平台是否真的能跑（未注册实现 → false；包缺失/加载失败 → false）。
  Future<bool> isAvailable();

  /// 对一张图片字节流做深度估计。
  ///
  /// [inputSize] 为模型输入边长（本项目的 ONNX 已验证支持 384 / 512 / 640 / 768）。
  /// 失败或不可用时返回 null —— 调用方应降级到预设景深模板，而不是报错。
  Future<DepthResult?> infer(Uint8List imageBytes, {int inputSize = 640});
}

/// 注册表。
abstract final class DepthInferenceRegistry {
  static DepthInference? _impl;

  static void register(DepthInference impl) => _impl = impl;

  /// 未注册 → null（鸿蒙当前即为此状态）。
  static DepthInference? get instance => _impl;
}
