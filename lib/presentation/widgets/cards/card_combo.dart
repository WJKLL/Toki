// lib/presentation/widgets/cards/card_combo.dart
// 编号：C-28 组合大卡片（v1.14.0 登记，PROJECT_SPEC §5）
// 职责：大卡片容器包裹两个子块 —— ①小课表（红卡 #a01，含「查看全部」按钮 #a02）
//       ②今日剩余环形仪表盘（标题「今日剩余」）。
// 布局：竖屏全宽；横屏为右栏（与 C-27 摘要区等高）。内部 Row 左右两列 Expanded。
// 样式：大容器 surfaceContainerLow + 细边框 + 圆角 15；小课表品牌红 #DA2828 白字；
//       今日剩余环 surfaceContainerHigh + 环形进度（CustomPainter）+ 深浅色自适应。
// 性能：纯静态（const 数据）；环由 CustomPainter 绘制（静态，零 ticker）。
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/course.dart';
import '../c32_ring_progress.dart';
import '../../../domain/entities/home_card.dart';
import '../../features/home/p05_activity_editor.dart'
    deferred as editor; // #a20
import '../../providers/course_provider.dart';
import '../../providers/daily_activity_provider.dart';
import '../../providers/drag_active_provider.dart';

/// 品牌红（小课表卡背景 / 查看全部按钮文字，深浅色一致）。
const Color _brandRed = Color(0xFFDA2828);

/// C-28 组合大卡片（小课表 + 今日剩余环形仪表盘）。
/// v1.21.x：提升为 Stateful —— 每分钟 invalidate 三个时间派生
///   （今日剩余 / 当前课程 / 下一节课），两半卡随派生重建自动联动
///   （仅 invalidate、无 setState，静止零 ticker）。
class C28ComboCard extends ConsumerStatefulWidget {
  const C28ComboCard({super.key, required this.data});

  final ComboCardData data;

  @override
  ConsumerState<C28ComboCard> createState() => _C28ComboCardState();
}

class _C28ComboCardState extends ConsumerState<C28ComboCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (Timer _) {
      // v1.23.0:拖拽排序进行中 → 跳过本轮(等效暂停,结束自动恢复)。
      if (ref.read(dragActiveProvider)) return;
      // 派生 provider 内部用 DateTime.now() 现算,需 invalidate 才取新时间。
      ref.invalidate(todayRemainingProvider);
      ref.invalidate(currentClassProvider);
      ref.invalidate(nextClassProvider);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colors.outline.withValues(alpha: 0.5)),
      ),
      // v1.14.2：用 start（子卡顶部对齐、各自 intrinsic 高度）—— v1.14.1 的
      //   IntrinsicHeight 在竖屏 ListView（unbounded 高度）内触发 native 崩溃；
      //   stretch 在无界高度下也会布局异常，故用 start 保持稳定。
      // v1.19.1：两卡改用固定高度 Row（SizedBox + stretch）保证左右等宽等高，
      //   修复竖屏下「今日剩余」卡与左课程表宽度不一致（_RemainingRing 为
      //   Stack 时 loose fit 破坏宽度约束）。
      child: SizedBox(
        height: 172,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Expanded(child: _ScheduleCard()),
            const SizedBox(width: 12),
            Expanded(child: _RemainingRing(widget.data)),
          ],
        ),
      ),
    );
  }
}

/// 小课表红卡（#a01，v1.21.x/v1.23.1 改版）：
/// 行序:标题 → 「当前课程」标签(课程名上方,小字) → 课程名(大字整行)
///   → 教室(纯白小字,无红色 emoji) → 下一节课是(小字)。
/// 删除「查看全部」按钮 → **整卡点击跳转大课表** /timetable。
/// 数据:当前课程 currentClassProvider + 下一节 nextClassProvider(每分钟联动)。
class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final List<Course> courses =
        ref.watch(courseListProvider).value ?? const <Course>[];
    final CurrentClass? cur = ref.watch(currentClassProvider);
    final NextClass? next = ref.watch(nextClassProvider);
    const Color white = Color(0xFFFFFFFF);
    final Color whiteSoft = white.withValues(alpha: 0.85);

    // 「当前课程」大字槽(cur 非空 = 进行中课程,含时间表未覆盖态)。
    final bool hasCourse = courses.isNotEmpty;
    final bool inClass = cur != null;
    final String bigName = !hasCourse
        ? ''
        : (inClass ? cur.course.name : '休息中');
    final double bigSize = inClass ? 21 : 16;
    final FontWeight bigWeight = inClass ? FontWeight.w600 : FontWeight.w400;
    // 教室(位置):仅进行中的课程显示,无则省略该行。
    // v1.23.1:去掉 📍 emoji(Android 渲染为红色,与红卡背景融合难读),
    //   改用纯白小字「教室:xxx」。
    final String? location = cur?.course.location;

    // 底部「下一节课是」小字槽。
    final String nextText = !hasCourse
        ? '点击卡片去添加'
        : (next != null
              ? '下一节课是:${next.course.name} ${next.startLabel}'
              : '今天没有更多课了');

    // 行序:标题 → [「当前课程」标签 → 课程名整行 → 教室] → 下一节课是。
    final List<Widget> rows = <Widget>[
      // 顶:标题(小字)。
      MiuixText(
        '📚 小课表',
        style: textStyles.body2.copyWith(fontSize: 13),
        color: whiteSoft,
      ),
    ];
    if (!hasCourse) {
      rows.add(
        const MiuixText(
          '暂无课程',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Color(0xFFFFFFFF),
        ),
      );
      rows.add(
        MiuixText(
          '点击卡片去添加',
          style: textStyles.body2.copyWith(fontSize: 13),
          color: whiteSoft,
        ),
      );
    } else {
      // v1.23.1:「当前课程」标签移到课程名上方(独立小行),
      // 课程名独占整行 → 竖屏窄卡下名字显示更全。
      rows.add(
        MiuixText(
          '当前课程',
          style: textStyles.body2.copyWith(fontSize: 13),
          color: whiteSoft,
        ),
      );
      rows.add(
        MiuixText(
          bigName,
          style: textStyles.body2.copyWith(
            fontSize: bigSize,
            fontWeight: bigWeight,
          ),
          color: white,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      if (inClass && location != null && location.isNotEmpty) {
        rows.add(
          MiuixText(
            '教室:$location',
            style: textStyles.body2.copyWith(fontSize: 13),
            color: whiteSoft,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
      rows.add(
        MiuixText(
          nextText,
          style: textStyles.body2.copyWith(fontSize: 13),
          color: whiteSoft,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 整卡点击 → 大课表(编辑课程/节次时间表都在此页)。
      onTap: () => context.push('/timetable'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _brandRed,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// 今日剩余环形仪表盘（标题「今日剩余」+ 圆环 + 剩余时间 + 截止）。
/// v1.19.0 数据驱动：#a04 圆环 / #a05 剩余文本来自 dailyActivityProvider
///   （todayRemainingProvider select 监听）；#a06 点击 → 懒加载打开编辑窗。
/// v1.21.x：分钟联动上移父卡 C28ComboCard（本组件不再持 Timer）。
class _RemainingRing extends ConsumerStatefulWidget {
  const _RemainingRing(this.data);

  final ComboCardData data;

  @override
  ConsumerState<_RemainingRing> createState() => _RemainingRingState();
}

class _RemainingRingState extends ConsumerState<_RemainingRing> {
  /// 编辑窗懒加载状态（#a20：#a06 点击后 loadLibrary 一次）。
  bool _editorLoaded = false;
  bool _editorOpen = false;

  /// #a06 点击卡片 → 懒加载编辑窗并打开。
  Future<void> _openEditor() async {
    if (!_editorLoaded) {
      await editor.loadLibrary(); // deferred:首次点击才加载
      if (!mounted) return;
      _editorLoaded = true;
    }
    setState(() => _editorOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    // 精确监听：只订阅当日剩余(其它天变化不重建)。
    final TodayRemaining? rem = ref.watch(todayRemainingProvider);

    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        MiuixText(
          widget.data.remainingTitle,
          style: textStyles.body2,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 5),
        // #a04 圆环（RepaintBoundary 隔离:父级重绘不触发圆环）。
        // 小米运动/健康粗环:浅轨道整圈 + 主色进度弧(12点顺时针,整圈填满→缩短)。
        // v1.26.0:环 64→60、间距 8→6→5 —— 高行高字体(Ahem/无障碍)下
        //   内容区溢出 10px 的余量修正(真机观感几乎不变)。
        RepaintBoundary(
          child: CustomPaint(
            size: const Size.square(60),
            painter: RingProgressPainter(
              progress: rem?.ratio ?? 0,
              color: colors.primary,
              backgroundColor: colors.primary.withValues(alpha: 0.14),
            ),
          ),
        ),
        const SizedBox(height: 5),
        // #a05 剩余时间文本（未启用/时段外归零）。
        MiuixText(
          rem?.leftText ?? '-- h -- m',
          style: textStyles.title3,
          color: colors.onSurface,
        ),
        const SizedBox(height: 2),
        MiuixText(
          rem == null || rem.activity.isEnabled
              ? (rem?.deadlineText ?? widget.data.remainingDeadline)
              : '今天未启用',
          style: textStyles.body2,
          color: colors.onSurfaceVariantSummary,
        ),
      ],
    );

    // v1.19.1：Stack loose fit 会让宽度收缩到内容,破坏与左卡等宽;
    //   Positioned.fill 强制内容卡填满 Row 的 Expanded(等宽);编辑器为
    //   非定位 child,保持自身 shrink(不参与撑开)。
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openEditor,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: content,
              ),
            ),
          ),
          // #a06/#a20:编辑窗(懒加载后挂载;show=false 时零布局)。
          if (_editorLoaded)
            editor.ActivityEditor(
              show: _editorOpen,
              // 系统返回 / 点遮罩 → 关闭浮层(Bug 修复:此前未接导致关不掉)。
              onDismissRequest: () {
                if (mounted) setState(() => _editorOpen = false);
              },
              onDismissFinished: () {
                if (mounted) setState(() => _editorOpen = false);
              },
            ),
        ],
      ),
    );
  }
}
