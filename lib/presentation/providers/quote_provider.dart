// lib/presentation/providers/quote_provider.dart
// 编号：S-21/S-22 首页动态内容 Provider（v1.26.0 新增;v1.27.0 点击刷新）
// 说明：
//   - dailyQuoteProvider：每日一言（S-21）——watch 设置四切片
//     (quoteEnabled/quoteApi/quoteStyle/quoteLang)：
//       * 开关关 → AsyncData(null)(UI 落本地文案),零网络;
//       * 缓存新鲜(同自然日 && 同 API && 同风格 && 同语言)→ 直接返回,
//         零网络(旧缓存无 lang 字段按 'zh' 兼容,升级当日平滑);
//       * 否则:旧内容(可 null)立即展示 → 后台拉新(主 API 失败静默
//         fallback 固定备用 1 家,再失败保持旧内容/本地文案,不打扰);
//   - forceRefresh()(v1.27.0):摘要卡点击手动刷新 —— 忽略当日缓存强制
//     重取,25 秒冷却(不足静默忽略,无 Toast);
//   - autoRefresh()(v1.28.0):45 分钟自动换新(仅 C-27 Timer 驱动;
//     v1.31.0:重建不再调用,见 refreshIfDayChanged);
//   - refreshIfDayChanged()(v1.31.0):页面重建/回首页保守检查 —— 仅无缓存/
//     跨自然日/缺 fetchedAt 时拉新(每日换新语义;同日零请求,修复
//     「切页回首页每日一言自己刷新」);
//   - 功耗:无定时器;仅在 build/手动刷新且缓存过期时联网;开关关永不联网。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quotes/s21_quote_service.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/daily_quote.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_providers.dart';

/// S-21 联网服务注入点（单元测试可 override 为 fixture 客户端）。
final quoteServiceProvider = Provider<QuoteService>((ref) {
  return QuoteService();
});

/// 每日一言状态：`null` = 开关关闭 / 全后端失败（UI 显示本地文案）。
final dailyQuoteProvider =
    AsyncNotifierProvider<DailyQuoteNotifier, DailyQuote?>(
      DailyQuoteNotifier.new,
    );

/// 手动点击刷新的最短间隔(v1.27.0,25s;冷却内点击静默忽略)。
const Duration kQuoteRefreshCooldown = Duration(seconds: 25);

/// 自动换新间隔(v1.28.0,45 分钟):内容展示超过该窗口即自动重取;
/// 与手动冷却相互独立(手动点击仍受 [kQuoteRefreshCooldown] 限制)。
const Duration kQuoteAutoInterval = Duration(minutes: 45);

/// 备用本地文案池（开关关 / 联网全败时展示;按日稳定取一条,零网络）。
const List<String> kLocalFallbackQuotes = <String>[
  '今天也要加油哦 ✨',
  '心之所向，素履以往',
  '慢慢来，比较快',
  '生活明朗，万物可爱',
  '保持热爱，奔赴山海',
];

/// 按日期稳定取本地文案（同一天同一条,不闪变）。
String localFallbackQuote(DateTime now) {
  final int dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
  return kLocalFallbackQuotes[dayOfYear % kLocalFallbackQuotes.length];
}

/// 每日一言设置切片(provider 重建判定用)。
typedef QuoteSettings = ({bool enabled, String api, String style, String lang});

class DailyQuoteNotifier extends AsyncNotifier<DailyQuote?> {
  QuoteService? _service;

  /// 上次手动刷新时刻(v1.27.0,冷却判定)。
  DateTime? _lastManualAt;

  /// 拉取进行中(v1.28.0:自动/手动并发丢弃,防重复请求)。
  bool _fetching = false;

  String _two(int x) => x < 10 ? '0$x' : '$x';

  String _todayKey(DateTime now) =>
      '${now.year}-${_two(now.month)}-${_two(now.day)}';

  @override
  FutureOr<DailyQuote?> build() {
    // select 四切片:与每日一言无关的设置变更不触发重建(§11.2.2)。
    final QuoteSettings s = ref.watch(
      appSettingsProvider.select(
        (AppSettings a) => (
          enabled: a.quoteEnabled,
          api: a.quoteApi,
          style: a.quoteStyle,
          lang: a.quoteLang,
        ),
      ),
    );
    _service ??= ref.read(quoteServiceProvider);
    final SettingsRepository repo = ref.read(settingsRepositoryProvider);
    if (!s.enabled) return null; // 开关关:零网络。

    final DateTime now = DateTime.now();
    final DailyQuote? cached = repo.loadQuoteCache();
    if (_isFresh(cached, s, now)) {
      return cached; // 同日同源同风格同语言且未超 45 分钟:零网络。
    }

    // 缓存过期/换源/超窗:旧内容(可能 null)立即可见,后台拉新,不闪 loading。
    state = AsyncData(cached);
    unawaited(_pullAndApply(s, repo));
    return cached;
  }

  /// 缓存新鲜度(v1.28.0):同日 && 同 API && 同风格 && 同语言 &&
  /// 距获取时刻 < 45 分钟自动换新窗口;旧缓存缺 fetchedAt/lang 按过期/
  /// 'zh' 兼容(升级当日各自拉新一次后自然补齐,不额外请求)。
  bool _isFresh(DailyQuote? cached, QuoteSettings s, DateTime now) {
    if (cached == null || cached.api.key != s.api) return false;
    final String? effLang = _effectiveLang(s);
    if (effLang != null && (cached.lang ?? 'zh') != effLang) return false;
    if (cached.style?.key != s.style) return false;
    final DateTime? fetched = cached.fetchedAt;
    if (fetched == null) return false;
    if (cached.dateKey != _todayKey(now)) return false;
    return now.difference(fetched) < kQuoteAutoInterval;
  }

  /// 实际参与请求的语言:仅 UAPI 生效,其它 API 语言无关(null)。
  static String? _effectiveLang(QuoteSettings s) =>
      QuoteApi.fromKey(s.api) == QuoteApi.uapi ? s.lang : null;

  /// 手动刷新(v1.27.0):摘要卡点击触发 —— 25s 冷却内静默忽略;
  /// 忽略缓存强制重取,成功更新缓存与内容,失败静默保持旧内容。
  Future<void> forceRefresh() async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastManualAt;
    if (last != null && now.difference(last) < kQuoteRefreshCooldown) {
      return; // 冷却:静默忽略。
    }
    _lastManualAt = now;
    final AppSettings cur = ref.read(appSettingsProvider);
    if (!cur.quoteEnabled) return; // 开关关:不联网。
    final QuoteSettings s = (
      enabled: true,
      api: cur.quoteApi,
      style: cur.quoteStyle,
      lang: cur.quoteLang,
    );
    final SettingsRepository repo = ref.read(settingsRepositoryProvider);
    // 旧内容保持可见,拉取成功后原地替换(不闪 loading)。
    unawaited(_pullAndApply(s, repo));
  }

  /// 自动换新(v1.28.0):45 分钟窗口到期 / 摘要卡重建时调用 ——
  /// 内容仍新鲜(距获取 <45 分钟)则零请求;过期则后台重取
  /// (不受手动 25s 冷却限制,窗口本身即节流)。
  /// v1.31.0 修复:「重建即检查」从本方法拆出为 [refreshIfDayChanged] ——
  /// 本方法仅由 C-27 存活期 Timer 驱动(页面可见每 45 分钟换新)。
  Future<void> autoRefresh() async {
    final AppSettings cur = ref.read(appSettingsProvider);
    if (!cur.quoteEnabled) return; // 开关关:零网络。
    final QuoteSettings s = (
      enabled: true,
      api: cur.quoteApi,
      style: cur.quoteStyle,
      lang: cur.quoteLang,
    );
    final SettingsRepository repo = ref.read(settingsRepositoryProvider);
    final DailyQuote? cached = repo.loadQuoteCache();
    if (_isFresh(cached, s, DateTime.now())) return; // 窗口内:零请求。
    await _pullAndApply(s, repo);
  }

  /// v1.31.0:页面重建 / 切回首页时的**保守检查**(替代旧「立即 autoRefresh」)
  /// —— 仅当 无缓存 / 缓存跨自然日 / 缺失获取时刻 时才拉新(每日换新语义),
  /// **不再以 45 分钟窗口判定**:45 分钟自动换新只由 C-27 Timer 驱动,
  /// 修复「切走再回首页,每日一言自己刷新」(重建触发 45 分钟判定,频繁
  /// 切页时反复换新)。
  Future<void> refreshIfDayChanged() async {
    final AppSettings cur = ref.read(appSettingsProvider);
    if (!cur.quoteEnabled) return; // 开关关:零网络。
    final QuoteSettings s = (
      enabled: true,
      api: cur.quoteApi,
      style: cur.quoteStyle,
      lang: cur.quoteLang,
    );
    final SettingsRepository repo = ref.read(settingsRepositoryProvider);
    final DailyQuote? cached = repo.loadQuoteCache();
    if (cached == null) {
      await _pullAndApply(s, repo); // 首次/无缓存:拉一条。
      return;
    }
    final bool dayChanged =
        cached.dateKey != _todayKey(DateTime.now()) ||
        cached.fetchedAt == null;
    if (!dayChanged) return; // 同日且有获取时刻:零请求(45min 窗口交 Timer)。
    await _pullAndApply(s, repo);
  }

  Future<void> _pullAndApply(QuoteSettings s, SettingsRepository repo) async {
    if (_fetching) return; // 拉取进行中:并发请求丢弃(自动/手动互不叠加)。
    _fetching = true;
    try {
      final QuoteApi api = QuoteApi.fromKey(s.api);
      final String? lang = _effectiveLang(s);
      // 风格:多风格 API 生效;UAPI 非中文语言档按语言源随机(风格不参与)。
      final QuoteStyle? style = api.supportsStyles
          ? (api == QuoteApi.uapi && lang != null && lang != 'zh'
                ? null
                : QuoteStyle.fromKey(s.style))
          : null;
      DailyQuote quote;
      try {
        quote = await _service!.fetch(api: api, style: style, lang: lang);
      } on QuoteFetchException {
        // 主 API 失败 → 备用(当前非 iciba → iciba;iciba → hitokoto)。
        final QuoteApi backup = api == QuoteApi.iciba
            ? QuoteApi.hitokoto
            : QuoteApi.iciba;
        quote = await _service!.fetch(
          api: backup,
          style: backup.supportsStyles ? backup.defaultStyle : null,
          lang: null, // 备用源无语言筛选
        );
      }
      repo.saveQuoteCache(quote);
      if (!ref.mounted) return; // provider 已销毁(页面切走):放弃写入。
      // 竞态守卫:拉取期间用户关了开关 / 换了来源 → 放弃本次结果
      // (新 build 已按最新设置自行处理)。
      final AppSettings cur = ref.read(appSettingsProvider);
      if (!cur.quoteEnabled || cur.quoteApi != s.api) return;
      state = AsyncData(quote);
    } on QuoteFetchException {
      // 主 + 备用均失败:保持旧缓存/null,UI 落本地文案(静默)。
    } catch (_) {
      // 未知异常同静默(不打扰用户)。
    } finally {
      _fetching = false;
    }
  }
}
