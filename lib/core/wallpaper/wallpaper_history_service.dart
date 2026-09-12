// lib/core/wallpaper/wallpaper_history_service.dart
// 编号：S-40 空间图片历史（草稿箱）
//
// 职责：把「导入过的图片 + 它的成片」落到应用缓存目录，并提供
//       列表 / 导出 / 删除 / 自动清理。
//
// ★ 为什么需要它（用户反馈："导入的图片后缓存会一直在"）
//   之前每次导入只是在内存里换一张 ui.Image：既没有留下可回看的记录，
//   也没有任何清理入口 —— 缓存只增不减，用户无从处置。
//
// 存储布局（**复用 S-13 的 `Directory.systemTemp`**，Android 上就是应用缓存
//   目录；不引入 path_provider 等任何新平台依赖，鸿蒙镜像同样可用）：
//     <cache>/wallpaper_history/<id>.src    源图（导入时的原始字节）
//     <cache>/wallpaper_history/<id>.png    成片（点「保存到相册」时写入，兼作缩略图）
//     <cache>/wallpaper_history/index.json  条目索引
//
// 功耗要点（§11.2）：只在导入 / 保存 / 打开历史时各读写一次，运行期零 IO。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 一条历史记录。
class WallpaperHistoryEntry {
  const WallpaperHistoryEntry({
    required this.id,
    required this.name,
    required this.savedAt,
    required this.srcPath,
    this.shotPath,
  });

  /// 稳定 ID（= 落盘文件名前缀），同时用作删除/更新的键。
  final String id;

  /// 导入时的原始文件名（仅用于展示）。
  final String name;

  final DateTime savedAt;

  /// 源图落盘路径。
  final String srcPath;

  /// 成片路径；用户还没点过「保存到相册」时为 null（此时缩略图退回源图）。
  final String? shotPath;

  /// 该条目占用的磁盘字节数（源图 + 成片）。
  int get sizeBytes {
    int n = 0;
    for (final String p in <String>[srcPath, ?shotPath]) {
      final File f = File(p);
      if (f.existsSync()) n += f.lengthSync();
    }
    return n;
  }

  /// 缩略图用哪张：优先成片，没有就退回源图。
  String get previewPath => shotPath ?? srcPath;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'savedAt': savedAt.millisecondsSinceEpoch,
        'srcPath': srcPath,
        if (shotPath != null) 'shotPath': shotPath,
      };

  static WallpaperHistoryEntry? fromJson(Object? o) {
    if (o is! Map) return null;
    final Object? id = o['id'];
    final Object? src = o['srcPath'];
    if (id is! String || src is! String) return null;
    final Object? ts = o['savedAt'];
    final Object? shot = o['shotPath'];
    return WallpaperHistoryEntry(
      id: id,
      name: o['name'] is String ? o['name'] as String : '未命名',
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        ts is int ? ts : 0,
      ),
      srcPath: src,
      shotPath: shot is String && shot.isNotEmpty ? shot : null,
    );
  }
}

/// S-40：历史记录服务（单例）。
class WallpaperHistoryService {
  WallpaperHistoryService._();
  static final WallpaperHistoryService instance = WallpaperHistoryService._();

  /// 最多保留的条目数 —— 超出后自动删最旧的（含其文件）。
  ///
  /// ★ 这条是"缓存会一直在"的正解：即使你想不起来清理，它也不会无限涨。
  ///   按每条源图约 2 MB 估，20 条上限 ≈ 40 MB。
  static const int maxEntries = 20;

  Directory? _dir;

  Directory get _root {
    final Directory? c = _dir;
    if (c != null) return c;
    final Directory d = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}wallpaper_history',
    );
    if (!d.existsSync()) d.createSync(recursive: true);
    _dir = d;
    return d;
  }

  File get _indexFile =>
      File('${_root.path}${Platform.pathSeparator}index.json');

  String _pathOf(String id, String ext) =>
      '${_root.path}${Platform.pathSeparator}$id$ext';

  /// 读索引（时间倒序）。坏文件一律当空 —— 历史记录不值得阻断页面。
  Future<List<WallpaperHistoryEntry>> list() async {
    try {
      final File f = _indexFile;
      if (!f.existsSync()) return <WallpaperHistoryEntry>[];
      final Object? raw = jsonDecode(await f.readAsString());
      if (raw is! List) return <WallpaperHistoryEntry>[];
      final List<WallpaperHistoryEntry> out = <WallpaperHistoryEntry>[];
      for (final Object? o in raw) {
        final WallpaperHistoryEntry? e = WallpaperHistoryEntry.fromJson(o);
        // 顺带剔除源图已被外部清掉的僵尸条目
        if (e != null && File(e.srcPath).existsSync()) out.add(e);
      }
      out.sort((WallpaperHistoryEntry a, WallpaperHistoryEntry b) =>
          b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (e) {
      debugPrint('🔴 S-40 读历史失败: $e');
      return <WallpaperHistoryEntry>[];
    }
  }

  /// 读文件字节（缩略图 / 导出用）。UI 层不必 import dart:io。
  static Future<Uint8List?> readFile(String path) async {
    try {
      final File f = File(path);
      if (!f.existsSync()) return null;
      return await f.readAsBytes();
    } catch (e) {
      debugPrint('🔴 S-40 读文件失败 $path: $e');
      return null;
    }
  }

  Future<void> _writeIndex(List<WallpaperHistoryEntry> entries) async {
    await _indexFile.writeAsString(
      jsonEncode(entries.map((WallpaperHistoryEntry e) => e.toJson()).toList()),
      flush: true,
    );
  }

  /// 新增一条（导入图片时调用）。返回新条目；失败返回 null（不阻断导入）。
  Future<WallpaperHistoryEntry?> add({
    required Uint8List source,
    required String name,
  }) async {
    try {
      final DateTime now = DateTime.now();
      final String id = 'w${now.millisecondsSinceEpoch}';
      final String srcPath = _pathOf(id, '.src');
      await File(srcPath).writeAsBytes(source, flush: true);

      final WallpaperHistoryEntry entry = WallpaperHistoryEntry(
        id: id,
        name: name,
        savedAt: now,
        srcPath: srcPath,
      );
      final List<WallpaperHistoryEntry> all = await list();
      final List<WallpaperHistoryEntry> next =
          <WallpaperHistoryEntry>[entry, ...all];

      // 超限 → 把最旧的连同文件一起删掉
      while (next.length > maxEntries) {
        final WallpaperHistoryEntry drop = next.removeLast();
        _deleteFiles(drop);
      }
      await _writeIndex(next);
      return entry;
    } catch (e) {
      debugPrint('🔴 S-40 写历史失败: $e');
      return null;
    }
  }

  /// 写入/更新某条的成片（点「保存到相册」时调用，兼作缩略图）。
  Future<void> updateShot(String id, Uint8List png) async {
    try {
      final String shotPath = _pathOf(id, '.png');
      await File(shotPath).writeAsBytes(png, flush: true);
      final List<WallpaperHistoryEntry> all = await list();
      await _writeIndex(<WallpaperHistoryEntry>[
        for (final WallpaperHistoryEntry e in all)
          if (e.id == id)
            WallpaperHistoryEntry(
              id: e.id,
              name: e.name,
              savedAt: e.savedAt,
              srcPath: e.srcPath,
              shotPath: shotPath,
            )
          else
            e,
      ]);
    } catch (e) {
      debugPrint('🔴 S-40 更新成片失败: $e');
    }
  }

  /// 删除一条（含两个文件）。
  Future<void> delete(String id) async {
    try {
      final List<WallpaperHistoryEntry> all = await list();
      for (final WallpaperHistoryEntry e in all) {
        if (e.id == id) _deleteFiles(e);
      }
      await _writeIndex(
        all.where((WallpaperHistoryEntry e) => e.id != id).toList(),
      );
    } catch (e) {
      debugPrint('🔴 S-40 删除失败: $e');
    }
  }

  /// 清空全部。
  Future<void> clear() async {
    try {
      for (final WallpaperHistoryEntry e in await list()) {
        _deleteFiles(e);
      }
      await _writeIndex(<WallpaperHistoryEntry>[]);
    } catch (e) {
      debugPrint('🔴 S-40 清空失败: $e');
    }
  }

  void _deleteFiles(WallpaperHistoryEntry e) {
    for (final String p in <String>[
      e.srcPath,
      if (e.shotPath != null) e.shotPath!,
    ]) {
      try {
        final File f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // 单个文件删不掉不影响索引清理
      }
    }
  }
}
