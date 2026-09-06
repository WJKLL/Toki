// lib/presentation/features/todo/page_p10_todo_page.dart
// 编号：P-10 待办时间轴主页（v1.43.0，一级页 · 底栏「待办」首页左边）
// 说明：单日视图（HTML 风格）—— C-43 日期导航切换选中日期，主体只显示
//   该日**未完成**任务；已完成(归档)任务在回收站 P-12。
// 阶段1：C-44 任务卡（完成✓归档 / 点按编辑 / 长按删除确认）+ FAB 新建/
//   编辑 bottom sheet（标题/日期(C-43)/优先级三档）。
// 阶段2：右上回收站入口(/todo/archived P-12)；UI：左上无占位按钮、
//   FAB 毛玻璃与首页 C-24 统一、回收站入口裸图标。
// 阶段6（v1.44.0）：横屏分栏列表+流程图只读预览、卡片点按进流程图编辑器。
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/lifecycle/app_lifecycle_controller.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../../domain/entities/todo_item.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/todo_providers.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/c43_date_navigation.dart';
import '../../widgets/c44_todo_task_card.dart';

/// P-10 待办一级页。
class PageP10TodoPage extends ConsumerStatefulWidget {
  const PageP10TodoPage({super.key});

  @override
  ConsumerState<PageP10TodoPage> createState() => _PageP10TodoPageState();
}

class _PageP10TodoPageState extends ConsumerState<PageP10TodoPage> {
  /// 当前选中日期（仅日期部分；默认今天）。
  late DateTime _selectedDate = _today();

  /// 新增/编辑表单状态（_sheetEditId null = 新增）。
  bool _sheetOpen = false;
  String? _sheetEditId;
  final TextEditingController _titleCtrl = TextEditingController();
  DateTime _formDate = _today();
  int _formPri = 1;

  /// 删除确认弹窗目标（null = 关闭）。
  TodoItem? _deleteTarget;

  /// 长按操作菜单目标（null = 关闭）。
  TodoItem? _menuFor;

  static DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 顶栏折叠滚动行为（顶栏纯蒙版，无页面级快照采样）。
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  /// S-24 复位订阅（后台 ≥15s 复位时收拢本页全部弹层）。
  @override
  void initState() {
    super.initState();
    AppLifecycleController.instance.addListener(_onAppReset);
  }

  /// S-24 后台复位：收起新增/编辑 sheet、删除确认、长按菜单。
  void _onAppReset() {
    if (!mounted) return;
    if (_sheetOpen || _deleteTarget != null || _menuFor != null) {
      setState(() {
        _sheetOpen = false;
        _sheetEditId = null;
        _deleteTarget = null;
        _menuFor = null;
      });
    }
  }

  @override
  void dispose() {
    AppLifecycleController.instance.removeListener(_onAppReset);
    _titleCtrl.dispose();
    super.dispose();
  }

  /// 回收站入口（右上角裸图标,无胶囊背景 —— v1.43.0 UI 统一）。
  Widget _archiveAction(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return GestureDetector(
      key: const ValueKey('todo.archive'),
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/todo/archived'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: MiuixIcon(
          vector: appIcon('delete'),
          size: 20,
          tint: colors.onSurfaceVariantActions,
        ),
      ),
    );
  }

  /// 新建 FAB（右下 Positioned；毛玻璃视觉对齐首页 C-24：Android 13+ 模糊
  /// tint 0.20，其余降级 0.88 表面色；56×56 squircle + 单层阴影）。
  Widget _buildFab(
    BuildContext context,
    MiuixColors colors,
    double throughInset,
  ) {
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    final bool blurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: true,
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    const ShapeBorder shape = MiuixSquircleBorder(cornerRadius: 18);
    Widget inner = Container(
      width: 56,
      height: 56,
      decoration: ShapeDecoration(
        color: colors.surfaceContainerHigh.withValues(
          alpha: blurAllowed ? 0.20 : 0.88,
        ),
        shape: shape,
        shadows: const <BoxShadow>[
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: MiuixIcon(
          vector: appIcon('add'),
          size: 24,
          tint: colors.onSurface,
        ),
      ),
    );
    if (blurAllowed) {
      inner = ClipPath(
        clipper: const ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: inner,
        ),
      );
    }
    return Positioned(
      right: 20,
      bottom: 20 + throughInset,
      child: GestureDetector(
        key: const ValueKey('todo.fab'),
        behavior: HitTestBehavior.opaque,
        onTap: _openAdd,
        child: inner,
      ),
    );
  }

  // ── 新增/编辑表单 ─────────────────────────────────────────

  void _openAdd() {
    setState(() {
      _sheetEditId = null;
      _titleCtrl.clear();
      _formDate = _today();
      _formPri = 1;
      _sheetOpen = true;
    });
  }

  void _openEdit(TodoItem t) {
    setState(() {
      _sheetEditId = t.id;
      _titleCtrl.text = t.title;
      _formDate = DateTime(t.date.year, t.date.month, t.date.day);
      _formPri = t.priority;
      _sheetOpen = true;
    });
  }

  void _closeSheet() {
    setState(() => _sheetOpen = false);
  }

  Future<void> _saveForm() async {
    final String title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      showMiniToast(context, '请输入任务标题');
      return;
    }
    final TodoListNotifier notifier =
        ref.read(todoListProvider.notifier);
    final String? editId = _sheetEditId;
    if (editId == null) {
      await notifier.add(
        title: title,
        date: _formDate,
        priority: _formPri,
      );
    } else {
      final TodoItem? cur = _findTodo(editId);
      if (cur != null) {
        await notifier.updateItem(
          cur.copyWith(
            title: title,
            date: DateTime(_formDate.year, _formDate.month, _formDate.day),
            priority: _formPri,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
    if (mounted) _closeSheet();
  }

  TodoItem? _findTodo(String id) {
    final List<TodoItem> todos =
        ref.read(todoListProvider).value ?? const <TodoItem>[];
    for (final TodoItem t in todos) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ── 任务操作 ─────────────────────────────────────────────

  Future<void> _complete(TodoItem t) async {
    await ref.read(todoListProvider.notifier).complete(t.id);
    if (mounted) {
      showMiniToast(context, '已完成 · ${t.title}');
    }
  }

  void _askMenu(TodoItem t) {
    setState(() => _menuFor = t);
  }

  void _askDelete(TodoItem t) {
    setState(() => _deleteTarget = t);
  }

  Future<void> _confirmDelete() async {
    final TodoItem? t = _deleteTarget;
    setState(() => _deleteTarget = null);
    if (t == null) return;
    await ref.read(todoListProvider.notifier).permanentlyDelete(t.id);
    if (mounted) showMiniToast(context, '已删除 · ${t.title}');
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '待办',
        largeTitle: '待办',
        actions: <Widget>[
          // v1.43.0 UI：回收站入口(裸图标) + 更多菜单；左上角不放占位假按钮。
          _archiveAction(context),
          const C26MoreMenu(),
        ],
        scrollBehavior: _collapse,
      ),
      content: (padding) {
        final Widget page = ListView(
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(
            top: 12 + padding.top,
            bottom: 24 + throughInset,
          ),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: C43DateNavigation(
                value: _selectedDate,
                onChanged: (DateTime d) => setState(() => _selectedDate = d),
              ),
            ),
            const SizedBox(height: 16),
            ..._buildTaskArea(context),
          ],
        );
        final Widget listWithBg = ColoredBox(color: colors.surface, child: page);
        // 内容 + 悬浮 FAB（右下，避让底栏/手势区）。
        return Material(
          type: MaterialType.transparency,
          // 与首页同款：Column 直接作 Stack 子项撑满约束
          //（Positioned.fill 包裹会使 Stack 无撑高子项 → 尺寸 0）。
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
              // 新增/编辑 bottom sheet + 长按菜单 + 删除确认（show 驱动零开销）。
              _buildEditSheet(colors),
              _buildMenuDialog(colors),
              _buildDeleteDialog(colors),
              // 新建 FAB：与首页 C-24 同款毛玻璃视觉（Positioned 定位可控）。
              _buildFab(context, colors, throughInset),
            ],
          ),
        );
      },
    );
  }

  // ── 任务列表区 ────────────────────────────────────────────

  List<Widget> _buildTaskArea(BuildContext context) {
    final List<TodoItem> todos =
        ref.watch(todoListProvider).value ?? const <TodoItem>[];
    final List<TodoItem> dayTodos = <TodoItem>[
      for (final TodoItem t in todos)
        if (!t.isCompleted && _sameDay(t.date, _selectedDate)) t,
    ]..sort((TodoItem a, TodoItem b) {
        final int byP = b.priority.compareTo(a.priority);
        return byP != 0 ? byP : a.createdAt.compareTo(b.createdAt);
      });

    if (dayTodos.isEmpty) {
      return <Widget>[_buildEmpty(context)];
    }
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: MiuixText(
          '${dayTodos.length} 个任务',
          fontSize: 12,
          color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
        ),
      ),
      for (final TodoItem t in dayTodos)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: C44TodoTaskCard(
            todo: t,
            // v1.44.0：点按进入流程图编辑器。
            onOpen: () => context.push('/todo/${t.id}'),
            onComplete: () => _complete(t),
            onMenuRequest: () => _askMenu(t),
          ),
        ),
    ];
  }

  /// 空态。
  Widget _buildEmpty(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      child: Column(
        children: <Widget>[
          MiuixIcon(
            vector: appIcon('tasks'),
            size: 44,
            tint: colors.outline.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          MiuixText(
            '这一天还没有任务',
            style: ts.body1,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 4),
          MiuixText(
            '点右下角 + 新建任务',
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  // ── 新增/编辑表单 ─────────────────────────────────────────

  Widget _buildEditSheet(MiuixColors colors) {
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final bool editing = _sheetEditId != null;
    return MiuixOverlayBottomSheet(
      show: _sheetOpen,
      title: editing ? '编辑任务' : '新建任务',
      onDismissRequest: _closeSheet,
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MiuixTextField(
                key: const ValueKey('todo.title'),
                controller: _titleCtrl,
                label: '任务标题',
                singleLine: true,
                autofocus: !editing,
              ),
              const SizedBox(height: 14),
              MiuixText(
                '截止日期',
                style: ts.body2,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 6),
              C43DateNavigation(
                value: _formDate,
                onChanged: (DateTime d) => setState(() => _formDate = d),
              ),
              const SizedBox(height: 14),
              MiuixText(
                '优先级',
                style: ts.body2,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (int i = 0; i < 3; i++)
                    _priChip(colors, i),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  const Spacer(),
                  MiuixButton(
                    onPressed: _closeSheet,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  MiuixButton(
                    onPressed: _saveForm,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: Text(editing ? '保存' : '添加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 优先级胶囊（低/中/高；选中浅主色底 + 主色文字，同工具参数 chip 语言）。
  Widget _priChip(MiuixColors colors, int pri) {
    final bool selected = _formPri == pri;
    return GestureDetector(
      onTap: () => setState(() => _formPri = pri),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.14)
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? Border.all(color: colors.primary, width: 1.2)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: C44TodoTaskCard.priorityColor(pri),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            MiuixText(
              kTodoPriorityLabels[pri],
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? colors.primary : colors.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  // ── 长按操作菜单 ─────────────────────────────────────────

  Widget _buildMenuDialog(MiuixColors colors) {
    final TodoItem? t = _menuFor;
    return MiuixOverlayDialog(
      show: t != null,
      title: t?.title ?? '',
      onDismissRequest: () => setState(() => _menuFor = null),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            GestureDetector(
              key: const ValueKey('todo.menu.edit'),
              behavior: HitTestBehavior.opaque,
              onTap: t == null
                  ? null
                  : () {
                      setState(() => _menuFor = null);
                      _openEdit(t);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: MiuixText('编辑任务', fontSize: 14, color: colors.onSurface),
              ),
            ),
            GestureDetector(
              key: const ValueKey('todo.menu.delete'),
              behavior: HitTestBehavior.opaque,
              onTap: t == null
                  ? null
                  : () {
                      setState(() => _menuFor = null);
                      _askDelete(t);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: MiuixText(
                  '删除任务',
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

  // ── 删除确认 ──────────────────────────────────────────────

  Widget _buildDeleteDialog(MiuixColors colors) {
    final TodoItem? t = _deleteTarget;
    return MiuixOverlayDialog(
      show: t != null,
      title: '删除任务',
      onDismissRequest: () => setState(() => _deleteTarget = null),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MiuixText(
              '「${t?.title ?? ''}」将被永久删除，无法在回收站找回。',
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
                  key: const ValueKey('todo.confirmDelete'),
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
