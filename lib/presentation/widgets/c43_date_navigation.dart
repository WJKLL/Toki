// lib/presentation/widgets/c43_date_navigation.dart
// 编号：C-43 日期导航栏（v1.43.0，P-10 待办页顶部；v1.43.0 增强月历）
// 说明：左右箭头 ±1 天 + 中央日期文本(相对标签 今天/明天/昨天/周X) +
//   点击弹出自绘月历(MiuixOverlayDialog)选任意日期。纯 Miuix 视觉：
//   - 日期仅日期部分(DateTime(y,m,d))，跨月自动进位/退位；
//   - **月历可左右侧滑切月(PageView 原生滑动过渡)**；头部箭头同切；
//   - **头部点「年月」展开年份选择器**(1900-2199 滚动列表,AnimatedSwitcher
//     过渡切回月视图)；今天描边、选中浅主色底；跨年翻页自由；
//   - 无第三方依赖；弹层 show 布尔驱动、静止零 ticker。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/lifecycle/app_lifecycle_controller.dart';
import '../../core/widgets/app_icons.dart';

/// C-43 日期导航栏。
class C43DateNavigation extends StatefulWidget {
  const C43DateNavigation({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 当前选中日期（仅日期部分）。
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  State<C43DateNavigation> createState() => _C43DateNavigationState();
}

class _C43DateNavigationState extends State<C43DateNavigation> {
  /// S-24 复位订阅（后台 ≥15s 复位时收起日历弹层）。
  bool _calendarOpen = false;

  DateTime get _day => widget.value;

  @override
  void initState() {
    super.initState();
    AppLifecycleController.instance.addListener(_onAppReset);
  }

  void _onAppReset() {
    if (mounted && _calendarOpen) {
      setState(() => _calendarOpen = false);
    }
  }

  @override
  void dispose() {
    AppLifecycleController.instance.removeListener(_onAppReset);
    super.dispose();
  }

  void _shift(int days) {
    widget.onChanged(_day.add(Duration(days: days)));
  }

  /// 中央日期文本 + 相对标签 + 展开图标。
  String get _dateText {
    final DateTime now = DateTime.now();
    final bool sameYear = _day.year == now.year;
    final String md = '${_day.month}月${_day.day}日';
    return sameYear ? md : '${_day.year}年$md';
  }

  String get _relativeTag {
    final DateTime now = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final int diff = _day.difference(now).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == -1) return '昨天';
    return _weekday(_day.weekday);
  }

  static String _weekday(int w) => switch (w) {
    1 => '周一',
    2 => '周二',
    3 => '周三',
    4 => '周四',
    5 => '周五',
    6 => '周六',
    _ => '周日',
  };

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            // ── 前一天（MIUI 无底：删除圆形底色，按压仅圆形遮罩；热区 40）──
            MiuixPressable(
              borderRadius: BorderRadius.circular(999),
              onPressed: () => _shift(-1),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: MiuixIcon(
                    vector: appIcon('chevronBackward'),
                    size: 18,
                    tint: colors.onSurfaceVariantActions,
                  ),
                ),
              ),
            ),
            // ── 中央日期（点击弹月历）──
            Expanded(
              child: MiuixPressable(
                feedbackType: MiuixPressFeedbackType.sink,
                sinkAmount: 0.96,
                borderRadius: BorderRadius.circular(14),
                onPressed: () => setState(() => _calendarOpen = true),
                child: Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      MiuixText(
                        _dateText,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                      const SizedBox(width: 8),
                      _TagChip(text: _relativeTag),
                      const SizedBox(width: 4),
                      MiuixIcon(
                        vector: appIcon('expandMore'),
                        size: 14,
                        tint: colors.onSurfaceVariantActions,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ── 后一天（MIUI 无底：删除圆形底色，按压仅圆形遮罩；热区 40）──
            MiuixPressable(
              borderRadius: BorderRadius.circular(999),
              onPressed: () => _shift(1),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: MiuixIcon(
                    vector: appIcon('chevronForward'),
                    size: 18,
                    tint: colors.onSurfaceVariantActions,
                  ),
                ),
              ),
            ),
          ],
        ),
        // ── 月历弹层（show 布尔驱动，false 零开销）──
        MiuixOverlayDialog(
          show: _calendarOpen,
          title: '选择日期',
          onDismissRequest: () => setState(() => _calendarOpen = false),
          content: _MonthCalendar(
            initial: _day,
            onPick: (DateTime d) {
              setState(() => _calendarOpen = false);
              widget.onChanged(d);
            },
          ),
        ),
      ],
    );
  }
}

/// 相对标签小胶囊（今天/明天/…）。
class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool isToday = text == '今天';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isToday
            ? colors.primary.withValues(alpha: 0.12)
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: MiuixText(
        text,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: isToday ? colors.primary : colors.onSurfaceVariantSummary,
      ),
    );
  }
}

/// 月历可支持年范围（1900..2199，PageView 页 = (年-1900)*12 + (月-1)）。
const int _kCalendarBaseYear = 1900;
const int _kCalendarYearCount = 300; // 1900-2199

/// 自绘月历（周一开头；PageView 侧滑切月；点年月开年选择器）。
class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({required this.initial, required this.onPick});

  final DateTime initial;
  final ValueChanged<DateTime> onPick;

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  static const List<String> _wd = <String>['一', '二', '三', '四', '五', '六', '日'];

  /// 当前页索引（page = (year-base)*12 + month-1）。
  late int _page = _pageOf(widget.initial.year, widget.initial.month);
  late final PageController _pc = PageController(initialPage: _page);

  /// 年选择视图是否展开（AnimatedSwitcher 过渡）。
  bool _yearSheet = false;

  static int _pageOf(int year, int month) =>
      (year - _kCalendarBaseYear) * 12 + (month - 1);

  static (int, int) _ymOf(int page) {
    final int total = page + 12; // 1 基月
    return ((total - 1) ~/ 12 + _kCalendarBaseYear, (total - 1) % 12 + 1);
  }

  int get _year => _ymOf(_page).$1;
  int get _month => _ymOf(_page).$2;

  void _onPageChanged(int page) {
    if (page != _page) setState(() => _page = page);
  }

  void _stepMonth(int delta) {
    final int next = (_page + delta).clamp(0, _kCalendarYearCount * 12 - 1);
    _pc.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _pickYear(int year) {
    final int next = _pageOf(year, _month).clamp(0, _kCalendarYearCount * 12 - 1);
    setState(() {
      _yearSheet = false;
      _page = next;
    });
    _pc.jumpToPage(next);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final DateTime today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ── 头部：上/下月箭头 + 中央「年月」（点开年选择）──
          Row(
            children: <Widget>[
              MiuixPressable(
                feedbackType: MiuixPressFeedbackType.sink,
                sinkAmount: 0.9,
                borderRadius: BorderRadius.circular(999),
                onPressed: () => _stepMonth(-1),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: MiuixIcon(
                    vector: appIcon('chevronBackward'),
                    size: 15,
                    tint: colors.onSurfaceVariantActions,
                  ),
                ),
              ),
              Expanded(
                child: MiuixPressable(
                  feedbackType: MiuixPressFeedbackType.sink,
                  sinkAmount: 0.96,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: () => setState(() => _yearSheet = !_yearSheet),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        MiuixText(
                          '$_year年$_month月',
                          style: ts.body1,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                        const SizedBox(width: 4),
                        MiuixIcon(
                          vector: appIcon('expandMore'),
                          size: 12,
                          tint: colors.onSurfaceVariantActions,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              MiuixPressable(
                feedbackType: MiuixPressFeedbackType.sink,
                sinkAmount: 0.9,
                borderRadius: BorderRadius.circular(999),
                onPressed: () => _stepMonth(1),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: MiuixIcon(
                    vector: appIcon('chevronForward'),
                    size: 15,
                    tint: colors.onSurfaceVariantActions,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // ── 月历视图 ↔ 年份选择视图（AnimatedSwitcher 过渡）──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _yearSheet
                ? _buildYearSheet(context, today)
                : _buildMonthBody(context, today),
          ),
          const SizedBox(height: 2),
          // ── 回到今天（两视图共用底部）──
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                widget.onPick(DateTime(today.year, today.month, today.day));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: MiuixText(
                  '回到今天',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 月历视图（星期头 + PageView 各月网格）──────────────

  Widget _buildMonthBody(BuildContext context, DateTime today) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Column(
      key: const ValueKey<String>('cal.month'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 星期头（周一开头）。
        Row(
          children: <Widget>[
            for (final String w in _wd)
              Expanded(
                child: MiuixText(
                  w,
                  textAlign: TextAlign.center,
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        // 连续月份 PageView：左右侧滑切月（原生滑动过渡），高度固定 6 行。
        SizedBox(
          height: 34 * 6,
          child: PageView.builder(
            controller: _pc,
            itemCount: _kCalendarYearCount * 12,
            onPageChanged: _onPageChanged,
            itemBuilder: (BuildContext context, int index) {
              final (int y, int m) = _ymOf(index);
              return _MonthGrid(
                year: y,
                month: m,
                sel: widget.initial,
                today: today,
                onPick: widget.onPick,
              );
            },
          ),
        ),
      ],
    );
  }

  // ── 年份选择视图（1900-2199 滚动列表，当前年高亮）────────

  Widget _buildYearSheet(BuildContext context, DateTime today) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    const double itemExtent = 36.0;
    return SizedBox(
      key: const ValueKey<String>('cal.year'),
      height: 34 * 6,
      child: Column(
        children: <Widget>[
          // 提示行。
          MiuixText(
            '选择年份',
            fontSize: 11,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              // 初始滚动到当前年附近（居中展示）。
              controller: ScrollController(
                initialScrollOffset: ((_year - _kCalendarBaseYear) - 4) *
                    itemExtent,
              ),
              itemExtent: itemExtent,
              itemCount: _kCalendarYearCount,
              itemBuilder: (BuildContext context, int index) {
                final int y = _kCalendarBaseYear + index;
                final bool current = y == _year;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pickYear(y),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: current
                          ? colors.primary.withValues(alpha: 0.14)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: MiuixText(
                      '$y年',
                      style: ts.body2.copyWith(
                        color: current
                            ? colors.primary
                            : colors.onSurface,
                        fontWeight: current
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单月日期网格（周一开头；今天描边；选中浅主色底）。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.month,
    required this.sel,
    required this.today,
    required this.onPick,
  });

  final int year;
  final int month;
  final DateTime sel;
  final DateTime today;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final DateTime first = DateTime(year, month, 1);
    final int lead = (first.weekday + 6) % 7; // 周一=0
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final int cells = ((lead + daysInMonth + 6) ~/ 7) * 7;

    final List<Widget> rows = <Widget>[];
    for (int row = 0; row < cells ~/ 7; row++) {
      rows.add(
        Row(
          children: <Widget>[
            for (int col = 0; col < 7; col++)
              Expanded(
                child: _dayCell(
                  row * 7 + col,
                  lead,
                  daysInMonth,
                  colors,
                ),
              ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _dayCell(int idx, int lead, int daysInMonth, MiuixColors colors) {
    final int dayNo = idx - lead + 1;
    final bool inMonth = dayNo >= 1 && dayNo <= daysInMonth;
    final bool isToday = inMonth &&
        year == today.year &&
        month == today.month &&
        dayNo == today.day;
    final bool isSel = inMonth &&
        year == sel.year &&
        month == sel.month &&
        dayNo == sel.day;
    return GestureDetector(
      onTap: inMonth ? () => onPick(DateTime(year, month, dayNo)) : null,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSel ? colors.primary.withValues(alpha: 0.14) : null,
          shape: BoxShape.circle,
          border: isToday ? Border.all(color: colors.primary, width: 1.2) : null,
        ),
        child: MiuixText(
          inMonth ? '$dayNo' : '',
          fontSize: 13,
          fontWeight: isSel || isToday ? FontWeight.w600 : FontWeight.w400,
          color: !inMonth
              ? const Color(0x00000000)
              : isSel
              ? colors.primary
              : colors.onSurface,
        ),
      ),
    );
  }
}
