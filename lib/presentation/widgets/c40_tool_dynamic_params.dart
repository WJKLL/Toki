// === 文件: lib/presentation/widgets/c40_tool_dynamic_params.dart ===
// 编号：C-40 动态参数输入（v1.35.0 新增,P-09 通用页输入区）
// 说明：按 ToolConfig.params 配置驱动生成输入控件（新增工具不改代码）:
//   - text/number → MiuixTextField（悬浮标签,与 P-08 steam.input 同风格）;
//   - select → 横向选择胶囊(MiuixPressable sink,选中主色高亮);
//   - toggle/file → 首批兜底为文本框（预留类型,当前目录工具未用）;
//   - 值变化即回调 [onChanged](Map<参数名, 值>),空值由 ToolApiService 过滤。
// 视觉:字段纵向排列,间距 12;由使用方(P-09)决定是否套 C03GroupCard。
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../domain/entities/tool_config.dart';

/// C-40 动态参数输入。
class C40ToolDynamicParams extends StatefulWidget {
  const C40ToolDynamicParams({
    super.key,
    required this.params,
    this.onChanged,
  });

  final List<ToolParam> params;
  final ValueChanged<Map<String, String>>? onChanged;

  @override
  State<C40ToolDynamicParams> createState() => _C40ToolDynamicParamsState();
}

class _C40ToolDynamicParamsState extends State<C40ToolDynamicParams> {
  /// text/number 参数的输入控制器（按参数名）。
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  /// select 当前选中值。
  final Map<String, String> _selected = <String, String>{};

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
      _ => _buildTextField(context, p),
    };
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
    final Color accent = selected ? colors.primary : colors.surfaceContainerHigh;
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
              ? Border.all(color: colors.primary, width: 1)
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
