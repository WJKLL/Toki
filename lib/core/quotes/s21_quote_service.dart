// lib/core/quotes/s21_quote_service.dart
// 编号：S-21 每日一言联网服务（v1.26.0 新增;v1.27.0 UAPI 适配器重写）
// 说明：统一 5 家免注册 API 后端（Hitokoto / 金山词霸 / 诗泉 / 今日诗词 /
//   UAPI），按用户选择的 [QuoteApi] 与 [QuoteStyle]/[QuoteLang] 请求并
//   归一化为 [DailyQuote]。
//   - 请求超时默认 6s；失败抛 [QuoteFetchException]（调用方负责 fallback）；
//   - 内容统一清洗空白（诗词换行转空格，保证卡片单行阅读）；
//   - [from] 语义 = 真实出处（作者/作品），无出处为空串 —— UI 不显示
//     API 名称兜底（v1.27.0）;
//   - [lang] 仅 UAPI 生效（官方语料仅中/英,source 过滤;无日文原文）;
//   - http.Client 可注入（单元测试用 fixture 客户端）。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/daily_quote.dart';

/// 拉取失败（网络 / 超时 / 非 2xx / 解析失败统一收敛为此异常）。
class QuoteFetchException implements Exception {
  const QuoteFetchException(this.message);

  final String message;

  @override
  String toString() => 'QuoteFetchException: $message';
}

/// 每日一言联网服务（S-21）。
class QuoteService {
  QuoteService({http.Client? client, this.timeout = const Duration(seconds: 6)})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// 请求并归一化为 [DailyQuote]。
  /// [style] 仅对支持多风格的后端生效;固定风格后端忽略。
  /// [lang] 语言档键（'zh'/'en'/'mix'）—— 仅 UAPI 生效,其它后端忽略;
  /// 非中文语言下 UAPI 按语言源随机,风格不参与过滤。
  Future<DailyQuote> fetch({
    required QuoteApi api,
    QuoteStyle? style,
    String? lang,
  }) {
    return switch (api) {
      QuoteApi.hitokoto => _hitokoto(style),
      QuoteApi.iciba => _iciba(),
      QuoteApi.poetry => _poetry(),
      QuoteApi.jinrishici => _jinrishici(),
      QuoteApi.uapi => _uapi(
        style: lang == null || lang == 'zh' ? style : null,
        lang: lang,
      ),
    };
  }

  // ── 通用请求 ────────────────────────────────────────────────

  /// GET + 超时 + UTF-8 解码（容忍无 charset 头 / BOM）。
  Future<String> _getBody(Uri uri) async {
    final http.Response resp;
    try {
      resp = await _client
          .get(
            uri,
            headers: const <String, String>{'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const QuoteFetchException('timeout');
    } on http.ClientException catch (e) {
      throw QuoteFetchException('network: ${e.message}');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw QuoteFetchException('http ${resp.statusCode}');
    }
    String body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (body.isNotEmpty && body.codeUnitAt(0) == 0xFEFF) {
      body = body.substring(1); // 去 UTF-8 BOM
    }
    return body;
  }

  /// 解析 JSON 对象；失败统一收敛。
  Map<String, dynamic> _decodeObject(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const QuoteFetchException('bad json');
    }
    if (decoded is! Map) throw const QuoteFetchException('not object');
    return Map<String, dynamic>.from(decoded);
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _asString(Object? v) => v is String ? v.trim() : '';

  String _todayKey() {
    final DateTime n = DateTime.now();
    String two(int x) => x < 10 ? '0$x' : '$x';
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  // ── 各家适配 ────────────────────────────────────────────────

  /// 一言（Hitokoto）：?c=d 文学 / c=i 诗词 / c=l 励志 / 缺省随机。
  Future<DailyQuote> _hitokoto(QuoteStyle? style) async {
    final String? c = switch (style) {
      QuoteStyle.classic => 'd',
      QuoteStyle.poetry => 'i',
      QuoteStyle.inspire => 'l',
      _ => null, // mix / 空 → 全类型随机
    };
    final Uri uri = Uri.parse(
      'https://v1.hitokoto.cn/'
      '?charset=utf-8${c == null ? '' : '&c=$c'}',
    );
    final Map<String, dynamic> json = _decodeObject(await _getBody(uri));
    final String content = _clean(_asString(json['hitokoto']));
    if (content.isEmpty) throw const QuoteFetchException('empty hitokoto');
    final String fromWho = _asString(json['from_who']);
    final String fromSrc = _asString(json['from']);
    final String from = <String>[
      if (fromWho.isNotEmpty) fromWho,
      if (fromSrc.isNotEmpty) fromSrc,
    ].join(' · ');
    return DailyQuote(
      content: content,
      from: from, // 空 = 无来源(不显示行)
      api: QuoteApi.hitokoto,
      style: style,
      fetchedAt: DateTime.now(),
      dateKey: _todayKey(),
    );
  }

  /// 金山词霸每日一句：{content 英文, note 中文} → 展示中文 note。
  /// 无独立出处字段 → from 为空(来源行不显示)。
  Future<DailyQuote> _iciba() async {
    final Map<String, dynamic> json = _decodeObject(
      await _getBody(Uri.parse('https://open.iciba.com/dsapi/')),
    );
    String content = _clean(_asString(json['note']));
    if (content.isEmpty) content = _clean(_asString(json['content']));
    if (content.isEmpty) throw const QuoteFetchException('empty iciba');
    return DailyQuote(
      content: content,
      from: '',
      api: QuoteApi.iciba,
      style: null,
      fetchedAt: DateTime.now(),
      dateKey: _todayKey(),
    );
  }

  /// 诗泉（古诗词）：{title, author, content}。
  Future<DailyQuote> _poetry() async {
    final Map<String, dynamic> json = _decodeObject(
      await _getBody(Uri.parse('https://poetry.palemoky.com/api/poems/random')),
    );
    final String content = _clean(_asString(json['content']));
    if (content.isEmpty) throw const QuoteFetchException('empty poetry');
    final String title = _asString(json['title']);
    final String author = _asString(json['author']);
    final String from = <String>[
      if (title.isNotEmpty) '《$title》',
      if (author.isNotEmpty) author,
    ].join(' · ');
    return DailyQuote(
      content: content,
      from: from, // 空 = 无来源
      api: QuoteApi.poetry,
      style: null,
      fetchedAt: DateTime.now(),
      dateKey: _todayKey(),
    );
  }

  /// 今日诗词：{data:{content, origin:{title, author, dynasty}}}。
  Future<DailyQuote> _jinrishici() async {
    final Map<String, dynamic> root = _decodeObject(
      await _getBody(Uri.parse('https://api.jinrishici.com/v1/')),
    );
    final Object? dataRaw = root['data'];
    if (dataRaw is! Map) throw const QuoteFetchException('no data');
    final Map<String, dynamic> data = Map<String, dynamic>.from(dataRaw);
    final String content = _clean(_asString(data['content']));
    if (content.isEmpty) throw const QuoteFetchException('empty jinrishici');
    String title = '';
    String author = '';
    String dynasty = '';
    final Object? originRaw = data['origin'];
    if (originRaw is Map) {
      final Map<String, dynamic> origin = Map<String, dynamic>.from(originRaw);
      title = _asString(origin['title']);
      author = _asString(origin['author']);
      dynasty = _asString(origin['dynasty']);
    }
    final String from = <String>[
      if (title.isNotEmpty) '《$title》',
      if (dynasty.isNotEmpty) dynasty,
      if (author.isNotEmpty) author,
    ].join(' · ');
    return DailyQuote(
      content: content,
      from: from, // 空 = 无来源
      api: QuoteApi.jinrishici,
      style: null,
      fetchedAt: DateTime.now(),
      dateKey: _todayKey(),
    );
  }

  /// UAPI 一言(v1.27.0 重写;v1.28.0 +动漫台词档):
  /// GET https://uapis.cn/api/v1/saying/random。
  /// 语言 → source(语料库):zh = 双中文源 / en = quotable(英文原句)/
  ///   anime = 双中文源 + category 动画,漫画(中文动漫台词,官方语料
  ///   无日文原文)/ mix = 不传(全库随机)。
  /// 风格(仅 zh 档有意义)→ category:beauty = 古诗文,诗词;
  ///   classic/mix = 无额外过滤。其它语言档忽略风格。
  /// 响应兼容「直接对象」与「{item:{…}} 包装」两种形态。
  Future<DailyQuote> _uapi({QuoteStyle? style, String? lang}) async {
    final Map<String, String> q = <String, String>{'mode': 'random'};
    if (lang == 'zh') {
      q['source'] = 'caoxingyu sentence,sentences bundle';
      if (style == QuoteStyle.beauty) {
        q['category'] = '古诗文,诗词';
      }
    } else if (lang == 'anime') {
      q['source'] = 'caoxingyu sentence,sentences bundle';
      q['category'] = '动画,漫画';
    } else if (lang == 'en') {
      q['source'] = 'quotable';
    }
    // mix / null:不传 source(全库随机)。
    final Uri uri = Uri.parse('https://uapis.cn/api/v1/saying/random')
        .replace(queryParameters: q);
    final Map<String, dynamic> root = _decodeObject(await _getBody(uri));
    final Map<String, dynamic> data;
    if (root['content'] is String) {
      data = root; // random 模式:直接对象
    } else {
      final Object? item = root['item'];
      if (item is! Map) {
        throw const QuoteFetchException('uapi shape');
      }
      data = Map<String, dynamic>.from(item); // 包装形态防御
    }
    final String content = _clean(_asString(data['content']));
    if (content.isEmpty) throw const QuoteFetchException('empty uapi');
    final String author = _asString(data['author']);
    String source = _asString(data['source']);
    if (source.isNotEmpty && !source.startsWith('《')) {
      source = '《$source》';
    }
    final String from = <String>[
      if (author.isNotEmpty) author,
      if (source.isNotEmpty) source,
    ].join(' · ');
    return DailyQuote(
      content: content,
      from: from, // 空 = 无来源
      api: QuoteApi.uapi,
      style: style,
      lang: lang,
      fetchedAt: DateTime.now(),
      dateKey: _todayKey(),
    );
  }
}
