// lib/presentation/features/home/p05_activity_editor.dart
// 编号：P-05 每日活动时间编辑窗（v1.19.0 新增，v1.19.2 重构）
// 说明：deferred 懒加载库 —— 首页卡片首次点击才 loadLibrary()。
//   v1.19.2 按用户反馈重构：
//   - 一次编辑一天（顶部 7 天 MiuixTabRow 选择，见 #a10 单天视图）；
//   - 时间输入用文本框 + 自动冒号（只允许数字 0-23:0-59，无滑动选择器）
//     → 解决横屏滑动冲突 / 竖屏按钮靠下 / 时间范围受限；
//   - miuix 立体感：各配置卡加轻阴影（低性能开销，仅静态 BoxShadow）。
//   - 竖屏 BottomSheet / 横屏或宽屏 Dialog（自适应）。
import 'dart:async';

import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/daily_activity.dart';
import '../../providers/daily_activity_provider.dart';
import '../../widgets/cards/card_shell.dart';

/// 编辑窗容器（show 驱动显隐，关闭见 onDismissRequest/onDismissFinished）。
class ActivityEditor extends ConsumerStatefulWidget {
  const ActivityEditor({
    super.key,
    required this.show,
    this.onDismissRequest,
    this.onDismissFinished,
  });

  final bool show;
  final VoidCallback? onDismissRequest;
  final VoidCallback? onDismissFinished;

  @override
  ConsumerState<ActivityEditor> createState() => _ActivityEditorState();
}

class _ActivityEditorState extends ConsumerState<ActivityEditor> {
  List<DailyActivityTime> _draft = const <DailyActivityTime>[];
  bool _saving = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _syncDraft() {
    final DailyBalanceData? data = ref.read(dailyActivityProvider).value;
    _draft = <DailyActivityTime>[
      for (int w = 1; w <= 7; w++)
        (data?.of(w) ?? DailyActivityTime.defaults(w)),
    ];
  }

  Future<void> _resetDefaults() async {
    await ref.read(dailyActivityProvider.notifier).resetDefaults();
    _syncDraft();
    if (mounted) setState(() {});
  }

  void _update(int weekday, DailyActivityTime next) {
    setState(() {
      _draft = <DailyActivityTime>[
        for (final DailyActivityTime a in _draft)
          a.weekday == weekday ? next : a,
      ];
    });
  }

  Future<void> _onSave(VoidCallback onDone) async {
    if (_saving) return;
    _saving = true;
    try {
      // 整表单次写入(不再逐条 updateDay → 消除"保存延迟/没反应")。
      await ref.read(dailyActivityProvider.notifier).saveAll(_draft);
      if (mounted) onDone();
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draft.isEmpty) _syncDraft();
    // 统一用 MiuixOverlayDialog（v1.19.3）：竖屏/横屏同款从底部弹出悬浮，
    //   宽度/高度由 Miuix 自适应（大屏居中、小屏拉伸）。此前竖屏走
    //   OverlayBottomSheet 与横屏 Dialog 观感不一致。
    final Widget form = _DayEditorForm(
      draft: _draft,
      onUpdate: _update,
      onReset: _resetDefaults,
      onSave: (VoidCallback done) => _onSave(done),
    );
    // MiuixOverlayBottomSheet（v1.19.6）：从底部滑出、内容全程在屏幕内。
    //   defaultWindowInsetsPadding:false → 键盘抬升交给表单内 AnimatedPadding,
    //   避免 Miuix 内容底部 padding 与整卡抬升双重叠加。
    return MiuixOverlayBottomSheet(
      show: widget.show,
      title: '每日活动时间',
      onDismissRequest: widget.onDismissRequest,
      onDismissFinished: widget.onDismissFinished,
      content: form,
      defaultWindowInsetsPadding: false,
    );
  }
}

/// 单天编辑表单：7 天 TabRow + 当天起止时间文本输入 + 操作按钮。
class _DayEditorForm extends StatefulWidget {
  const _DayEditorForm({
    required this.draft,
    required this.onUpdate,
    required this.onReset,
    required this.onSave,
  });

  final List<DailyActivityTime> draft;
  final void Function(int weekday, DailyActivityTime next) onUpdate;
  final Future<void> Function() onReset;
  final void Function(VoidCallback done) onSave;

  @override
  State<_DayEditorForm> createState() => _DayEditorFormState();
}

class _DayEditorFormState extends State<_DayEditorForm> {
  /// 当前编辑的天（默认今天）。
  late int _selected = DateTime.now().weekday;

  DailyActivityTime get _cur => widget.draft[_selected - 1];

  void _onChanged(DailyActivityTime next) {
    widget.onUpdate(_selected, next);
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final VoidCallback? dismiss = MiuixDismissScope.maybeOf(context);
    final DailyActivityTime cur = _cur;
    // v1.19.6：整页内容整体避让键盘 —— 键盘弹出时整卡上移抬离键盘,
    //   内容区保留滚动(可用高 = 屏高−键盘高),保存按钮始终可点。
    final double ime = MediaQuery.viewInsetsOf(context).bottom;
    final double avail = MediaQuery.sizeOf(context).height - ime;
    final double maxContentH = avail * 0.85;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: ime),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxContentH),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 7 天选择（MiuixTabRow 横向滚动,一次编辑一天）。
              MiuixTabRow(
                tabs: const <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
                selectedTabIndex: _selected - 1,
                onTabSelected: (int i) => setState(() => _selected = i + 1),
              ),
              const SizedBox(height: 12),
              // 当前天配置卡（miuix 立体感：轻阴影）。
              _card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        MiuixText(
                          cur.label,
                          style: MiuixTheme.of(context).textStyles.title3,
                        ),
                        const Spacer(),
                        MiuixText(
                          '启用',
                          style: MiuixTheme.of(context).textStyles.body2,
                        ),
                        const SizedBox(width: 6),
                        MiuixSwitch(
                          value: cur.isEnabled,
                          onChanged: (bool v) =>
                              _onChanged(cur.copyWith(isEnabled: v)),
                        ),
                        const SizedBox(width: 8),
                        MiuixTextButton(
                          '重置',
                          onPressed: () => _onChanged(
                            DailyActivityTime.defaults(cur.weekday),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!cur.isEnabled)
                      MiuixText(
                        '此天未启用,不计入「今日剩余」',
                        style: MiuixTheme.of(context).textStyles.body2,
                        color: colors.onSurfaceVariantSummary,
                      )
                    else ...[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _TimeField(
                              label: '起始',
                              minutes: cur.startMinutes,
                              onChanged: (int m) =>
                                  _onChanged(cur.copyWith(startMinutes: m)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeField(
                              label: '终止',
                              minutes: cur.endMinutes,
                              onChanged: (int m) =>
                                  _onChanged(cur.copyWith(endMinutes: m)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 恢复默认（整表）。
              Align(
                alignment: Alignment.centerRight,
                child: MiuixTextButton(
                  '恢复全部默认',
                  onPressed: () async {
                    await widget.onReset();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 12),
              // 按钮行（随整页滚动;高度不足时滑到底部即可点保存）。
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      MiuixButton(
                        onPressed: dismiss,
                        colors: MiuixButtonDefaults.buttonColors(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      MiuixButton(
                        onPressed: dismiss == null
                            ? null
                            : () => widget.onSave(dismiss),
                        colors: MiuixButtonDefaults.buttonColorsPrimary(
                          context,
                        ),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 配置卡容器(v1.25.0 起复用统一阴影壳,深浅色自适应双层悬浮阴影;
  /// 原手写黑 8% 单层 + outline 描边移除 —— 悬浮感由阴影承担)。
  Widget _card(BuildContext context, {required Widget child}) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return CardShadow(
      radius: 14,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

/// 时间输入（#a08/#a09）：小时框 `:` 分钟框,冒号独立在框外。
/// 输入不做自动格式化/补零（避免「删一格乱弹数字」）；每框底部小字
/// 提示（"时"/"分"）；值在**失焦时后台解析提交**（0-23:0-59,越界钳制）。
class _TimeField extends StatefulWidget {
  const _TimeField({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  State<_TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<_TimeField> {
  late final TextEditingController _h;
  late final TextEditingController _m;
  final FocusNode _hFocus = FocusNode();
  final FocusNode _mFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _h = TextEditingController(text: _two(widget.minutes ~/ 60));
    _m = TextEditingController(text: _two(widget.minutes % 60));
    _hFocus.addListener(_onFocus);
    _mFocus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_TimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当没有焦点(用户不在编辑)且外部值变化(如重置/切天)时回显;
    // 编辑中绝不回写 → 不再出现"删一格自动弹数字"。
    if (oldWidget.minutes != widget.minutes &&
        !_hFocus.hasFocus &&
        !_mFocus.hasFocus) {
      _h.text = _two(widget.minutes ~/ 60);
      _m.text = _two(widget.minutes % 60);
    }
  }

  @override
  void dispose() {
    _hFocus.removeListener(_onFocus);
    _mFocus.removeListener(_onFocus);
    _h.dispose();
    _m.dispose();
    _hFocus.dispose();
    _mFocus.dispose();
    super.dispose();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  void _onFocus() {
    // 焦点丢失(编辑结束)→ 后台解析提交。
    if (!_hFocus.hasFocus && !_mFocus.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final int? h = int.tryParse(_h.text);
    final int? m = int.tryParse(_m.text);
    if (h == null || m == null) {
      // 未输入完整 → 回退显示当前值,不提交。
      _h.text = _two(widget.minutes ~/ 60);
      _m.text = _two(widget.minutes % 60);
      return;
    }
    widget.onChanged((h.clamp(0, 23)) * 60 + (m.clamp(0, 59)));
  }

  /// 单段数字框：内部不补零/不格式化,仅过滤非数字并限 2 位;
  /// 下方小字提示(用户需求:空时底部细小字体写 "时"/"分")。
  Widget _box({
    required TextEditingController c,
    required FocusNode f,
    required String hint,
    required VoidCallback next, // 输满 2 位自动跳下一框
  }) {
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 58,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: f.hasFocus
                  ? colors.primary
                  : colors.outline.withValues(alpha: 0.35),
              width: f.hasFocus ? 1.6 : 1,
            ),
          ),
          child: TextField(
            controller: c,
            focusNode: f,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            style: ts.title3,
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (String raw) {
              // 过滤非数字并截 2 位;不做格式化(后台提交)。
              final String d = raw.replaceAll(RegExp(r'[^0-9]'), '');
              final String v = d.length > 2 ? d.substring(0, 2) : d;
              if (v != c.text) {
                c.text = v;
                c.selection = TextSelection.collapsed(offset: v.length);
              }
              if (v.length == 2) next();
            },
          ),
        ),
        const SizedBox(height: 3),
        // 底部小字提示（细小特殊字体）。
        Text(
          hint,
          style: ts.body2.copyWith(
            fontSize: 9,
            color: colors.onSurfaceVariantSummary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiuixText(
          widget.label,
          style: ts.body2,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _box(
              c: _h,
              f: _hFocus,
              hint: '时',
              next: () => _mFocus.requestFocus(),
            ),
            // 冒号独立显示（不在输入框内,用户无需输入）。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(':', style: ts.title3),
            ),
            _box(c: _m, f: _mFocus, hint: '分', next: () => _mFocus.unfocus()),
          ],
        ),
      ],
    );
  }
}
