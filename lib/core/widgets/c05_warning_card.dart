// lib/core/widgets/c05_warning_card.dart
// 编号：C-05 警告卡片（复刻蓝本 WarningCard：黄色/红色警示横幅）
// 功耗要点：纯静态 Widget，const 构造，零动画、零 ticker（§5 C-05 低功耗评级）。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'app_icons.dart';

/// 警告横幅。severity 决定语义色：
/// - [C05WarningSeverity.warning]：黄色警示（secondaryContainer 系）
/// - [C05WarningSeverity.error]：红色警示（errorContainer 系）
class C05WarningCard extends StatelessWidget {
  const C05WarningCard({
    super.key,
    required this.message,
    this.severity = C05WarningSeverity.warning,
    this.icon,
  });

  final String message;
  final C05WarningSeverity severity;

  /// 起始图标；默认按 severity 取 MiuixIcons（warning → 'info'，error → 'report'）。
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool error = severity == C05WarningSeverity.error;
    final Color bg = error ? colors.errorContainer : colors.secondaryContainer;
    final Color fg = error
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MiuixSurface(
        color: bg,
        cornerRadius: 12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              icon ??
                  MiuixIcon(
                    vector: error ? appIcon('report') : appIcon('info'),
                    size: 18,
                    tint: fg,
                  ),
              const SizedBox(width: 10),
              Expanded(
                child: MiuixText(
                  message,
                  style: MiuixTheme.of(context).textStyles.body2,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum C05WarningSeverity { warning, error }
