// === 文件: lib/presentation/widgets/course_reminder_bridge.dart ===
// 编号：v1.36.0 课程提醒 · 常驻桥（挂在 App 顶层 MaterialApp 内，整机生命周期）
// 说明：把真实课表数据驱动到原生提醒（Android；Web 直接空转）：
//   - **到点提醒**：课表/节次/周次变化 → 排「今天剩余 + 明天全部」课程开始
//     闹钟（AlarmManager，App 不在也弹）；闹钟清单持久化 → 开机/兜底重排；
//   - **常驻通知（上课中）**：监听 currentClassProvider —— 上课(非空) →
//     原生前台服务**自治倒计时**（传 endAt + total，原生按墙钟自己刷新）；
//     下课 → 停止；
//   - v1.36.0 定稿：桌面小组件因 MIUI 桌面 RemoteViews 兼容性问题已移除，
//     本桥只服务「到点通知 + 上课常驻通知」。
//   - 本桥自身零 Timer、零周期占用；跨周日次以当前周次近似（打开即重排修正）。
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/reminder/reminder_service.dart';
import '../../domain/entities/class_period.dart';
import '../../domain/entities/course.dart';
import '../providers/course_provider.dart';
import '../providers/settings_providers.dart';

/// 顶层常驻桥：无 UI，纯驱动（return child 透传）。
class CourseReminderBridge extends ConsumerStatefulWidget {
  const CourseReminderBridge({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CourseReminderBridge> createState() =>
      _CourseReminderBridgeState();
}

class _CourseReminderBridgeState extends ConsumerState<CourseReminderBridge> {
  /// 首次 build 完成监听注册与初始排程（ref.listen 必须在 build 内调用）。
  bool _booted = false;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && !_booted) {
      _booted = true;
      // 课表/周次/节次变更 → 重排到点闹钟。
      ref.listen(courseListProvider, (_, _) => _scheduleCourseAlarms());
      ref.listen(scheduleMetaProvider, (_, _) => _scheduleCourseAlarms());
      ref.listen(
        appSettingsProvider.select((s) => s.classPeriods),
        (_, _) => _scheduleCourseAlarms(),
      );
      // 当前课程 → 启停常驻自治通知。
      ref.listen(
        currentClassProvider,
        (_, CurrentClass? next) => _onCurrentClass(next),
      );
      // 课程提醒总开关：关 → 清闹钟 + 停常驻；开 → 重排 + 恢复上课态。
      ref.listen(
        appSettingsProvider.select((s) => s.courseReminderEnabled),
        (_, bool enabled) {
          if (!enabled) {
            unawaited(ReminderService.cancelAllAlarms());
            unawaited(ReminderService.stopCountdown());
          } else {
            _scheduleCourseAlarms();
            _onCurrentClass(ref.read(currentClassProvider));
          }
        },
      );
      // 首帧后初始排程 + 覆盖「启动即在上课」（非 listen 副作用走 postFrame）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!ref.read(appSettingsProvider).courseReminderEnabled) return;
        _scheduleCourseAlarms();
        _onCurrentClass(ref.read(currentClassProvider));
      });
    }
    return widget.child;
  }

  // ── 到点提醒排程：今天剩余 + 明天全部 ─────────────────────────

  void _scheduleCourseAlarms() {
    final List<Course> courses =
        ref.read(courseListProvider).value ?? const <Course>[];
    final meta = ref.read(scheduleMetaProvider).value;
    if (courses.isEmpty || meta == null) return;
    final List<ClassPeriod> periods = ref.read(appSettingsProvider).classPeriods;
    final DateTime now = DateTime.now();

    for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
      final DateTime day = now.add(Duration(days: dayOffset));
      final int weekday = day.weekday; // 1=周一..7=周日
      for (final Course c in courses) {
        if (c.day != weekday) continue;
        if (!c.showsOn(meta.week)) continue; // 跨周边界以当前周近似。
        if (c.start < 1 || c.start > periods.length) continue;
        final ClassPeriod p = periods[c.start - 1];
        if (!p.enabled) continue;
        final DateTime at = DateTime(
          day.year,
          day.month,
          day.day,
          p.startMinutes ~/ 60,
          p.startMinutes % 60,
        );
        if (dayOffset == 0 && !at.isAfter(now)) continue; // 今天已过/正在不排
        final int id =
            ('course_alarm_${c.id}_${day.year}${day.month}${day.day}')
                .hashCode & 0x7fffffff;
        unawaited(
          ReminderService.scheduleAlert(
            id: id,
            at: at,
            title: c.name,
            body:
                '${Course.periodLabel(c.start, c.len)} · '
                '${ClassPeriod.formatMinutes(p.startMinutes)} 开始',
          ),
        );
      }
    }
  }

  // ── 常驻通知（上课中）：启动原生自治倒计时 / 下课停 ────────────

  /// 该课覆盖启用节次的**结束分钟**（0 点起；与 currentClassProvider 一致）。
  int _endMinutesOf(Course c, List<ClassPeriod> periods) {
    int end = 0;
    final int first = (c.start - 1).clamp(0, periods.length - 1);
    final int last = (c.start + c.len - 2).clamp(first, periods.length - 1);
    for (int i = first; i <= last; i++) {
      final ClassPeriod p = periods[i];
      if (p.enabled && p.endMinutes > p.startMinutes) end = p.endMinutes;
    }
    return end;
  }

  void _onCurrentClass(CurrentClass? cur) {
    if (cur == null || cur.timeMissing) {
      unawaited(ReminderService.stopCountdown());
      return;
    }
    final List<ClassPeriod> periods = ref.read(appSettingsProvider).classPeriods;
    final int endMin = _endMinutesOf(cur.course, periods);
    if (endMin <= 0) {
      unawaited(ReminderService.stopCountdown());
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime endAt = DateTime(
      now.year,
      now.month,
      now.day,
      endMin ~/ 60,
      endMin % 60,
    );
    unawaited(
      ReminderService.startCountdown(
        title: cur.course.name,
        endText: '${cur.periodLabel} · ${cur.spanEndLabel} 结束',
        endAtMillis: endAt.millisecondsSinceEpoch,
        totalMinutes: cur.totalMinutes <= 0 ? 1 : cur.totalMinutes,
      ),
    );
  }
}
