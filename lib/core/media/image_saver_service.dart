// lib/core/media/image_saver_service.dart
// 编号：C-41 配套 · 图片长按保存服务（v1.40.0 新增）
// 说明：工具结果图(body 字节 / field URL)长按保存 ——
//   - Android: MethodChannel「xiangjugong/media」→ MediaStore 相册
//     Pictures/Toki(Android 10+ 免存储权限,minSdk 30 恒可用);
//   - Web: file_picker saveFile(bytes) → 浏览器直接下载;
//   - 其它桌面: file_picker saveFile 弹系统保存框。
//   防重入:全局 in-flight 标记,保存进行中再次触发返回 null(忽略)。
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart'
    show MethodChannel, PlatformException;
import 'package:http/http.dart' as http;

/// 图片保存服务（无状态单例语义：全静态方法 + 全局防重入）。
abstract final class ImageSaverService {
  static const MethodChannel _channel = MethodChannel('xiangjugong/media');

  static bool _busy = false;

  /// 保存图片。成功返回落盘说明(Android 相册路径 / 其它平台文件名)；
  /// [url] 非空时先下载(20s 超时)；[bytes]/[url] 至少一个。
  /// 返回 null = 保存中(已忽略)或无可保存数据。
  static Future<String?> saveImage({
    Uint8List? bytes,
    String? url,
    required String baseName,
  }) async {
    if (_busy || (bytes == null && (url == null || url.isEmpty))) return null;
    _busy = true;
    try {
      Uint8List data;
      if (bytes != null) {
        data = bytes;
      } else {
        final http.Response resp = await http
            .get(Uri.parse(url!))
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          return '下载失败(${resp.statusCode})';
        }
        data = resp.bodyBytes;
      }
      final String fileName = '$baseName.${_detectExt(data, url)}';
      if (kIsWeb) {
        // 浏览器:触发下载(自动存入下载目录/询问保存位置)。
        await FilePicker.saveFile(fileName: fileName, bytes: data);
        return fileName;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final Object? path = await _channel.invokeMethod<Object?>(
            'saveImage',
            <String, Object?>{
              'bytes': data,
              'fileName': fileName,
            },
          );
          return path is String ? path : fileName;
        } on PlatformException catch (e) {
          return e.message ?? '保存失败';
        }
      }
      // 桌面等:系统保存对话框。
      await FilePicker.saveFile(fileName: fileName, bytes: data);
      return fileName;
    } catch (_) {
      return '保存失败';
    } finally {
      _busy = false;
    }
  }

  /// 扩展名推断：图片魔数优先，URL 后缀兜底，最后 png。
  static String _detectExt(Uint8List b, String? url) {
    if (b.length >= 12) {
      if (b[0] == 0x89 &&
          b[1] == 0x50 &&
          b[2] == 0x4E &&
          b[3] == 0x47) {
        return 'png';
      }
      if (b[0] == 0xFF && b[1] == 0xD8) {
        return 'jpg';
      }
      if (b[0] == 0x47 &&
          b[1] == 0x49 &&
          b[2] == 0x46 &&
          b[3] == 0x46) {
        return 'gif';
      }
      if (b[0] == 0x42 && b[1] == 0x4D) {
        return 'bmp';
      }
      if (b[0] == 0x52 &&
          b[1] == 0x49 &&
          b[2] == 0x46 &&
          b[3] == 0x46 &&
          b[8] == 0x57 &&
          b[9] == 0x45 &&
          b[10] == 0x42 &&
          b[11] == 0x50) {
        return 'webp';
      }
    }
    final String? u = url;
    if (u != null) {
      final RegExpMatch? m = RegExp(
        r'\.(png|jpe?g|gif|webp|bmp)(?:$|[?#])',
        caseSensitive: false,
      ).firstMatch(u);
      if (m != null) {
        final String ext = m.group(1)!.toLowerCase();
        return ext == 'jpeg' ? 'jpg' : ext;
      }
    }
    return 'png';
  }
}
