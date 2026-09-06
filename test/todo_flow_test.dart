// test/todo_flow_test.dart
// v1.43.0（P-10）：待办单日视图流程 —— 底栏切「待办」→ 空态 → FAB 新建
//   （标题/优先级）→ 当日列表出现 → 完成✓ 归档（列表移除、归档落盘）→
//   直接删除（确认后移除且归档无残留）。
// 依赖注入：todoRepositoryProvider = TodoRepositoryImpl(内存 prefs)。
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiangjugong/data/repositories/agreement_repository_impl.dart';
import 'package:xiangjugong/data/repositories/settings_repository_impl.dart';
import 'package:xiangjugong/data/repositories/todo_repository_impl.dart';
import 'package:xiangjugong/domain/repositories/agreement_repository.dart';
import 'package:xiangjugong/main.dart';
import 'package:xiangjugong/presentation/providers/agreement_provider.dart';
import 'package:xiangjugong/presentation/providers/settings_providers.dart';
import 'package:xiangjugong/presentation/providers/todo_providers.dart';
import 'package:xiangjugong/presentation/widgets/c44_todo_task_card.dart';

void main() {
  Future<TodoRepositoryImpl> pumpApp(WidgetTester tester) async {
    // 手机竖屏（窄屏底栏）。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'user_agreement_accepted': true,
      'user_agreement_version': kAgreementVersion,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsRepositoryImpl repository = SettingsRepositoryImpl(prefs);
    final TodoRepositoryImpl todoRepo = TodoRepositoryImpl(prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          agreementRepositoryProvider.overrideWithValue(
            AgreementRepositoryImpl(prefs),
          ),
          todoRepositoryProvider.overrideWithValue(todoRepo),
        ],
        child: const XiangJuGongApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 4)); // 消化初始跳页 S-16 Timer
    return todoRepo;
  }

  /// 切到待办一级页：直接点底栏第 1 项中心（360 宽 3 项均分 → x=60；
  ///   底栏 y 区 744-800 中心 772）—— 绕开 PageView 缓存页顶栏同名文本歧义。
  Future<void> switchTodo(WidgetTester tester) async {
    await tester.tapAt(const Offset(60, 772));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // 兜底：若未切成功，微调 y 再点一次。
    if (find.byKey(const ValueKey('todo.fab')).evaluate().isEmpty) {
      await tester.tapAt(const Offset(60, 756));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
  }

  /// 点当前任务卡的「完成✓」按钮。
  Future<void> tapComplete(WidgetTester tester) async {
    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('todo.complete.'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }

  /// 定位任务标题输入框（MiuixTextField 内的 EditableText）。
  Finder titleField() => find.descendant(
    of: find.byKey(const ValueKey('todo.title')),
    matching: find.byType(EditableText),
  );

  Future<void> settleTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

  /// 经 FAB 新建任务（今日）。
  Future<void> addTodo(WidgetTester tester, String title) async {
    await tester.tap(find.byKey(const ValueKey('todo.fab')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.enterText(titleField(), title);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }

  /// 进入回收站（待办页右上 delete 图标）。
  Future<void> gotoArchive(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('todo.archive')));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    // 回收站页大标题出现（顶栏,与底栏同名无冲突 —— 二级页覆盖 shell）。
    expect(find.text('回收站'), findsWidgets);
  }

  testWidgets('待办流程:新建→当日出现→完成归档→列表移除且归档落盘', (tester) async {
    final TodoRepositoryImpl repo = await pumpApp(tester);
    await switchTodo(tester);

    // FAB 新建：标题 + 高优先级。
    await tester.tap(find.byKey(const ValueKey('todo.fab')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('新建任务'), findsOneWidget, reason: 'FAB 应打开新建表单');
    await tester.enterText(titleField(), '买菜');
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 当日列表出现 C-44 卡。
    expect(find.byType(C44TodoTaskCard), findsOneWidget);
    expect(find.text('买菜'), findsOneWidget);

    // 完成 ✓ → 归档：卡消失 + 归档落盘 1 条 + 待办保留(已完成态)。
    await tapComplete(tester);
    expect(find.byType(C44TodoTaskCard), findsNothing);
    expect(repo.loadArchived().length, 1);
    expect(repo.loadTodos().length, 1);
    expect(repo.loadTodos().single.isCompleted, isTrue);
    await settleTimers(tester);
  });

  testWidgets('待办流程:删除任务(确认)后待办与归档均无残留', (tester) async {
    final TodoRepositoryImpl repo = await pumpApp(tester);
    await switchTodo(tester);

    // 新建一个任务。
    await tester.tap(find.byKey(const ValueKey('todo.fab')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.enterText(titleField(), '要删的');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(C44TodoTaskCard), findsOneWidget);

    // 长按卡片 → 操作菜单 → 删除 → 确认弹窗 → 永久删除。
    await tester.longPress(find.byType(C44TodoTaskCard));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('todo.menu.delete')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('todo.confirmDelete')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.byType(C44TodoTaskCard), findsNothing);
    expect(repo.loadTodos(), isEmpty);
    expect(repo.loadArchived(), isEmpty);
    await settleTimers(tester);
  });

  testWidgets('回收站流程:完成归档 → 回收站出现 → 恢复回到待办', (tester) async {
    final TodoRepositoryImpl repo = await pumpApp(tester);
    await switchTodo(tester);
    await addTodo(tester, '写周报');
    await tapComplete(tester);
    expect(repo.loadArchived().length, 1);

    // 进回收站：条目出现（标题 + 副行）。
    await gotoArchive(tester);
    expect(find.text('写周报'), findsOneWidget);

    // 恢复 → 条目消失、待办恢复未完成。
    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('archive.restore.'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(repo.loadArchived(), isEmpty);
    expect(repo.loadTodos().single.isCompleted, isFalse);
    await settleTimers(tester);
  });

  testWidgets('回收站流程:永久删除(确认)后无任何残留', (tester) async {
    final TodoRepositoryImpl repo = await pumpApp(tester);
    await switchTodo(tester);
    await addTodo(tester, '过期的');
    await tapComplete(tester);

    await gotoArchive(tester);
    expect(find.text('过期的'), findsOneWidget);
    // 永久删除（弹窗确认按钮与标题同名,取后出现的按钮）。
    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('archive.delete.'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('永久删除').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(repo.loadTodos(), isEmpty);
    expect(repo.loadArchived(), isEmpty);
    expect(find.text('回收站是空的'), findsOneWidget);
    await settleTimers(tester);
  });
}
