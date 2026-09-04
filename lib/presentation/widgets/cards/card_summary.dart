// lib/presentation/widgets/cards/card_summary.dart
// 编号：C-27 首页摘要区（v1.14.0 登记;v1.26.0 动态内容化;
//   v1.27.0 点击刷新 + 按压动效;v1.28.0 45 分钟自动刷新 + 点击轻提示）
// 职责：首页顶部摘要区 —— 「动态问候语(S-22)」+「每日一言(S-21)」。
// 交互（v1.27.0/v1.28.0）：整卡可点击 —— 按压 0.96 缩放(150ms easeInOut),
//   松手:轻提示「请稍等一会哦」+ 手动刷新(25s 冷却,静默);卡片存活期每
//   45 分钟自动换新一次(Timer;v1.31.0:重建/回页仅跨天保守检查,不再由
//   45 分钟窗口触发,修复切页回首页自动刷新);问候语不随刷新变化。
// 数据：
//   - 问候语：GreetingService 现算(确定性 seed:同一小时内稳定;优先级
//     节日 > 节气 > 时段;用户名暂固定 'XX')；
//   - 每日一言：dailyQuoteProvider 流式(开关关/全后端失败 → AsyncData(null)
//     → 本地文案池按日稳定取一条;联网成功 → 内容 + 来源小字)。
// 样式：问候语 title1 加粗 24px;一言 斜体 16px w400 letterSpacing 0.8,
//   无标题前缀、maxLines 2 防溢出;来源行仅在 from 非空时显示(弱化小字)。
// 性能：按压动画瞬时(≤150ms);自动刷新为 45 分钟单次 Timer(非常驻 ticker,
//   页面销毁即取消);quote 更新仅当 provider 状态变化,不闪 loading。
// v1.31.0:initState 不再立即 autoRefresh(45 分钟窗口判定),改调
//   refreshIfDayChanged(跨天保守检查)—— 切走再回首页不会自己刷新。
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/greeting/s22_greeting_service.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../../domain/entities/daily_quote.dart';
import '../../providers/quote_provider.dart';

/// 按压缩放(松手恢复)系数。
const double _kSummaryPressScale = 0.96;
const Duration _kSummaryPressDuration = Duration(milliseconds: 150);

/// C-27 首页摘要区（动态问候语 + 每日一言,点击刷新 + 45 分钟自动换新）。
class C27HomeSummary extends ConsumerStatefulWidget {
  const C27HomeSummary({super.key});

  @override
  ConsumerState<C27HomeSummary> createState() => _C27HomeSummaryState();
}

class _C27HomeSummaryState extends ConsumerState<C27HomeSummary> {
  /// 按压态:true → 0.96 缩放(点击反馈)。
  bool _pressed = false;

  /// v1.28.0:自动换新周期 Timer(可见期持有;销毁取消,零残留)。
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    // v1.31.0 修复:「切回首页每日一言自己刷新」—— 重建/回页只做**跨天
    // 保守检查**(refreshIfDayChanged:跨自然日/无缓存才拉新,同日零请求);
    // 45 分钟自动换新窗口仅由下方 Timer 驱动(页面存活期可见时换新),
    // 不再因页面重建(如一级页横滑切回)而按 45 分钟窗口判定触发换新。
    unawaited(ref.read(dailyQuoteProvider.notifier).refreshIfDayChanged());
    _autoRefreshTimer = Timer.periodic(kQuoteAutoInterval, (_) {
      unawaited(ref.read(dailyQuoteProvider.notifier).autoRefresh());
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final String greeting = GreetingService.instance.greetingFor();
    final AsyncValue<DailyQuote?> quoteAsync = ref.watch(dailyQuoteProvider);
    // 加载/关闭/失败 → 一律本地文案(不闪 loading、不打扰)。
    final DailyQuote? quote = switch (quoteAsync) {
      AsyncData(value: final DailyQuote? v) => v,
      _ => null,
    };
    final String quoteText = quote == null || quote.content.isEmpty
        ? localFallbackQuote(DateTime.now())
        : quote.content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) {
        _setPressed(false);
        // v1.28.0:点击即轻提示「请稍等一会哦」(网络往返的即时应答;
        //   25s 冷却同样提示,forceRefresh 内部静默判定)。
        showMiniToast(context, '请稍等一会哦');
        unawaited(ref.read(dailyQuoteProvider.notifier).forceRefresh());
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? _kSummaryPressScale : 1.0,
        duration: _kSummaryPressDuration,
        curve: Curves.easeInOut,
        child: MiuixCard(
          insideMargin: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 动态问候语:粗体 24(可读性优先)。
              MiuixText(
                greeting,
                style: textStyles.title1.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                color: colors.onSurface,
              ),
              const SizedBox(height: 10),
              // 每日一言:文艺斜体 16,无标题前缀。
              MiuixText(
                quoteText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.8,
                  height: 1.5,
                ),
                color: colors.onSurfaceVariantSummary,
              ),
              // 来源弱化小字(v1.27.0:仅真实出处非空时显示,无 API 名兜底)。
              if (quote != null && quote.from.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: MiuixText(
                    '— ${quote.from}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, letterSpacing: 0.4),
                    color: colors.onSurfaceVariantActions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
