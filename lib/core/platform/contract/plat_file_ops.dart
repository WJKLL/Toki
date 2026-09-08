// === 文件: lib/core/platform/contract/plat_file_ops.dart ===
// 编号：PLAT-01 平台文件操作抽象（双端同字，主项目为源；PLAN_OH_PLATFORM_v2 §0.1）
// 说明：把「选图 / 选 Excel / 保存文件 / 保存图片到相册」从公共 UI 代码中抽出：
//   - 未注册 → _Default（file_picker 现逻辑：Web 下载 / Android 通道 / 桌面保存框，
//     行为与迁移前逐字等价 —— 主项目零变化）；
//   - 镜像注册 OH 实现（file_ops_ohos.dart：PhotoViewPicker / DocumentViewPicker
//     原生选择器 + media 通道存相册）；
//   - 注册制而非平台枚举 switch：本文件**不引用 TargetPlatform.ohos**（标准 Flutter
//     无该枚举），平台差异全部收敛到 impl/。
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart'
    show MethodChannel, PlatformException;

/// 已选择文件（字节 + 原始文件名；取消 → null）。
class PlatPickedFile {
  const PlatPickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 平台文件操作。
abstract interface class PlatFileOps {
  /// 选择一张图片（相册/文件；取消 → null）。
  Future<PlatPickedFile?> pickImage();

  /// 选择 Excel 课表（.xls/.xlsx；取消 → null）。
  Future<PlatPickedFile?> pickExcel();

  /// 保存任意字节到用户选择的位置（桌面保存框/浏览器下载/OH 文档选择器）。
  /// 返回描述文案；用户取消 → null。
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
  });

  /// 保存图片到系统相册（Android/OH 相册；Web/桌面走 saveFile 语义）。
  Future<String?> saveImageToGallery({
    required Uint8List bytes,
    required String fileName,
  });
}

/// 注册表：未注册 → [instance] 返回 Default（主项目行为零变）。
abstract final class PlatFileOpsRegistry {
  static PlatFileOps? _ops;

  /// 注册平台实现（镜像 main() 启动时注册 OH 实现）。
  static void register(PlatFileOps ops) => _ops = ops;

  static PlatFileOps get instance => _ops ?? _DefaultPlatFileOps();
}

/// 默认实现 = file_picker 现逻辑（v1.40/v1.41 迁移，逐字等价）。
class _DefaultPlatFileOps implements PlatFileOps {
  static const MethodChannel _media = MethodChannel('xiangjugong/media');

  @override
  Future<PlatPickedFile?> pickImage() async {
    final PlatformFile? f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return null;
    final Uint8List bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;
    return PlatPickedFile(name: f.name, bytes: bytes);
  }

  @override
  Future<PlatPickedFile?> pickExcel() async {
    final PlatformFile? f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['xls', 'xlsx'],
    );
    if (f == null) return null;
    final Uint8List bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;
    return PlatPickedFile(name: f.name, bytes: bytes);
  }

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    return fileName;
  }

  @override
  Future<String?> saveImageToGallery({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb) {
      // 浏览器：触发下载（自动存入下载目录/询问保存位置）。
      await FilePicker.saveFile(fileName: fileName, bytes: bytes);
      return fileName;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android：MethodChannel「xiangjugong/media」→ MediaStore 相册 Pictures/Toki。
      try {
        final Object? path = await _media.invokeMethod<Object?>(
          'saveImage',
          <String, Object?>{
            'bytes': bytes,
            'fileName': fileName,
          },
        );
        return path is String ? path : fileName;
      } on PlatformException catch (e) {
        return e.message ?? '保存失败';
      }
    }
    // 桌面等：系统保存对话框。
    await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    return fileName;
  }
}
