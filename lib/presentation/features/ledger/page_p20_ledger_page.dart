// lib/presentation/features/ledger/page_p20_ledger_page.dart
// 编号：P-20 记账一级页（v1.50.0，一级页 · 底栏「记账」）
// 说明：单月视图 —— C-49 月份导航切换月份，顶部 C-46 汇总卡（支出/收入/结余），
//   主体按日分组的流水列表；右下 C-24 毛玻璃 FAB「记一笔」。
//   「记一笔」为底部 sheet（与待办 P-10 新建任务同交互）：类型（支出/收入）
//   → 金额 → 分类（C-47 一级网格 + 二级细分）→ 备注 → 日期（C-43）。
//   - 视觉与 P-10 待办页 1:1 对齐（C-25 毛玻璃顶栏 + C-26 更多菜单 +
//     CardShadow radius 16 + MiuixCard 列表卡 + 右下 FAB）；
//   - 金额一律「分」为单位 int，输入解析走 _parseCents；
//   - 二级分类归并到一级统计（见 ledger_providers.computeMonthStats）。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifecycle/app_lifecycle_controller.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glow_tab_row.dart';
import '../../../core/widgets/ledger_icons.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../../domain/entities/ledger_category.dart';
import '../../../domain/entities/ledger_entry.dart';
import '../../providers/ledger_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c24_frosted_fab.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/c43_date_navigation.dart';
import '../../widgets/c46_ledger_entry_card.dart';
import '../../widgets/c47_category_picker.dart';
import '../../widgets/c49_month_navigation.dart';
import '../../widgets/cards/card_shell.dart';

/// P-20 记账一级页。
class PageP20LedgerPage extends ConsumerStatefulWidget {
  const PageP20LedgerPage({super.key});

  @override
  ConsumerState<PageP20LedgerPage> createState() => _PageP20LedgerPageState();
}

class _PageP20LedgerPageState extends ConsumerState<PageP20LedgerPage>
    with AutomaticKeepAliveClientMixin<PageP20LedgerPage> {
  @override
  bool get wantKeepAlive => true;

  /// 顶栏折叠滚动行为。
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  // ── 记一笔 / 编辑 sheet 状态 ──
  bool _sheetOpen = false;

  /// 正在编辑的账目 id（null = 新增）。
  String? _editId;

  LedgerKind _kind = LedgerKind.expense;

  /// 一级分类 id（空 = 未选）。
  String _categoryId = '';

  /// 二级分类 id（空 = 未细分）。
  String _subCategoryId = '';

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  /// 账目日期（仅日期部分）。
  late DateTime _date = _today();

  /// 账目时刻（时/分；日期取自 _date）。
  int _hour = DateTime.now().hour;
  int _minute = DateTime.now().minute;

  /// 删除确认目标 / 长按菜单目标。
  LedgerEntry? _deleteTarget;
  LedgerEntry? _menuFor;

  /// 月度预算设置弹窗（v1.50.1，首页 C-51 卡片口径依赖）。
  bool _budgetOpen = false;
  final TextEditingController _budgetCtrl = TextEditingController();

  static DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    // S-24 复位订阅（后台 ≥15s 复位时收拢本页全部弹层）。
    AppLifecycleController.instance.addListener(_onAppReset);
  }

  void _onAppReset() {
    if (!mounted) return;
    if (_sheetOpen ||
        _deleteTarget != null ||
        _menuFor != null ||
        _budgetOpen) {
      setState(() {
        _sheetOpen = false;
        _editId = null;
        _deleteTarget = null;
        _menuFor = null;
        _budgetOpen = false;
      });
    }
  }

  @override
  void dispose() {
    AppLifecycleController.instance.removeListener(_onAppReset);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  // ── 表单 ──────────────────────────────────────────────────

  void _openAdd() {
    setState(() {
      _editId = null;
      _kind = LedgerKind.expense;
      _categoryId = '';
      _subCategoryId = '';
      _amountCtrl.clear();
      _noteCtrl.clear();
      _date = _today();
      final DateTime now = DateTime.now();
      _hour = now.hour;
      _minute = now.minute;
      _sheetOpen = true;
    });
  }

  void _openEdit(LedgerEntry e) {
    final Map<String, LedgerCategory> map = ref.read(ledgerCategoryMapProvider);
    final LedgerCategory? cat = map[e.categoryId];
    setState(() {
      _editId = e.id;
      _kind = e.kind == LedgerKind.transfer ? LedgerKind.expense : e.kind;
      if (cat != null && cat.parentId.isNotEmpty) {
        _categoryId = cat.parentId;
        _subCategoryId = cat.id;
      } else {
        _categoryId = e.categoryId;
        _subCategoryId = '';
      }
      _amountCtrl.text = _amountText(e.amountCents);
      _noteCtrl.text = e.note;
      _date = DateTime(e.date.year, e.date.month, e.date.day);
      _hour = e.date.hour;
      _minute = e.date.minute;
      _sheetOpen = true;
    });
  }

  void _closeSheet() {
    setState(() => _sheetOpen = false);
  }

  /// 分 → 输入框文本（不带千分位）。
  static String _amountText(int cents) =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  /// 输入文本 → 分（无效返回 null）。
  static int? _parseCents(String raw) {
    final String s = raw.trim().replaceAll(',', '').replaceAll('¥', '');
    if (s.isEmpty) return null;
    final double? v = double.tryParse(s);
    if (v == null || v <= 0 || v > 99999999) return null;
    return (v * 100).round();
  }

  Future<void> _saveForm() async {
    final int? cents = _parseCents(_amountCtrl.text);
    if (cents == null) {
      showMiniToast(context, '请输入有效金额');
      return;
    }
    if (_categoryId.isEmpty) {
      showMiniToast(context, '请选择分类');
      return;
    }
    final String catId = _subCategoryId.isNotEmpty
        ? _subCategoryId
        : _categoryId;
    final DateTime when = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _hour,
      _minute,
    );
    final LedgerEntriesNotifier notifier = ref.read(
      ledgerEntriesProvider.notifier,
    );
    final String? editId = _editId;
    if (editId == null) {
      await notifier.add(
        kind: _kind,
        amountCents: cents,
        categoryId: catId,
        date: when,
        note: _noteCtrl.text,
      );
    } else {
      final LedgerEntry? cur = _findEntry(editId);
      if (cur != null) {
        await notifier.updateEntry(
          cur.copyWith(
            kind: _kind,
            amountCents: cents,
            categoryId: catId,
            date: when,
            note: _noteCtrl.text.trim(),
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
    if (!mounted) return;
    _closeSheet();
    showMiniToast(context, editId == null ? '已记账' : '已保存');
  }

  LedgerEntry? _findEntry(String id) {
    final List<LedgerEntry> list =
        ref.read(ledgerEntriesProvider).value ?? const <LedgerEntry>[];
    for (final LedgerEntry e in list) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ── 列表操作 ──────────────────────────────────────────────

  void _askDelete(LedgerEntry e) => setState(() => _deleteTarget = e);

  Future<void> _confirmDelete() async {
    final LedgerEntry? e = _deleteTarget;
    setState(() => _deleteTarget = null);
    if (e == null) return;
    await ref.read(ledgerEntriesProvider.notifier).remove(e.id);
    if (mounted) showMiniToast(context, '已删除');
  }

  @override
  Widget build(BuildContext context) {
    // PERF-A：一级页保活（切 Tab 零重建）。
    super.build(context);
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '记账',
        largeTitle: '记账',
        actions: <Widget>[
          _budgetAction(context),
          const C26MoreMenu(),
        ],
        scrollBehavior: _collapse,
      ),
      content: (padding) {
        final Widget list = ListView(
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(
            top: 12 + padding.top,
            bottom: 24 + throughInset,
          ),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: C49MonthNavigation(
                month: ref.watch(ledgerMonthProvider),
                onChanged: (DateTime m) =>
                    ref.read(ledgerMonthProvider.notifier).setMonth(m),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _summaryCard(colors),
            ),
            const SizedBox(height: 16),
            ..._buildGroups(colors),
          ],
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
                      child: ColoredBox(color: colors.surface, child: list),
                    ),
                  ),
                ],
              ),
              _buildEntrySheet(colors),
              _buildBudgetDialog(colors),
              _buildMenuDialog(colors),
              _buildDeleteDialog(colors),
              // 记一笔 FAB（C-24 毛玻璃，与首页/待办页同款）。
              Positioned.fill(
                child: C24FrostedFab(
                  buttonKey: const ValueKey('ledger.fab'),
                  onPressed: _openAdd,
                  child: MiuixIcon(
                    vector: appIcon('add'),
                    size: 24,
                    tint: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 月度汇总卡 ────────────────────────────────────────────

  Widget _summaryCard(MiuixColors colors) {
    final LedgerMonthStats stats = ref.watch(ledgerMonthStatsProvider);
    return CardShadow(
      radius: 16,
      child: MiuixCard(
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _summaryColumn(
                colors,
                '支出',
                stats.expenseCents,
                colors.onSurface,
              ),
            ),
            _summaryDivider(colors),
            Expanded(
              child: _summaryColumn(
                colors,
                '收入',
                stats.incomeCents,
                C46LedgerEntryCard.kIncomeColor,
              ),
            ),
            _summaryDivider(colors),
            Expanded(
              child: _summaryColumn(
                colors,
                '结余',
                stats.balanceCents,
                stats.balanceCents < 0
                    ? colors.error
                    : (stats.balanceCents > 0
                          ? C46LedgerEntryCard.kIncomeColor
                          : colors.onSurfaceVariantSummary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryColumn(
    MiuixColors colors,
    String label,
    int cents,
    Color valueColor,
  ) {
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiuixText(label, fontSize: 12, color: colors.onSurfaceVariantSummary),
        const SizedBox(height: 6),
        MiuixText(
          formatCents(cents),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ts.title3.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _summaryDivider(MiuixColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: ColoredBox(
      color: colors.dividerLine,
      child: const SizedBox(width: 0.5, height: 28),
    ),
  );

  // ── 流水列表（按日分组）────────────────────────────────────

  List<Widget> _buildGroups(MiuixColors colors) {
    final List<LedgerDayGroup> groups = ref.watch(ledgerDayGroupsProvider);
    if (groups.isEmpty) return <Widget>[_buildEmpty(colors)];
    final Map<String, LedgerCategory> map = ref.watch(
      ledgerCategoryMapProvider,
    );
    final DateTime now = DateTime.now();
    final List<Widget> out = <Widget>[];
    for (int gi = 0; gi < groups.length; gi++) {
      final LedgerDayGroup g = groups[gi];
      if (gi > 0) out.add(const SizedBox(height: 6));
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: <Widget>[
              MiuixText(
                g.label(now),
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              const Spacer(),
              if (g.expenseCents > 0)
                MiuixText(
                  '支出 ${formatCents(g.expenseCents)}',
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
              if (g.expenseCents > 0 && g.incomeCents > 0)
                const SizedBox(width: 10),
              if (g.incomeCents > 0)
                MiuixText(
                  '收入 ${formatCents(g.incomeCents)}',
                  fontSize: 11,
                  color: C46LedgerEntryCard.kIncomeColor,
                ),
            ],
          ),
        ),
      );
      for (final LedgerEntry e in g.entries) {
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: C46LedgerEntryCard(
              entry: e,
              category: map[e.categoryId],
              onTap: () => _openEdit(e),
              onLongPress: () => setState(() => _menuFor = e),
            ),
          ),
        );
      }
    }
    return out;
  }

  /// 空态（与待办页同款）。
  Widget _buildEmpty(MiuixColors colors) {
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      child: Column(
        children: <Widget>[
          MiuixIcon(
            vector: ledgerIcon('salary'),
            size: 44,
            tint: colors.outline.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          MiuixText(
            '这个月还没有账目',
            style: ts.body1,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 4),
          MiuixText(
            '点右下角 + 记一笔',
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  // ── 记一笔 / 编辑 sheet ───────────────────────────────────

  Widget _buildEntrySheet(MiuixColors colors) {
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final bool editing = _editId != null;
    final List<LedgerCategory> all =
        ref.watch(ledgerCategoriesProvider).value ?? const <LedgerCategory>[];
    final List<LedgerCategory> tops = topCategoriesOf(all, _kind);
    final List<LedgerCategory> subs = _categoryId.isEmpty
        ? const <LedgerCategory>[]
        : subCategoriesOf(all, _categoryId);

    // v1.50.2（横屏键盘空白修复 v2）：鸿蒙横屏键盘弹起时 Flutter 视图**整体
    //   缩小**（overlay 高度 = 屏幕高 − 键盘高，viewInsets 归零），卡片按自然
    //   高度贴底即正好落在键盘上沿 —— 上一版强行给内容区设固定高度，反而在
    //   卡片内部撑出一片底部空白。此处改为：内容区保持自然高度，横屏时把
    //   MediaQuery.viewInsets 归零（Miuix 会把它加进**卡片背景内部**，非 0
    //   时卡片底边向下延伸出空白带；视图已缩小时该值本就为 0，归零幂等）。
    final MediaQueryData mq = MediaQuery.of(context);
    final bool landscape = mq.size.width > mq.size.height;

    final Widget sheetContent = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 类型（支出 / 收入；转账一期不开放入口）。
              GlowTabRow(
                tabs: const <String>['支出', '收入'],
                selectedTabIndex: _kind == LedgerKind.expense ? 0 : 1,
                onTabSelected: (int i) => setState(() {
                  _kind = i == 0 ? LedgerKind.expense : LedgerKind.income;
                  _categoryId = '';
                  _subCategoryId = '';
                }),
              ),
              const SizedBox(height: 16),
              MiuixTextField(
                key: const ValueKey<String>('ledger.amount'),
                controller: _amountCtrl,
                label: '金额',
                singleLine: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: !editing,
                textStyle: ts.title2.copyWith(color: colors.onSurface),
              ),
              const SizedBox(height: 16),
              MiuixText(
                '分类',
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 10),
              C47CategoryPicker(
                categories: tops,
                selectedId: _categoryId,
                onSelected: (LedgerCategory c) => setState(() {
                  _categoryId = c.id;
                  _subCategoryId = '';
                }),
              ),
              if (subs.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                C47SubCategoryPicker(
                  categories: subs,
                  selectedId: _subCategoryId,
                  onSelected: (LedgerCategory c) =>
                      setState(() => _subCategoryId = c.id),
                ),
              ],
              const SizedBox(height: 16),
              MiuixTextField(
                key: const ValueKey<String>('ledger.note'),
                controller: _noteCtrl,
                label: '备注（可选）',
                singleLine: true,
              ),
              const SizedBox(height: 16),
              MiuixText(
                '日期',
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 6),
              C43DateNavigation(
                value: _date,
                onChanged: (DateTime d) => setState(() => _date = d),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  const Spacer(),
                  MiuixButton(onPressed: _closeSheet, child: const Text('取消')),
                  const SizedBox(width: 12),
                  MiuixButton(
                    key: const ValueKey<String>('ledger.save'),
                    onPressed: _saveForm,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: Text(editing ? '保存' : '记下'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

    final Widget sheet = MiuixOverlayBottomSheet(
      show: _sheetOpen,
      title: editing ? '编辑账目' : '记一笔',
      onDismissRequest: _closeSheet,
      content: sheetContent,
    );
    if (!landscape) return sheet;
    return MediaQuery(
      data: mq.copyWith(viewInsets: EdgeInsets.zero),
      child: sheet,
    );
  }

  // ── 月度预算设置（v1.50.1）────────────────────────────────

  /// 顶栏「预算」入口（裸图标，与待办页回收站入口同语言）。
  Widget _budgetAction(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return GestureDetector(
      key: const ValueKey<String>('ledger.budget'),
      behavior: HitTestBehavior.opaque,
      onTap: _openBudget,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: MiuixIcon(
          vector: appIcon('tune'),
          size: 20,
          tint: colors.onSurfaceVariantActions,
        ),
      ),
    );
  }

  void _openBudget() {
    final int cur = ref.read(ledgerBudgetProvider);
    setState(() {
      _budgetCtrl.text = cur > 0 ? _amountText(cur) : '';
      _budgetOpen = true;
    });
  }

  Future<void> _saveBudget() async {
    final String raw = _budgetCtrl.text.trim();
    final int cents = raw.isEmpty ? 0 : (_parseCents(raw) ?? 0);
    await ref.read(ledgerBudgetProvider.notifier).setBudget(cents);
    if (!mounted) return;
    setState(() => _budgetOpen = false);
    showMiniToast(
      context,
      cents > 0 ? '月度预算已设为 ${formatCents(cents)}' : '已清除月度预算',
    );
  }

  Widget _buildBudgetDialog(MiuixColors colors) {
    return MiuixOverlayDialog(
      show: _budgetOpen,
      title: '月度预算',
      onDismissRequest: () => setState(() => _budgetOpen = false),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MiuixText(
              '首页记账卡：本月剩余 = 预算 + 本月收入 − 本月支出',
              fontSize: 12,
              color: colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 12),
            MiuixTextField(
              key: const ValueKey<String>('ledger.budgetInput'),
              controller: _budgetCtrl,
              label: '月度预算金额（留空 = 不设预算）',
              singleLine: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                MiuixButton(
                  onPressed: () => setState(() => _budgetOpen = false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                MiuixButton(
                  key: const ValueKey<String>('ledger.budgetSave'),
                  onPressed: _saveBudget,
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 长按操作菜单 ──────────────────────────────────────────

  Widget _buildMenuDialog(MiuixColors colors) {
    final LedgerEntry? e = _menuFor;
    return MiuixOverlayDialog(
      show: e != null,
      title: e == null ? '' : _entryTitle(e),
      onDismissRequest: () => setState(() => _menuFor = null),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            GestureDetector(
              key: const ValueKey<String>('ledger.menu.edit'),
              behavior: HitTestBehavior.opaque,
              onTap: e == null
                  ? null
                  : () {
                      setState(() => _menuFor = null);
                      _openEdit(e);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: MiuixText(
                  '编辑账目',
                  fontSize: 14,
                  color: colors.onSurface,
                ),
              ),
            ),
            GestureDetector(
              key: const ValueKey<String>('ledger.menu.delete'),
              behavior: HitTestBehavior.opaque,
              onTap: e == null
                  ? null
                  : () {
                      setState(() => _menuFor = null);
                      _askDelete(e);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: MiuixText(
                  '删除账目',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _entryTitle(LedgerEntry e) {
    final LedgerCategory? c = ref.read(ledgerCategoryMapProvider)[e.categoryId];
    return c?.name ?? (e.isTransfer ? '转账' : '未分类');
  }

  // ── 删除确认 ──────────────────────────────────────────────

  Widget _buildDeleteDialog(MiuixColors colors) {
    final LedgerEntry? e = _deleteTarget;
    return MiuixOverlayDialog(
      show: e != null,
      title: '删除账目',
      onDismissRequest: () => setState(() => _deleteTarget = null),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MiuixText(
              e == null
                  ? ''
                  : '「${_entryTitle(e)} '
                        '${formatSignedCents(e.kind, e.amountCents)}」将被永久删除。',
              fontSize: 14,
              color: colors.onSurface,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                MiuixButton(
                  onPressed: () => setState(() => _deleteTarget = null),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                MiuixButton(
                  key: const ValueKey<String>('ledger.confirmDelete'),
                  onPressed: _confirmDelete,
                  colors: MiuixButtonColors(
                    color: colors.error,
                    disabledColor: colors.error.withValues(alpha: 0.4),
                    contentColor: colors.onError,
                    disabledContentColor: colors.onError,
                  ),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
