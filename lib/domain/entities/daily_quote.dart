// lib/domain/entities/daily_quote.dart
// 编号：S-21 每日一言数据模型（v1.26.0 新增）
// 说明：纯领域实体，不依赖 UI 框架。
//   - QuoteApi：可用 API 后端（5 家，全部免注册免 Key）；
//   - QuoteStyle：内容风格（仅多风格 API 使用；固定风格 API 不落状态）；
//   - DailyQuote：统一返回模型 + 缓存序列化（dateKey 用于自然日判定）。
//   中文标签与 UI 选项映射在 presentation 层（settings_providers / 设置页）。
import 'package:flutter/foundation.dart' show immutable;

/// 每日一言风格（内容类别；标签见 presentation 层）。
enum QuoteStyle {
  classic('classic'),
  poetry('poetry'),
  inspire('inspire'),
  beauty('beauty'),
  mix('mix');

  const QuoteStyle(this.key);

  /// 持久化键（S-02 settings.quoteStyle）。
  final String key;

  static QuoteStyle fromKey(String? key) => QuoteStyle.values.firstWhere(
    (QuoteStyle s) => s.key == key,
    orElse: () => QuoteStyle.classic,
  );
}

/// 每日一言 API 后端。
enum QuoteApi {
  /// 一言（Hitokoto）：支持 文学/诗词/励志/随机。
  hitokoto('hitokoto', <QuoteStyle>[
    QuoteStyle.classic,
    QuoteStyle.poetry,
    QuoteStyle.inspire,
    QuoteStyle.mix,
  ]),

  /// 金山词霸每日一句：中英双语（固定，无风格参数）。
  iciba('iciba', <QuoteStyle>[]),

  /// 诗泉（古诗词）：随机诗词（固定）。
  poetry('poetry', <QuoteStyle>[]),

  /// 今日诗词：智能推荐（固定）。
  jinrishici('jinrishici', <QuoteStyle>[]),

  /// UAPI 一言(v1.27.0 新端点):语言 source + 风格 category 过滤。
  uapi('uapi', <QuoteStyle>[
    QuoteStyle.beauty,
    QuoteStyle.classic,
    QuoteStyle.mix,
  ]);

  const QuoteApi(this.key, this.styles);

  /// 持久化键（S-02 settings.quoteApi）。
  final String key;

  /// 该 API 支持的风格集；空 = 固定内容类型（风格行隐藏）。
  final List<QuoteStyle> styles;

  /// 是否支持多风格（决定设置页风格行显隐）。
  bool get supportsStyles => styles.isNotEmpty;

  /// 默认风格（切换 API 后风格不在支持集时回落用）。
  QuoteStyle get defaultStyle =>
      styles.isNotEmpty ? styles.first : QuoteStyle.classic;

  static QuoteApi fromKey(String? key) => QuoteApi.values.firstWhere(
    (QuoteApi a) => a.key == key,
    orElse: () => QuoteApi.hitokoto,
  );
}

/// 每日一言统一返回模型（S-21 全部后端归一化）。
@immutable
class DailyQuote {
  const DailyQuote({
    required this.content,
    required this.from,
    required this.api,
    required this.style,
    required this.dateKey,
    this.lang,
    this.fetchedAt,
  });

  /// 展示主体文案（已清洗空白）。
  final String content;

  /// 来源标注（作者/作品等真实出处；空 = 无来源,UI 不显示来源行）。
  final String from;

  /// 实际返回该条的后端。
  final QuoteApi api;

  /// 实际使用的风格；固定风格后端为 null。
  final QuoteStyle? style;

  /// 实际使用的语言档键（v1.27.0;仅 UAPI 非空,null = 语言无关）。
  final String? lang;

  /// 获取日期键 'yyyy-MM-dd'（本地时区；缓存自然日判定）。
  final String dateKey;

  /// 实际获取时刻（v1.28.0;45 分钟自动换新窗口判定;旧缓存无此字段为
  /// null → 视为已过期,升级当日拉新一次后自然补齐）。
  final DateTime? fetchedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'content': content,
    'from': from,
    'api': api.key,
    'style': style?.key,
    'lang': lang,
    'fetched': fetchedAt?.millisecondsSinceEpoch,
    'date': dateKey,
  };

  /// 坏数据/缺字段 → null（调用方兜底本地文案）。
  static DailyQuote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
    final Object? content = map['content'];
    final Object? date = map['date'];
    if (content is! String || content.isEmpty || date is! String) return null;
    final Object? fetched = map['fetched'];
    return DailyQuote(
      content: content,
      from: map['from'] is String ? map['from'] as String : '',
      api: QuoteApi.fromKey(map['api'] is String ? map['api'] as String : null),
      style: map['style'] is String
          ? QuoteStyle.fromKey(map['style'] as String)
          : null,
      lang: map['lang'] is String ? map['lang'] as String : null,
      fetchedAt: fetched is int
          ? DateTime.fromMillisecondsSinceEpoch(fetched)
          : null,
      dateKey: date,
    );
  }
}
