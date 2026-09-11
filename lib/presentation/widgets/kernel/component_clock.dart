// lib/presentation/widgets/kernel/component_clock.dart
// 编号：C-66 数字时钟渲染器（P-24 空间壁纸 · 期 1）
//
// 职责：只绘制【内容】——时间 + 日期。玻璃底 / 圆角 / 边框 / 投影由外层
//   C-67 组件外壳统一提供，故期 2 把外壳换成 LensRefraction 折射玻璃时，
//   本文件零改动。
//
// 功耗要点（§11.6）：
//   定时器**精确对齐到下一个整分**（显示秒时对齐整秒），不做每秒 setState ——
//   静止时零重建；dispose 中取消定时器，无泄漏。
import 'dart:async';

import 'package:flutter/widgets.dart';

/// C-66 数字时钟内容。
class ComponentClock extends StatefulWidget {
  const ComponentClock({
    super.key,
    this.h24 = true,
    this.showDate = true,
    this.showSeconds = false,
    this.timeSize = 46,
    this.dateSize = 11.5,
    this.color = const Color(0xFFFFFFFF),
  });

  /// 24 小时制（false → 12 小时制并附 AM/PM）。
  final bool h24;

  /// 是否显示日期行。
  final bool showDate;

  /// 是否显示秒（默认关：省电且更稳）。
  final bool showSeconds;

  /// 时间字号。
  final double timeSize;

  /// 日期字号。
  final double dateSize;

  /// 文字颜色。
  final Color color;

  @override
  State<ComponentClock> createState() => _ComponentClockState();
}

class _ComponentClockState extends State<ComponentClock> {
  static const List<String> _week = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(covariant ComponentClock old) {
    super.didUpdateWidget(old);
    // 秒的开关会改变对齐粒度，需重新排程。
    if (old.showSeconds != widget.showSeconds) _scheduleTick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 对齐到下一个刷新点（整秒或整分）。
  void _scheduleTick() {
    _timer?.cancel();
    final DateTime n = DateTime.now();
    final Duration wait = widget.showSeconds
        ? Duration(milliseconds: 1000 - n.millisecond)
        : Duration(
            seconds: 59 - n.second,
            milliseconds: 1000 - n.millisecond,
          );
    _timer = Timer(wait, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  String get _timeText {
    final DateTime d = _now;
    int h = d.hour;
    String suffix = '';
    if (!widget.h24) {
      suffix = h < 12 ? ' AM' : ' PM';
      h = h % 12;
      if (h == 0) h = 12;
    }
    final String hh = h.toString().padLeft(2, '0');
    final String mm = d.minute.toString().padLeft(2, '0');
    final String ss = widget.showSeconds
        ? ':${d.second.toString().padLeft(2, '0')}'
        : '';
    return '$hh:$mm$ss$suffix';
  }

  String get _dateText {
    final DateTime d = _now;
    return '${d.month}月${d.day}日 星期${_week[d.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final Color c = widget.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 15, 26, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _timeText,
            maxLines: 1,
            style: TextStyle(
              fontSize: widget.timeSize,
              // 细字重是这套玻璃时钟观感的来源（对齐鸿蒙 / iOS 的时钟排版）。
              fontWeight: FontWeight.w200,
              height: 1.06,
              letterSpacing: 0.5,
              color: c,
              // 等宽数字：分钟跳变时宽度不变，避免整块玻璃左右抖动。
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
              shadows: <Shadow>[
                Shadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.40),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
                Shadow(
                  color: c.withValues(alpha: 0.18),
                  blurRadius: 22,
                ),
              ],
            ),
          ),
          if (widget.showDate) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              _dateText,
              maxLines: 1,
              style: TextStyle(
                fontSize: widget.dateSize,
                letterSpacing: 2.4,
                color: c.withValues(alpha: 0.82),
                shadows: <Shadow>[
                  Shadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.45),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
