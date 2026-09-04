// lib/presentation/widgets/cards/card_class_countdown.dart
// 编号:A-04 · C-33 课程倒计时卡片(v1.21.0;v1.22.0 网格 small 档紧凑横排)
// 说明:首页网格 small(1×1,高 104)卡 —— 基于当前时间 × 全局节次时间表
//   (S-02) × 今日课表(S-15,单双周/weeks 过滤)显示「正在上的课」:
//   标题行 + [环 40 | 文本列(课程名/剩余 %/节次时段)],上课满环→下课空环;
//   进度变化 500-800ms 平滑补间;动效开关(blurEnabled)关闭 → 跳变(低性能档);
//   三态:上课中 / 📚 空闲 / 该节次未设时间(点击跳大课表设置)。
// 性能:动画仅圆环 RepaintBoundary 重绘;静止零 ticker;每分钟 invalidate 刷新。
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/home_card.dart';
import '../../providers/course_provider.dart';
import '../../providers/drag_active_provider.dart';
import '../../providers/settings_providers.dart';
import '../c32_ring_progress.dart';

/// A-04 课程倒计时卡(数据实时来自 currentClassProvider)。
class C33ClassCountdownCard extends ConsumerStatefulWidget {
  const C33ClassCountdownCard({super.key, required this.data});

  final ClassCountdownCardData data;

  @override
  ConsumerState<C33ClassCountdownCard> createState() =>
      _C33ClassCountdownCardState();
}

class _C33ClassCountdownCardState extends ConsumerState<C33ClassCountdownCard> {
  /// 每分钟刷新(切后台自动停,回前台重建继续)。
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (Timer _) {
      // v1.23.0:拖拽排序进行中 → 跳过本轮(结束自动恢复)。
      if (ref.read(dragActiveProvider)) return;
      // currentClassProvider 内部用 DateTime.now() 现算,需 invalidate 才重算。
      ref.invalidate(currentClassProvider);
      if (mounted) setState(() {});
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
    final CurrentClass? cc = ref.watch(currentClassProvider);
    // 动效开关(= 原毛玻璃开关):关闭 → 低性能档,动画直接跳变。
    final bool animate = ref.watch(
      appSettingsProvider.select((s) => s.blurEnabled),
    );

    final bool canFixTime = cc?.timeMissing ?? false;
    return MiuixCard(
      insideMargin: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      // 节次未设时间 → 点击跳大课表页设置。
      onPressed: canFixTime ? () => context.push('/timetable') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MiuixText(
            widget.data.title,
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // 圆环(小卡紧凑档 40;仅环形区动画重绘)。
                RepaintBoundary(
                  child: C32AnimatedRing(
                    progress: (cc == null || cc.timeMissing) ? 0 : cc.ratio,
                    color: colors.primary,
                    backgroundColor: colors.primary.withValues(alpha: 0.14),
                    size: 40,
                    animate: animate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildTextColumn(cc, colors)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 右侧文本列(最多三行小字;按态切换内容)。
  Widget _buildTextColumn(CurrentClass? cc, MiuixColors colors) {
    if (cc == null) {
      // 空闲:当前不在任何启用节次内,或该节次无课。
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MiuixText(
            '📚 空闲',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          const SizedBox(height: 1),
          MiuixText(
            '暂无课程',
            fontSize: 11,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      );
    }
    if (cc.timeMissing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MiuixText(
            cc.course.name,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          MiuixText('该节次未设置时间', fontSize: 11, color: colors.primary),
          const SizedBox(height: 1),
          MiuixText(
            '点击进入大课表设置',
            fontSize: 10,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MiuixText(
          cc.course.name,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        // 主文本:剩余百分比(与圆环一致)。
        MiuixText(
          cc.leftText,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: colors.primary,
        ),
        const SizedBox(height: 1),
        MiuixText(
          '${cc.periodLabel} · ${cc.spanStartLabel}-${cc.spanEndLabel}',
          fontSize: 10,
          color: colors.onSurfaceVariantSummary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
