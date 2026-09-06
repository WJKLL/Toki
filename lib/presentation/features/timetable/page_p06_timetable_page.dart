// lib/presentation/features/timetable/page_p06_timetable_page.dart
// 编号：P-06 大课表编辑页（v1.16.0 重写，参考勾丰小站课程表）
// 说明：二级页面（不在底栏），从首页迷你课表「查看全部」进入。
// 布局：周课表网格 —— 列=周一~周日、行=节次（1..16），课程块（MiuixCard 彩色，
//       无毛玻璃）按 day×start 定位、支持跨节（len）；竖屏窄屏网格横向可滚动、
//       宽屏自适应填满；学期 meta（年级/学期/当前周次）表单 + badge。
// 交互：点空白格添加（预填星期/节次）、点课程块编辑、编辑弹窗内删除；单双周
//       按当前周次过滤（odd/even 不匹配淡化）。
// 数据：courseListProvider + scheduleMetaProvider（S-15，改后自动持久化同步首页）。
import 'package:flutter/gestures.dart' show DragStartBehavior;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart'
    show Material, MaterialType, ScaffoldMessenger, SnackBar;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/excel/excel_timetable_parser.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../domain/entities/class_period.dart';
import '../../../domain/entities/course.dart';
import '../../providers/course_provider.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/cards/card_shell.dart';

// ── 网格几何常量（单一事实源）──
const double _periodColW = 44; // 节次列宽
const double _dayColW = 64; // 每天列宽
const double _rowH = 56; // 每节行高
const double _headerH = 40; // 表头高
const int _maxPeriod = 16; // 最大节次（参考 f-start 1-16）
const List<String> _dayShort = <String>['一', '二', '三', '四', '五', '六', '日'];

class PageP06TimetablePage extends ConsumerStatefulWidget {
  const PageP06TimetablePage({super.key});

  @override
  ConsumerState<PageP06TimetablePage> createState() =>
      _PageP06TimetablePageState();
}

class _PageP06TimetablePageState extends ConsumerState<PageP06TimetablePage> {
  /// 顶栏返回按钮（二级页 leading）。
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('timetable.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  // ── C-25：顶部折叠滚动行为(v1.42.0:顶栏纯蒙版,无页面级快照采样)──
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  // ── 编辑状态 ──
  bool _sheetOpen = false;
  Course? _editing; // null = 新增

  // ── v1.21.0:节次时间表编辑状态 ──
  bool _periodsOpen = false;
  int? _timeEditIndex; // 正在编辑的节次(0 基),null=收起内联面板
  bool _timeEditIsStart = true; // true=编辑开始时间,false=结束时间
  int _timeHour = 8; // 时间草稿
  int _timeMinute = 0;

  /// 就地展开的选择字段（'day' / 'start' / 'len' / 'week'，null = 收起）。
  /// 轻量方案：无弹层/Overlay，仅当前展开字段重建 → 兼顾性能。
  String? _expandedPicker;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _locCtrl = TextEditingController();
  final TextEditingController _teacherCtrl = TextEditingController();
  final TextEditingController _gradeCtrl = TextEditingController();
  final TextEditingController _termCtrl = TextEditingController();
  final TextEditingController _weekCtrl = TextEditingController();
  // v1.42.0:起止周输入(开始周/结束周)。
  final TextEditingController _wsCtrl = TextEditingController();
  final TextEditingController _weCtrl = TextEditingController();

  // 表单选择状态（新增时由格子预填）。
  int _formDay = 1;
  int _formStart = 1;
  int _formLen = 1;
  // v1.42.0:周次四选(0=每周 1=单周 2=双周 3=指定起止周);起止文本
  //   存 _wsCtrl/_weCtrl,提交时解析校验(1..30 且 起 ≤ 止)。
  int _formWeekSel = 0;
  int _formColor = Course.autoColor('');

  /// 四选下标 → 三态枚举(0-2;3=范围模式仅用于状态,week 落 every)。
  static WeekType _weekSelToType(int sel) => switch (sel) {
    1 => WeekType.odd,
    2 => WeekType.even,
    _ => WeekType.every,
  };

  // ── 打开编辑弹窗（新增：预填 day/start）──
  void _openAdd(int day, int start) {
    _editing = null;
    _nameCtrl.clear();
    _locCtrl.clear();
    _teacherCtrl.clear();
    _formDay = day;
    _formStart = start.clamp(1, _maxPeriod);
    _formLen = 1;
    _formWeekSel = 0;
    _wsCtrl.text = '1';
    _weCtrl.text = '30';
    _formColor = Course.autoColor('');
    setState(() => _sheetOpen = true);
  }

  void _openEdit(Course c) {
    _editing = c;
    _nameCtrl.text = c.name;
    _locCtrl.text = c.location ?? '';
    _teacherCtrl.text = c.teacher ?? '';
    _formDay = c.day;
    _formStart = c.start;
    _formLen = c.len;
    // v1.42.0:weeks 非空(导入课/起止周课)→ 落到「指定起止周」模式并回显
    //   起止;否则三态(历史:导入课被伪装成「每周」,改三态即静默丢数据)。
    _formWeekSel = c.weeks.isNotEmpty ? 3 : c.week.index;
    _wsCtrl.text = c.weeks.isNotEmpty ? '${c.weeks.first}' : '1';
    _weCtrl.text = c.weeks.isNotEmpty ? '${c.weeks.last}' : '30';
    _formColor = c.colorValue;
    setState(() => _sheetOpen = true);
  }

  void _closeSheet() {
    setState(() {
      _sheetOpen = false;
      _expandedPicker = null;
    });
  }

  /// 选择字段值更新（点击展开 → 选择 → 收起；起止周选中后保持展开）。
  void _selectField(String key, int index) {
    setState(() {
      switch (key) {
        case 'day':
          _formDay = index + 1;
        case 'start':
          _formStart = index + 1;
        case 'len':
          _formLen = index + 1;
        case 'week':
          _formWeekSel = index;
      }
      _expandedPicker = (key == 'week' && index == 3) ? 'week' : null;
    });
  }

  /// 保存（新增 / 更新 → 自动持久化，首页迷你课表自动同步）。
  Future<void> _save() async {
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    // v1.42.0:指定起止周校验(1..30 且 起 ≤ 止)。
    final bool rangeMode = _formWeekSel == 3;
    final WeekType week = _weekSelToType(_formWeekSel);
    final List<int> rangeWeeks;
    if (rangeMode) {
      final int? s = int.tryParse(_wsCtrl.text.trim());
      final int? e = int.tryParse(_weCtrl.text.trim());
      if (s == null ||
          e == null ||
          s < 1 ||
          e > 30 ||
          s > e) {
        _showSnack('起止周无效:开始周需 ≤ 结束周(1-30)');
        return;
      }
      rangeWeeks = <int>[for (int w = s; w <= e; w++) w];
    } else {
      rangeWeeks = const <int>[];
    }
    final CourseListNotifier notifier = ref.read(courseListProvider.notifier);
    final Course? editing = _editing;
    if (editing == null) {
      await notifier.addCourse(
        name: name,
        day: _formDay,
        start: _formStart,
        len: _formLen,
        week: week,
        weeks: rangeWeeks,
        colorValue: _formColor,
        location: _locCtrl.text.trim().isEmpty ? null : _locCtrl.text.trim(),
        teacher: _teacherCtrl.text.trim().isEmpty
            ? null
            : _teacherCtrl.text.trim(),
      );
    } else {
      await notifier.updateCourse(
        editing.copyWith(
          name: name,
          day: _formDay,
          start: _formStart,
          len: _formLen,
          week: week,
          colorValue: _formColor,
          location: _locCtrl.text.trim().isEmpty ? null : _locCtrl.text.trim(),
          teacher: _teacherCtrl.text.trim().isEmpty
              ? null
              : _teacherCtrl.text.trim(),
          // 三态模式 → 清空导入/范围 weeks(避免双语义);范围模式 → 重写。
          weeks: rangeMode ? rangeWeeks : null,
          clearWeeks: !rangeMode,
        ),
      );
    }
    if (mounted) _closeSheet();
  }

  /// 删除课程。
  Future<void> _delete() async {
    final Course? editing = _editing;
    if (editing == null) return;
    setState(() => _sheetOpen = false);
    await ref.read(courseListProvider.notifier).deleteCourse(editing.id);
  }

  /// 保存学期信息。
  Future<void> _saveMeta() async {
    await ref
        .read(scheduleMetaProvider.notifier)
        .saveMeta(
          ScheduleMeta(
            grade: _gradeCtrl.text.trim(),
            term: int.tryParse(_termCtrl.text.trim()) ?? 1,
            week: int.tryParse(_weekCtrl.text.trim()) ?? 1,
          ),
        );
  }

  /// v1.17.0（S-18 导入）：选择 Excel 课表 → 解析 → 合并导入（同格替换）。
  Future<void> _importTimetable() async {
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['xls', 'xlsx'],
    );
    if (file == null) return; // 用户取消
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (mounted) _showSnack('读取文件失败：$e');
      return;
    }
    if (bytes.isEmpty) {
      if (mounted) _showSnack('读取文件失败：文件为空');
      return;
    }
    try {
      final List<ParsedCourse> parsed = ExcelTimetableParser.parse(bytes);
      await ref.read(courseListProvider.notifier).importCourses(parsed);
      if (mounted) _showSnack('导入成功：${parsed.length} 门课（同格已替换）');
    } on FormatException catch (e) {
      if (mounted) _showSnack('导入失败：${e.message}');
    } catch (e) {
      if (mounted) _showSnack('导入失败：$e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locCtrl.dispose();
    _teacherCtrl.dispose();
    _gradeCtrl.dispose();
    _termCtrl.dispose();
    _weekCtrl.dispose();
    _wsCtrl.dispose();
    _weCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '大课表',
        largeTitle: '大课表',
        navigationIcon: _backButton,
        scrollBehavior: _collapse,
      ),
      content: (padding) {
        final List<Course> courses =
            ref.watch(courseListProvider).value ?? const <Course>[];
        final ScheduleMeta meta =
            ref.watch(scheduleMetaProvider).value ?? const ScheduleMeta();
        // v1.21.0:节次时间表(16 节)与唯一写入口。
        final List<ClassPeriod> periods = ref.watch(
          appSettingsProvider.select((s) => s.classPeriods),
        );
        final AppSettingsController settingsCtrl = ref.read(
          appSettingsProvider.notifier,
        );
        final double width = MediaQuery.sizeOf(context).width;
        // 学期表单控制器同步（仅首次/变化时）。
        _gradeCtrl.text = meta.grade;
        _termCtrl.text = '${meta.term}';
        _weekCtrl.text = '${meta.week}';

        final Widget list = ListView(
          // v1.18.x（T1）：列表按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(top: 12 + padding.top, bottom: 24),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            // 学期 badge。
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MiuixText(
                '${meta.grade.isEmpty ? '未设置年级' : meta.grade} · '
                '第${meta.term}学期 · 第${meta.week}周',
                style: MiuixTheme.of(context).textStyles.body2,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            // 学期 meta 表单（MiuixCard）。
            _buildMetaCard(colors),
            const SizedBox(height: 12),
            // v1.21.0:节次时间表入口(16 节起止时间 → 首页课程倒计时)。
            _buildPeriodsEntry(colors, periods),
            const SizedBox(height: 12),
            // 周课表网格（自适应：窄屏横向滚动、宽屏填满）。
            _buildGrid(courses, meta, width, colors),
            const SizedBox(height: 8),
          ],
        );
        // v1.42.0(④A):摘除页面级采样(C-28/心跳) — 滚动零 toImageSync。
        final Widget listWithBg = ColoredBox(
          color: colors.surface,
          child: list,
        );
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: <Widget>[
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: MiuixScrollBehaviorListener(
                      behavior: _collapse,
                      child: listWithBg,
                    ),
                  ),
                ],
              ),
              _buildEditSheet(colors),
              // v1.21.0:节次时间表弹层(与课程编辑弹层互斥使用)。
              _buildPeriodsSheet(colors, periods, settingsCtrl),
            ],
          ),
        );
      },
    );
  }

  // ── v1.21.0:节次时间表(16 节起止 → 首页课程倒计时)──────────────

  /// 节次时间表入口卡(学期信息卡下方)。
  Widget _buildPeriodsEntry(MiuixColors colors, List<ClassPeriod> periods) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final int enabledCount = periods.where((ClassPeriod p) => p.enabled).length;
    // v1.25.0:整宽内容卡套统一阴影壳(radius 对齐 MiuixCard 16)。
    // v1.44.x:暗色高光内建进 CardShadow。
    return CardShadow(
      radius: 16,
      child: MiuixCard(
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onPressed: () => setState(() => _periodsOpen = true),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MiuixText(
                    '节次时间表',
                    style: textStyles.body1,
                    color: colors.onSurface,
                  ),
                  const SizedBox(height: 2),
                  MiuixText(
                    '已启用 $enabledCount/${ClassPeriod.maxPeriods} 节 · '
                    '首页课程倒计时据此计算',
                    style: textStyles.body2,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ],
              ),
            ),
            MiuixIcon(
              vector: appIcon('chevronRight'),
              size: 18,
              tint: colors.onSurfaceVariantSummary,
            ),
          ],
        ),
      ),
    );
  }

  /// 节次时间表弹层:16 行(启用开关 + 起止时间 chip),底部恢复默认模板。
  /// 时间编辑采用**内联面板**(编辑中隐藏列表,避免嵌套弹层/Overlay)。
  Widget _buildPeriodsSheet(
    MiuixColors colors,
    List<ClassPeriod> periods,
    AppSettingsController ctrl,
  ) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final int? editing = _timeEditIndex;
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (editing == null) ...<Widget>[
          MiuixText(
            '默认第 1 节 08:00 起,45 分钟 + 10 分钟课间;'
            '第 13-16 节默认关闭,可自行启用',
            style: textStyles.body2,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 10),
          // 16 行列表(分隔线手绘,避免额外组件依赖)。
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < ClassPeriod.maxPeriods; i++) ...[
                  if (i > 0)
                    MiuixHorizontalDivider(
                      color: colors.dividerLine.withValues(alpha: 0.4),
                    ),
                  _buildPeriodRow(i, periods, colors, ctrl),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              MiuixTextButton(
                '恢复默认模板',
                onPressed: () => ctrl.setClassPeriods(ClassPeriod.defaults),
              ),
            ],
          ),
        ] else
          _buildInlineTimeEditor(periods, colors, ctrl),
      ],
    );
    return MiuixOverlayBottomSheet(
      show: _periodsOpen,
      title: '节次时间表',
      onDismissRequest: () => setState(() {
        _periodsOpen = false;
        _timeEditIndex = null;
      }),
      // 内容上限 80% 屏高,整块可滚(16 行 + 内联面板都不会顶出屏幕)。
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: content,
          ),
        ),
      ),
    );
  }

  /// 单行:[第 N 节] [开始 chip] — [结束 chip] [启用开关]。
  Widget _buildPeriodRow(
    int index,
    List<ClassPeriod> periods,
    MiuixColors colors,
    AppSettingsController ctrl,
  ) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final ClassPeriod p = periods[index];
    final bool hasTime = p.enabled && p.endMinutes > p.startMinutes;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: <Widget>[
          MiuixText(
            '第${index + 1}节',
            style: textStyles.body2,
            color: colors.onSurface,
          ),
          const SizedBox(width: 10),
          _buildTimeChip(
            hasTime ? ClassPeriod.formatMinutes(p.startMinutes) : '--:--',
            p.enabled,
            () => _openTimeEditor(index, true, periods),
            colors,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: MiuixText(
              '—',
              style: textStyles.body2,
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          _buildTimeChip(
            hasTime ? ClassPeriod.formatMinutes(p.endMinutes) : '--:--',
            p.enabled,
            () => _openTimeEditor(index, false, periods),
            colors,
          ),
          const Spacer(),
          // 启用开关:空节次可先启用(时间用默认模板值或自行设置)。
          MiuixSwitch(
            value: p.enabled,
            onChanged: (bool v) {
              final List<ClassPeriod> next = List<ClassPeriod>.of(periods);
              next[index] = p.copyWith(enabled: v);
              ctrl.setClassPeriods(next);
            },
          ),
        ],
      ),
    );
  }

  /// 时间 chip(点击进入内联编辑;设时间会自动启用该节)。
  Widget _buildTimeChip(
    String text,
    bool active,
    VoidCallback onTap,
    MiuixColors colors,
  ) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: MiuixText(
          text,
          style: textStyles.body2,
          color: active ? colors.onSurface : colors.onSurfaceVariantSummary,
        ),
      ),
    );
  }

  /// 打开第 [index] 节 [isStart](true=开始)时间的内联编辑面板。
  void _openTimeEditor(int index, bool isStart, List<ClassPeriod> periods) {
    final ClassPeriod p = periods[index];
    final int m = isStart ? p.startMinutes : p.endMinutes;
    setState(() {
      _timeEditIndex = index;
      _timeEditIsStart = isStart;
      _timeHour = (m ~/ 60) % 24;
      _timeMinute = m % 60;
    });
  }

  /// 内联时间编辑面板(时 + 分 MiuixNumberPicker,确定/取消)。
  Widget _buildInlineTimeEditor(
    List<ClassPeriod> periods,
    MiuixColors colors,
    AppSettingsController ctrl,
  ) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final int index = _timeEditIndex!;
    final String kind = _timeEditIsStart ? '开始' : '结束';
    String two(int v) => v.toString().padLeft(2, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: MiuixText(
                '第${index + 1}节 · $kind时间',
                style: textStyles.body1,
                color: colors.onSurface,
              ),
            ),
            // 快捷:当前值摘要。
            MiuixText(
              '${two(_timeHour)}:${two(_timeMinute)}',
              style: textStyles.body2,
              color: colors.primary,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: MiuixNumberPicker(
                value: _timeHour,
                min: 0,
                max: 23,
                label: two,
                wrapAround: true,
                onValueChanged: (int v) => setState(() => _timeHour = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: MiuixText(
                ':',
                style: textStyles.title1,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            Expanded(
              child: MiuixNumberPicker(
                value: _timeMinute,
                min: 0,
                max: 59,
                label: two,
                wrapAround: true,
                onValueChanged: (int v) => setState(() => _timeMinute = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            MiuixTextButton(
              '取消',
              onPressed: () => setState(() => _timeEditIndex = null),
            ),
            const SizedBox(width: 12),
            MiuixButton(
              onPressed: () => _commitTime(periods, ctrl),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: const MiuixText('确定'),
            ),
          ],
        ),
      ],
    );
  }

  /// 提交时间草稿:结束时间钳制到 > 开始(防倒置),并自动启用该节。
  void _commitTime(List<ClassPeriod> periods, AppSettingsController ctrl) {
    final int? index = _timeEditIndex;
    if (index == null || index >= periods.length) return;
    final ClassPeriod p = periods[index];
    final int minutes = _timeHour * 60 + _timeMinute;
    int start = _timeEditIsStart ? minutes : p.startMinutes;
    int end = _timeEditIsStart ? p.endMinutes : minutes;
    if (end <= start) end = start + 1; // 静默钳制,防倒置
    const int dayEnd = 24 * 60 - 1;
    if (end > dayEnd) {
      end = dayEnd;
      start = end - 1;
    }
    final List<ClassPeriod> next = List<ClassPeriod>.of(periods);
    next[index] = ClassPeriod(
      startMinutes: start,
      endMinutes: end,
      enabled: true, // 设时间 = 意图启用
    );
    ctrl.setClassPeriods(next);
    setState(() => _timeEditIndex = null);
  }

  /// 学期信息编辑卡片（年级/学期/当前周次 + 保存）。
  Widget _buildMetaCard(MiuixColors colors) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    // v1.25.0:整宽内容卡套统一阴影壳(radius 对齐 MiuixCard 16)。
    return CardShadow(
      radius: 16,
      child: MiuixCard(
        insideMargin: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: MiuixText(
                    '学期信息',
                    style: textStyles.body1,
                    color: colors.onSurface,
                  ),
                ),
                // v1.17.0（S-18 导入）：实底 MiuixButton（非透明）。
                MiuixButton(
                  key: const ValueKey('timetable.import'),
                  onPressed: _importTimetable,
                  minHeight: 30,
                  insideMargin: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: const Text('导入课表'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: MiuixTextField(
                    label: '年级',
                    controller: _gradeCtrl,
                    singleLine: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MiuixTextField(
                    label: '学期',
                    controller: _termCtrl,
                    singleLine: true,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MiuixTextField(
                    label: '当前周次',
                    controller: _weekCtrl,
                    singleLine: true,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: MiuixButton(
                onPressed: _saveMeta,
                minHeight: 30,
                insideMargin: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 周课表网格（Stack 定位课程块）。
  Widget _buildGrid(
    List<Course> courses,
    ScheduleMeta meta,
    double screenWidth,
    MiuixColors colors,
  ) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final double gridWidth = math.max(
      screenWidth - 24,
      _periodColW + 7 * _dayColW,
    );
    const double gridHeight = _headerH + _maxPeriod * _rowH;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: gridWidth,
        height: gridHeight,
        child: Stack(
          children: <Widget>[
            // 表头：节次角落 + 周一~周日。
            Positioned(
              left: 0,
              top: 0,
              width: _periodColW,
              height: _headerH,
              child: _headerCell('节次', colors, textStyles),
            ),
            for (int d = 0; d < 7; d++)
              Positioned(
                left: _periodColW + d * _dayColW,
                top: 0,
                width: _dayColW,
                height: _headerH,
                child: _headerCell('周${_dayShort[d]}', colors, textStyles),
              ),
            // 节次行 + 空白 cell。
            for (int p = 1; p <= _maxPeriod; p++) ...[
              Positioned(
                left: 0,
                top: _headerH + (p - 1) * _rowH,
                width: _periodColW,
                height: _rowH,
                child: _periodCell('$p', colors, textStyles),
              ),
              for (int d = 1; d <= 7; d++)
                Positioned(
                  left: _periodColW + (d - 1) * _dayColW,
                  top: _headerH + (p - 1) * _rowH,
                  width: _dayColW,
                  height: _rowH,
                  child: _emptyCell(d, p, colors),
                ),
            ],
            // 课程块（上层，单双周过滤）。
            for (final Course c in courses)
              if (c.showsOn(meta.week))
                Positioned(
                  left: _periodColW + (c.day - 1) * _dayColW + 2,
                  top: _headerH + (c.start - 1) * _rowH + 2,
                  width: _dayColW - 4,
                  height: c.len * _rowH - 4,
                  child: _courseBlock(c, meta, colors),
                )
              else
                Positioned(
                  left: _periodColW + (c.day - 1) * _dayColW + 2,
                  top: _headerH + (c.start - 1) * _rowH + 2,
                  width: _dayColW - 4,
                  height: c.len * _rowH - 4,
                  // 非本周（单双周不匹配）→ 淡化显示，仍可点击编辑。
                  child: Opacity(
                    opacity: 0.35,
                    child: _courseBlock(c, meta, colors),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, MiuixColors colors, MiuixTextStyles ts) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: MiuixText(
        text,
        style: ts.body2,
        color: colors.onSurfaceVariantSummary,
      ),
    );
  }

  Widget _periodCell(String text, MiuixColors colors, MiuixTextStyles ts) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: MiuixText(
        text,
        style: ts.body2,
        color: colors.onSurfaceVariantSummary,
      ),
    );
  }

  /// 空白格：点击添加（预填该天该节）。
  Widget _emptyCell(int day, int period, MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openAdd(day, period),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  /// 课程块（MiuixCard 彩色，无毛玻璃；点击编辑）。
  Widget _courseBlock(Course c, ScheduleMeta meta, MiuixColors colors) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final Color bg = Color(c.colorValue);
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: MiuixCard(
        onPressed: () => _openEdit(c),
        onLongPress: () => _openEdit(c),
        colors: MiuixCardColors(
          color: bg,
          contentColor: const Color(0xFFFFFFFF),
        ),
        insideMargin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        cornerRadius: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MiuixText(
              c.name,
              style: textStyles.body2,
              color: const Color(0xFFFFFFFF),
              maxLines: c.len >= 2 ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (c.location != null && c.location!.isNotEmpty && c.len >= 2)
              MiuixText(
                c.location!,
                style: textStyles.body2.copyWith(fontSize: 10),
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            // 周次角标(v1.42.0:具体周次如 2-18;三态单/双周;每周无角标)。
            if (c.weeks.isNotEmpty)
              MiuixText(
                '第${Course.weeksLabel(c.weeks)}周',
                style: textStyles.body2.copyWith(fontSize: 10),
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else if (c.week != WeekType.every)
              MiuixText(
                Course.weekLabel(c.week),
                style: textStyles.body2.copyWith(fontSize: 10),
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
              ),
          ],
        ),
      ),
    );
  }

  /// 编辑/添加课程 BottomSheet（参考勾丰小站 sched-modal）。
  Widget _buildEditSheet(MiuixColors colors) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    return MiuixOverlayBottomSheet(
      show: _sheetOpen,
      title: _editing == null ? '添加课程' : '编辑课程',
      onDismissRequest: _closeSheet,
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MiuixTextField(
                label: '课程名',
                controller: _nameCtrl,
                singleLine: true,
              ),
              const SizedBox(height: 12),
              // 星期（点击展开选择）。
              _pickerField(
                key: 'day',
                label: '星期',
                options: _dayShort.map((String s) => '周$s').toList(),
                selectedIndex: _formDay - 1,
                colors: colors,
                textStyles: textStyles,
              ),
              const SizedBox(height: 12),
              // 开始节次（点击展开选择 1-16）。
              _pickerField(
                key: 'start',
                label: '开始节次',
                options: <String>[for (int i = 1; i <= _maxPeriod; i++) '$i'],
                selectedIndex: _formStart - 1,
                colors: colors,
                textStyles: textStyles,
              ),
              const SizedBox(height: 12),
              // 节数（点击展开选择 1-4）。
              _pickerField(
                key: 'len',
                label: '节数',
                options: const <String>['1节', '2节', '3节', '4节'],
                selectedIndex: _formLen - 1,
                colors: colors,
                textStyles: textStyles,
              ),
              const SizedBox(height: 12),
              // 周次（每周/单周/双周/指定起止周;v1.42.0 起止周编辑）。
              _pickerField(
                key: 'week',
                label: '周次',
                options: const <String>['每周', '单周', '双周', '指定起止周'],
                selectedIndex: _formWeekSel,
                colors: colors,
                textStyles: textStyles,
                trailing: _expandedPicker == 'week' && _formWeekSel == 3
                    ? _buildWeekRangeEditor(colors, textStyles)
                    : null,
              ),
              const SizedBox(height: 12),
              // 颜色选择（auto + 7 预设）。
              MiuixText(
                '卡片颜色',
                style: textStyles.body2,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _colorDot(0, '自动', colors, isAuto: true),
                  for (int i = 0; i < Course.presetColors.length; i++)
                    _colorDot(
                      Course.presetColors[i],
                      '',
                      colors,
                      isAuto: false,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              MiuixTextField(
                label: '地点（可选）',
                controller: _locCtrl,
                singleLine: true,
              ),
              const SizedBox(height: 12),
              MiuixTextField(
                label: '教师（可选）',
                controller: _teacherCtrl,
                singleLine: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  // 删除（编辑态显示）。
                  if (_editing != null)
                    MiuixButton(
                      onPressed: _delete,
                      colors: MiuixButtonColors(
                        color: colors.error,
                        disabledColor: colors.error.withValues(alpha: 0.4),
                        contentColor: colors.onError,
                        disabledContentColor: colors.onError,
                      ),
                      child: const Text('删除'),
                    ),
                  const Spacer(),
                  MiuixButton(onPressed: _closeSheet, child: const Text('取消')),
                  const SizedBox(width: 12),
                  MiuixButton(
                    onPressed: _save,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 点击展开的选择字段（值行 + 箭头；展开显示胶囊选项 Wrap + 附加区）。
  /// 轻量实现：仅当前展开字段重建，无弹层/Overlay（兼顾性能）。
  Widget _pickerField({
    required String key,
    required String label,
    required List<String> options,
    required int selectedIndex,
    required MiuixColors colors,
    required MiuixTextStyles textStyles,
    Widget? trailing,
  }) {
    final bool expanded = _expandedPicker == key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MiuixText(
          label,
          style: textStyles.body2,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expandedPicker = expanded ? null : key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              // v1.16.2：未展开字段加边框，增强可读性（可点击感）。
              border: Border.all(
                color: colors.outline.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: MiuixText(
                    options[selectedIndex],
                    style: textStyles.body1,
                    color: colors.onSurface,
                  ),
                ),
                MiuixDropdownArrowEndAction(
                  actionColor: colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (int i = 0; i < options.length; i++)
                  _optionChip(key, i, options[i], colors, textStyles),
              ],
            ),
          ),
        // v1.42.0:展开附加区(「指定起止周」选中时显示起止输入)。
        if (expanded && trailing != null) trailing,
      ],
    );
  }

  /// 起止周编辑区：开始周 / 结束周 数字输入(1..30,提交校验起 ≤ 止)。
  Widget _buildWeekRangeEditor(
    MiuixColors colors,
    MiuixTextStyles textStyles,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: MiuixTextField(
                  key: const ValueKey('timetable.weekStart'),
                  controller: _wsCtrl,
                  label: '开始周',
                  singleLine: true,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              MiuixText(
                '至',
                style: textStyles.body1,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MiuixTextField(
                  key: const ValueKey('timetable.weekEnd'),
                  controller: _weCtrl,
                  label: '结束周',
                  singleLine: true,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          MiuixText(
            '课程仅在指定周次范围内显示(1-30,如 2-18)',
            style: textStyles.footnote1,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  /// 选项胶囊（选中高亮）。
  Widget _optionChip(
    String key,
    int index,
    String text,
    MiuixColors colors,
    MiuixTextStyles textStyles,
  ) {
    final bool selected = _isSelected(key, index);
    return GestureDetector(
      onTap: () => _selectField(key, index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.14)
              : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? colors.primary
                : colors.outline.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: MiuixText(
          text,
          style: textStyles.body2,
          color: selected ? colors.primary : colors.onSurface,
        ),
      ),
    );
  }

  /// 字段当前选中下标判断。
  bool _isSelected(String key, int index) => switch (key) {
    'day' => index == _formDay - 1,
    'start' => index == _formStart - 1,
    'len' => index == _formLen - 1,
    'week' => index == _formWeekSel,
    _ => false,
  };

  /// 颜色选择圆点（选中高亮边框）。
  Widget _colorDot(
    int colorValue,
    String label,
    MiuixColors colors, {
    required bool isAuto,
  }) {
    final bool selected = _formColor == colorValue;
    final Color c = isAuto ? colors.surfaceContainerHighest : Color(colorValue);
    return GestureDetector(
      onTap: () => setState(() => _formColor = colorValue),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? colors.primary
                : colors.outline.withValues(alpha: 0.4),
            width: selected ? 2.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: label.isEmpty
            ? null
            : MiuixText(
                label,
                style: MiuixTheme.of(context).textStyles.body2
                    .copyWith(fontSize: 10),
              ),
      ),
    );
  }
}
