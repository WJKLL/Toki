// === 文件: lib/presentation/widgets/c41_tool_result_display.dart ===
// 编号：C-41 通用结果展示（v1.35.0 新增,P-09 结果区）
// 说明：按 ToolConfig.displayType + result 字段映射渲染响应（不解析统一
//   code —— UAPI 成功响应为直接业务 JSON）:
//   - image:   source='body' → Image.memory(字节);='field' → Image.network(字段 URL);
//   - text:    取 result.field 文本(密文/JSON 多行),点击复制(MiniToast);
//   - keyValue: result.fields 逐行(label+value,可复制);imageField 存在 →
//              顶部圆头像(如 B站 face);bool → 是/否;
//   - list:    result.listPath 取数组,逐项 title/subtitle/可选 url(外开)/
//              可选 cover 缩略图(Image.network);
//   - json:    响应整体美化文本(兜底,当前目录以 text 为主);
//   - 字段缺失防御跳过;组件只读渲染,刷新/重试在 P-09。
import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/media/image_saver_service.dart';
import '../../core/tools/tool_api_service.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/c03_group_card.dart';
import '../../core/widgets/mini_toast.dart';
import '../../domain/entities/tool_config.dart';

/// C-41 通用结果展示。
class C41ToolResultDisplay extends StatelessWidget {
  const C41ToolResultDisplay({
    super.key,
    required this.tool,
    required this.result,
  });

  final ToolConfig tool;

  /// ToolApiService 返回（json/bytes/text 三态）。
  final ToolApiResult result;

  void _copy(BuildContext context, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    showMiniToast(context, '已复制');
  }

  @override
  Widget build(BuildContext context) {
    return switch (tool.displayType) {
      ResponseDisplayType.image => _buildImage(context),
      ResponseDisplayType.keyValue => _buildKeyValue(context),
      ResponseDisplayType.list => _buildList(context),
      ResponseDisplayType.json => _buildJson(context),
      ResponseDisplayType.custom || ResponseDisplayType.text =>
        _buildText(context),
    };
  }

  // ── image（两态；v1.40.0 长按保存到相册/下载）──────────────────

  Widget _buildImage(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // field 模式:字段值为图片地址 —— URL 直连 / data URI / 纯 base64
    // (v1.41.0:抠图/水印接口返回纯 base64 PNG,魔数校验后解码)。
    final bool fieldMode = tool.result.source == 'field';
    final Widget? child;
    Uint8List? saveBytes; // 字节(直接保存):body 或 fieldBase64 解码。
    String? saveUrl; // field URL(保存时先下载)。
    if (fieldMode) {
      final Object? raw = _at(result.json, tool.result.imageField ?? '');
      if (raw is String && raw.isNotEmpty) {
        final (Uint8List?, String?) payload = _imagePayload(raw);
        final Uint8List? decoded = payload.$1;
        final String? url = payload.$2;
        if (decoded != null) {
          saveBytes = decoded;
          child = Image.memory(
            decoded,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                _placeholder(context, '图片解析失败'),
          );
        } else if (url != null) {
          saveUrl = url;
          child = Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _placeholder(context, '图片加载失败'),
          );
        } else {
          child = _placeholder(context, '无图片地址');
        }
      } else {
        child = _placeholder(context, '无图片地址');
      }
    } else if (result.bytes != null) {
      saveBytes = result.bytes;
      child = Image.memory(
        result.bytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(context, '图片解析失败'),
      );
    } else {
      child = _placeholder(context, '无图片数据');
    }
    final bool savable = saveBytes != null || saveUrl != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: savable
                ? () => _saveImage(context, saveBytes, saveUrl)
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 160,
                  maxHeight: 420,
                ),
                child: Container(
                  width: double.infinity,
                  color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
                  alignment: Alignment.center,
                  child: child,
                ),
              ),
            ),
          ),
          if (savable) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                MiuixIcon(
                  vector: appIcon('download'),
                  size: 12,
                  tint: colors.onSurfaceVariantSummary,
                ),
                const SizedBox(width: 5),
                MiuixText(
                  '长按图片保存',
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 长按保存：body 字节直存 / field URL 先下载；结果轻提示。
  Future<void> _saveImage(
    BuildContext context,
    Uint8List? bytes,
    String? url,
  ) async {
    final String base =
        'toki_${tool.id}_${DateTime.now().millisecondsSinceEpoch}';
    final String? saved = await ImageSaverService.saveImage(
      bytes: bytes,
      url: url,
      baseName: base,
    );
    if (!context.mounted) return;
    if (saved == null) {
      showMiniToast(context, '正在保存…'); // 防重入(上一次进行中)。
      return;
    }
    if (saved.startsWith('保存失败') || saved.startsWith('下载失败')) {
      showMiniToast(context, saved);
      return;
    }
    showMiniToast(context, kIsWeb ? '已开始下载' : '已保存到相册');
  }

  Widget _placeholder(BuildContext context, String text) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: MiuixText(
        text,
        fontSize: 12,
        color: colors.onSurfaceVariantSummary,
      ),
    );
  }

  // ── text ──────────────────────────────────────────────────────

  String? _textValue(Map<String, dynamic>? json) {
    if (json == null) return null;
    final String? field = tool.result.field;
    if (field == null || field.isEmpty) return null;
    final Object? v = _at(json, field);
    if (v == null) return null;
    return _displayString(v);
  }

  /// 值 → 展示文本：字符串原样；bool 是/否；数字整值原样、小数保留 2 位
  /// （尾零去除，v1.38.0 起，避免延迟/评分等长小数撑爆行宽）；
  /// 其余（数组/对象）JSON 缩进。
  String _displayString(Object v) {
    if (v is String) return v;
    if (v is bool) return v ? '是' : '否';
    if (v is num) {
      final double d = v.toDouble();
      if (d == d.roundToDouble()) return d.toInt().toString();
      String s = d.toStringAsFixed(2);
      if (s.contains('.')) {
        s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
      return s;
    }
    return const JsonEncoder.withIndent('  ').convert(v);
  }

  Widget _buildText(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final String? value = _textValue(_map(result.json));
    if (value == null || value.isEmpty) {
      return _placeholder(context, '无返回文本');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _copy(context, value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  MiuixText(
                    value,
                    style: ts.body2.copyWith(
                      color: colors.onSurface,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      MiuixIcon(
                        vector: appIcon('copy'),
                        size: 13,
                        tint: colors.onSurfaceVariantSummary,
                      ),
                      const SizedBox(width: 4),
                      MiuixText(
                        '点击复制',
                        fontSize: 11,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── keyValue ──────────────────────────────────────────────────

  Widget _buildKeyValue(BuildContext context) {
    final Map<String, dynamic>? json = _map(result.json);
    final Widget? head = _buildHeadImage(context, json);
    final List<Widget> rows = <Widget>[];
    for (final ToolResultField f in tool.result.fields) {
      final Object? v = _at(json, f.key);
      if (v == null) continue; // 字段缺失跳过。
      rows.add(_kvRow(context, f.label, _kvDisplay(f, v)));
    }
    if (rows.isEmpty && head == null) {
      return _placeholder(context, '无返回数据');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          ?head,
          ...rows,
        ],
      ),
    );
  }

  /// 字段展示值：优先命中的 valueMap 映射，否则原值格式化。
  String _kvDisplay(ToolResultField f, Object v) {
    final Map<String, String>? m = f.map;
    if (m != null && m.isNotEmpty) {
      final String raw = v is String ? v : v.toString();
      final String? mapped = m[raw];
      if (mapped != null) return mapped;
    }
    return _displayString(v);
  }

  /// 可选头图（result.imageField 存在且响应含 URL 字段 → 圆头像）。
  Widget? _buildHeadImage(
    BuildContext context,
    Map<String, dynamic>? json,
  ) {
    final String? field = tool.result.imageField;
    if (field == null || field.isEmpty || json == null) return null;
    final Object? url = _at(json, field);
    if (url is! String || url.isEmpty) return null;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: <Widget>[
          ClipOval(
            child: Image.network(
              url,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 56,
                height: 56,
                color: colors.surfaceContainerHigh,
                child: MiuixIcon(
                  vector: appIcon('image'),
                  size: 26,
                  tint: colors.onSurfaceVariantSummary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(BuildContext context, String label, String value) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _copy(context, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 72,
              child: MiuixText(
                label,
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            Expanded(
              child: MiuixText(
                value,
                style: MiuixTheme.of(context).textStyles.body2.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 4),
            MiuixIcon(
              vector: appIcon('copy'),
              size: 15,
              tint: colors.onSurfaceVariantActions,
            ),
          ],
        ),
      ),
    );
  }

  // ── list ──────────────────────────────────────────────────────

  Widget _buildList(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final List<Object?>? items = _listItems(_map(result.json));
    if (items == null || items.isEmpty) {
      return _placeholder(context, '暂无结果');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...[
            if (i != 0)
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 16),
                color: colors.outline.withValues(alpha: 0.2),
              ),
            _listRow(context, items[i]),
          ],
        ],
      ),
    );
  }

  /// 列表取数组：listPath 支持点路径；标量数组（数字/字符串列表）直接取。
  List<Object?>? _listItems(Map<String, dynamic>? json) {
    final String? path = tool.result.listPath;
    if (path == null || path.isEmpty || json == null) return null;
    final Object? v = _at(json, path);
    return v is List<Object?> ? v : null;
  }

  Widget _listRow(BuildContext context, Object? raw) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Map<String, dynamic>? item =
        raw is Map<String, dynamic> ? raw : null;
    // 标量项（如随机数数组）：元素自身即标题；Map 项按配置字段取。
    final String title = item != null
        ? _itemField(item, tool.result.itemTitle)
        : _displayString(raw!);
    final String subtitle = item != null && tool.result.itemSubtitle != null
        ? _itemField(item, tool.result.itemSubtitle!)
        : '';
    final Object? urlObj = item != null && tool.result.itemUrl != null
        ? _at(item, tool.result.itemUrl!)
        : null;
    final String? url = urlObj is String && urlObj.isNotEmpty ? urlObj : null;
    final Object? coverObj = item != null
        ? _at(item, tool.result.coverField ?? 'cover')
        : null;
    final String? cover = coverObj is String && coverObj.isNotEmpty
        ? coverObj
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openItem(context, title, url),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: <Widget>[
            if (cover != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  cover,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 44,
                    height: 44,
                    color: colors.surfaceContainerHigh,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (title.isNotEmpty)
                    MiuixText(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MiuixTheme.of(context).textStyles.body2.copyWith(
                        color: colors.onSurfaceContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    MiuixText(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ],
                ],
              ),
            ),
            if (url != null) ...[
              const SizedBox(width: 4),
              MiuixIcon(
                vector: appIcon('chevronForward'),
                size: 16,
                tint: colors.onSurfaceVariantSummary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 从列表项 Map 取展示字段（点路径），缺失空串。
  String _itemField(Map<String, dynamic> item, String? field) {
    if (field == null || field.isEmpty) return '';
    final Object? v = _at(item, field);
    if (v == null) return '';
    return _displayString(v);
  }

  Future<void> _openItem(BuildContext context, String title, String? url) async {
    if (url != null) {
      final Uri? uri = Uri.tryParse(url);
      if (uri != null) {
        final bool ok =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) showMiniToast(context, '无法打开链接');
        return;
      }
    }
    if (title.isNotEmpty) _copy(context, title);
  }

  // ── json（兜底展示原始响应美化文本）────────────────────────

  Widget _buildJson(BuildContext context) {
    final Object? json = result.json;
    if (json == null) {
      return _placeholder(context, '无返回数据');
    }
    final String pretty =
        const JsonEncoder.withIndent('  ').convert(json);
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _copy(context, pretty),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MiuixText(
                pretty,
                style: MiuixTheme.of(context).textStyles.body2.copyWith(
                  color: colors.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _map(Object? json) =>
      json is Map<String, dynamic> ? json : null;

  /// 点路径取值（v1.38.0）：'a.b' / 'a.0.b'（数字段走 List 下标）；
  /// Map/List 混走，缺失或类型不符返回 null。
  Object? _at(Object? root, String path) {
    if (root == null || path.isEmpty) return null;
    Object? cur = root;
    for (final String seg in path.split('.')) {
      if (cur is Map) {
        cur = cur[seg];
      } else if (cur is List) {
        final int? i = int.tryParse(seg);
        if (i == null || i < 0 || i >= cur.length) return null;
        cur = cur[i];
      } else {
        return null;
      }
    }
    return cur;
  }

  /// field 图片值解析（v1.41.0）：(解码字节, URL)—— data:image URI 剥头解码；
  /// 纯 base64 需魔数校验（避免把 URL 误当 base64 解出垃圾）；否则按 URL。
  (Uint8List?, String?) _imagePayload(String raw) {
    String data = raw;
    if (data.startsWith('data:image/')) {
      final int comma = data.indexOf(',');
      if (comma > 0) data = data.substring(comma + 1);
      try {
        return (base64Decode(data), null);
      } on FormatException {
        return (null, raw);
      }
    }
    if (raw.length > 64) {
      try {
        final Uint8List decoded = base64Decode(raw);
        if (_looksImage(decoded)) return (decoded, null);
      } on FormatException {
        // 非 base64 → 按 URL 处理。
      }
    }
    return (null, raw);
  }

  /// 常见图片魔数（PNG/JPEG/GIF/WebP/BMP）。
  bool _looksImage(Uint8List b) {
    if (b.length < 12) return false;
    if (b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return true;
    }
    if (b[0] == 0xFF && b[1] == 0xD8) {
      return true;
    }
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return true;
    }
    if (b[0] == 0x42 && b[1] == 0x4D) {
      return true;
    }
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return true;
    }
    return false;
  }
}
