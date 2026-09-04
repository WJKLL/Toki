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

import 'package:flutter/services.dart'
    show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // ── image（两态）──────────────────────────────────────────────

  Widget _buildImage(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // field 模式:URL 取自响应字段(如随机图封面/头像类接口未来用)。
    final bool fieldMode = tool.result.source == 'field';
    final Widget? child;
    if (fieldMode) {
      final Object? url = _map(result.json)?.containsKey(
            tool.result.imageField ?? '',
          ) == true
          ? _map(result.json)![tool.result.imageField!]
          : null;
      child = (url is String && url.isNotEmpty)
          ? Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _placeholder(context, '图片加载失败'),
            )
          : _placeholder(context, '无图片地址');
    } else if (result.bytes != null) {
      child = Image.memory(
        result.bytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(context, '图片解析失败'),
      );
    } else {
      child = _placeholder(context, '无图片数据');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 160, maxHeight: 420),
              child: Container(
                width: double.infinity,
                color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
                alignment: Alignment.center,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
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
    final Object? v = json[field];
    if (v == null) return null;
    return _displayString(v);
  }

  String _displayString(Object v) {
    if (v is String) return v;
    if (v is bool) return v ? '是' : '否';
    if (v is num) return v.toString();
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
      final Object? v = json?[f.key];
      if (v == null) continue; // 字段缺失跳过。
      rows.add(_kvRow(context, f.label, _displayString(v)));
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

  /// 可选头图（result.imageField 存在且响应含 URL 字段 → 圆头像）。
  Widget? _buildHeadImage(
    BuildContext context,
    Map<String, dynamic>? json,
  ) {
    final String? field = tool.result.imageField;
    if (field == null || field.isEmpty || json == null) return null;
    final Object? url = json[field];
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

  List<Object?>? _listItems(Map<String, dynamic>? json) {
    final String? path = tool.result.listPath;
    if (path == null || path.isEmpty || json == null) return null;
    final Object? v = json[path];
    return v is List<Object?> ? v : null;
  }

  Widget _listRow(BuildContext context, Object? raw) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final Map<String, dynamic>? item =
        raw is Map<String, dynamic> ? raw : null;
    final String title =
        item != null ? _displayString(item[tool.result.itemTitle] ?? '') : '';
    final String subtitle = item != null && tool.result.itemSubtitle != null
        ? _displayString(item[tool.result.itemSubtitle!] ?? '')
        : '';
    final Object? urlObj =
        item != null && tool.result.itemUrl != null
            ? item[tool.result.itemUrl!]
            : null;
    final String? url = urlObj is String && urlObj.isNotEmpty ? urlObj : null;
    final Object? coverObj = item?['cover'];
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
}
