// === 文件: lib/presentation/widgets/c40_tool_dynamic_params.dart ===
// 编号：C-40 动态参数输入（v1.35.0 新增,P-09 通用页输入区）
// 说明：按 ToolConfig.params 配置驱动生成输入控件（新增工具不改代码）:
//   - text/number → MiuixTextField（悬浮标签,与 P-08 steam.input 同风格）;
//   - select → 横向选择胶囊(MiuixPressable sink,选中主色高亮);
//   - file(v1.41.0) → 「选择图片」按钮(file_picker 相册/文件,字节经
//     [onFilesChanged] 上报,提交走 multipart 上传);
//   - 值变化即回调 [onChanged](Map<参数名, 值>),空值由 ToolApiService 过滤。
// 视觉:字段纵向排列,间距 12;由使用方(P-09)决定是否套 C03GroupCard。
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/widgets/app_icons.dart';
import '../../domain/entities/tool_config.dart';

/// file 参数已选文件（字节 + 原始文件名）。
class PickedToolFile {
  const PickedToolFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// C-40 动态参数输入。
class C40ToolDynamicParams extends StatefulWidget {
  const C40ToolDynamicParams({
    super.key,
    required this.params,
    this.onChanged,
    this.onFilesChanged,
  });

  final List<ToolParam> params;
  final ValueChanged<Map<String, String>>? onChanged;

  /// file 参数选图后回调（参数名 → 文件；v1.41.0）。
  final ValueChanged<Map<String, PickedToolFile>>? onFilesChanged;

  @override
  State<C40ToolDynamicParams> createState() => _C40ToolDynamicParamsState();
}

class _C40ToolDynamicParamsState extends State<C40ToolDynamicParams> {
  /// text/number 参数的输入控制器（按参数名）。
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  /// select 当前选中值。
  final Map<String, String> _selected = <String, String>{};

  /// file 参数已选文件（按参数名；v1.41.0）。
  final Map<String, PickedToolFile> _files = <String, PickedToolFile>{};

  @override
  void initState() {
    super.initState();
    for (final ToolParam p in widget.params) {
      if (p.type == ToolParamType.text || p.type == ToolParamType.number) {
        // v1.38.1:defaultValue 不再预填进输入框(提交时为空才兜底,
        // 见 P-09)——避免「默认文本残留需手动删除」;默认值改由
        // label 尾缀提示(如「最小值 · 默认 1」)。
        _controllers[p.name] = TextEditingController();
      } else if (p.type == ToolParamType.select &&
          p.options.isNotEmpty &&
          p.defaultValue != null) {
        _selected[p.name] = p.defaultValue!;
      }
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 汇总当前全部参数值（空值由调用层过滤）并上报。
  void _emit() {
    final Map<String, String> values = <String, String>{};
    for (final ToolParam p in widget.params) {
      final TextEditingController? c = _controllers[p.name];
      if (c != null) {
        values[p.name] = c.text;
      } else {
        values[p.name] = _selected[p.name] ?? p.defaultValue ?? '';
      }
    }
    widget.onChanged?.call(values);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> fields = <Widget>[];
    for (int i = 0; i < widget.params.length; i++) {
      final ToolParam p = widget.params[i];
      fields.add(_buildField(context, p));
      if (i != widget.params.length - 1) fields.add(const SizedBox(height: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: fields,
    );
  }

  Widget _buildField(BuildContext context, ToolParam p) {
    return switch (p.type) {
      ToolParamType.select => _buildSelect(context, p),
      ToolParamType.file => _buildFileField(context, p),
      _ => _buildTextField(context, p),
    };
  }

  // ── file：选择图片（相册/文件，跨平台字节读取）──────────────

  Future<void> _pickImage(ToolParam p) async {
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.image,
    );
    if (file == null || !mounted) return; // 用户取消。
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return;
    }
    if (bytes.isEmpty) return;
    setState(() {
      _files[p.name] = PickedToolFile(bytes: bytes, name: file.name);
    });
    widget.onFilesChanged
        ?.call(Map<String, PickedToolFile>.unmodifiable(_files));
  }

  Widget _buildFileField(BuildContext context, ToolParam p) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final PickedToolFile? file = _files[p.name];
    final String? preview = file?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: MiuixText(
            p.label,
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
        if (file == null)
          MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.95,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => _pickImage(p),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outline.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: <Widget>[
                  MiuixIcon(
                    vector: appIcon('image'),
                    size: 22,
                    tint: colors.primary,
                  ),
                  const SizedBox(height: 6),
                  MiuixText(
                    '选择图片',
                    fontSize: 13,
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ],
              ),
            ),
          )
        else
          MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.97,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => _pickImage(p),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      file.bytes,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Container(
                        width: 40,
                        height: 40,
                        color: colors.surfaceContainerHigh,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MiuixText(
                      preview ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      fontSize: 12,
                      color: colors.onSurface,
                    ),
                  ),
                  MiuixText(
                    '更换',
                    fontSize: 12,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTextField(BuildContext context, ToolParam p) {
    // v1.39.0:弃用 useLabelAsPlaceholder —— flutter_miuix 1.1.1 该模式下
    //   text 从空变非空时不触发重建(label 残留灰字遮挡输入,真机反馈)。
    //   改用标准浮动 label:空态灰字提示,输入后 label 上浮小字不遮挡。
    return MiuixTextField(
      key: ValueKey<String>('toolParam.${p.name}'),
      controller: _controllers[p.name],
      label: p.label,
      singleLine: true,
      textInputAction: TextInputAction.done,
      onChanged: (_) => _emit(),
    );
  }

  Widget _buildSelect(BuildContext context, ToolParam p) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final String? current = _selected[p.name] ?? p.defaultValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: MiuixText(
            p.label,
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String option in p.options)
              _buildChip(context, p, option, option == current),
          ],
        ),
      ],
    );
  }

  Widget _buildChip(
    BuildContext context,
    ToolParam p,
    String option,
    bool selected,
  ) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // v1.42.0:修复选中态同色遮挡 —— 主色底 + 主色文字不可读;
    //   改浅主色底(alpha 0.14) + 主色文字 + 主色细边(与课表 _optionChip 同语言)。
    final Color accent = selected
        ? colors.primary.withValues(alpha: 0.14)
        : colors.surfaceContainerHigh;
    final Color textColor = selected
        ? colors.primary
        : colors.onSurfaceVariantSummary;
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.94,
      borderRadius: BorderRadius.circular(999),
      onPressed: () {
        setState(() {
          _selected[p.name] = option;
        });
        _emit();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? Border.all(color: colors.primary, width: 1.2)
              : null,
        ),
        child: MiuixText(
          option,
          fontSize: 12,
          color: textColor,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
