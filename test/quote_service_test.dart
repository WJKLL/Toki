// test/quote_service_test.dart
// S-21 每日一言服务解析单元测试(v1.26.0 新增;v1.27.0 UAPI 新端点/语言):
//  使用 package:http/testing 的 MockClient 注入 fixture,验证 5 家后端
//  的 URL/参数构建、JSON 解析、内容清洗与失败收敛(不发起真实网络);
//  UAPI 覆盖:新端点 /api/v1/saying/random、语言→source、风格→category、
//  author·《source》来源组合、双响应形态兼容。
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiangjugong/core/quotes/s21_quote_service.dart';
import 'package:xiangjugong/domain/entities/daily_quote.dart';

void main() {
  /// 按请求路径返回对应 fixture(其余 404);[onRequest] 可捕获请求断言。
  QuoteService serviceWith(
    Map<String, String> fixtures, {
    void Function(http.Request)? onRequest,
  }) {
    final MockClient client = MockClient((http.Request req) async {
      onRequest?.call(req);
      final String? body = fixtures[req.url.path];
      if (body == null) {
        return http.Response('not found', 404);
      }
      return http.Response(
        body,
        200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    return QuoteService(client: client);
  }

  test('Hitokoto:经典语录 → c=d 参数 + 解析', () async {
    http.Request? captured;
    final QuoteService service = serviceWith(<String, String>{
      '/': '{"hitokoto":"人面不知何处去","from_who":"崔护","from":"题都城南庄"}',
    }, onRequest: (http.Request req) => captured = req);
    final DailyQuote q = await service.fetch(
      api: QuoteApi.hitokoto,
      style: QuoteStyle.classic,
    );
    expect(captured!.url.queryParameters['c'], 'd');
    expect(q.content, '人面不知何处去');
    expect(q.from, '崔护 · 题都城南庄');
    expect(q.api, QuoteApi.hitokoto);
    expect(q.style, QuoteStyle.classic);
  });

  test('Hitokoto:随机混合 → 无 c 参数', () async {
    http.Request? captured;
    final QuoteService service = serviceWith(<String, String>{
      '/': '{"hitokoto":"hi","from":""}',
    }, onRequest: (http.Request req) => captured = req);
    await service.fetch(api: QuoteApi.hitokoto, style: QuoteStyle.mix);
    expect(captured!.url.queryParameters.containsKey('c'), isFalse);
  });

  test('金山词霸:展示中文 note,无来源(from 为空串)', () async {
    final QuoteService service = serviceWith(<String, String>{
      '/dsapi/': '{"content":"Life is a journey.","note":"人生是一场旅程。"}',
    });
    final DailyQuote q = await service.fetch(api: QuoteApi.iciba);
    expect(q.content, '人生是一场旅程。');
    expect(q.from, isEmpty, reason: '无出处字段 → 不显示来源行');
    expect(q.style, isNull);
  });

  test('诗泉:多行诗词清洗为单行 + 来源组合', () async {
    final QuoteService service = serviceWith(<String, String>{
      '/api/poems/random':
          '{"title":"静夜思","author":"李白","content":"床前明月光\\n疑是地上霜\\n"}',
    });
    final DailyQuote q = await service.fetch(api: QuoteApi.poetry);
    expect(q.content, '床前明月光 疑是地上霜');
    expect(q.from, '《静夜思》 · 李白');
    expect(q.api, QuoteApi.poetry);
  });

  test('今日诗词:data.content + origin 组装', () async {
    final QuoteService service = serviceWith(<String, String>{
      '/v1/': '{"data":{"content":"春眠不觉晓","origin":{"title":"春晓","author":"孟浩然","dynasty":"唐"}}}',
    });
    final DailyQuote q = await service.fetch(api: QuoteApi.jinrishici);
    expect(q.content, '春眠不觉晓');
    expect(q.from, '《春晓》 · 唐 · 孟浩然');
  });

  group('UAPI(v1.27.0 新端点 /api/v1/saying/random)', () {
    const String fixture =
        '{"uuid":"u1","content":"无论多么微小的邂逅，都必定有着某种意义。",'
        '"source":"夏目友人帐","author":"绿川幸","corpus":"sentences-bundle",'
        '"category":"动画","contentLength":21}';

    test('中文语言 → source 双中文源;风格 beauty → category 古风', () async {
      http.Request? captured;
      final QuoteService service = serviceWith(<String, String>{
        '/api/v1/saying/random': fixture,
      }, onRequest: (http.Request req) => captured = req);
      final DailyQuote q = await service.fetch(
        api: QuoteApi.uapi,
        style: QuoteStyle.beauty,
        lang: 'zh',
      );
      final Uri uri = captured!.url;
      expect(uri.path, '/api/v1/saying/random');
      expect(uri.queryParameters['mode'], 'random');
      expect(
        uri.queryParameters['source'],
        'caoxingyu sentence,sentences bundle',
      );
      expect(uri.queryParameters['category'], '古诗文,诗词');
      expect(q.content, contains('邂逅'));
      expect(q.from, '绿川幸 · 《夏目友人帐》');
      expect(q.lang, 'zh');
    });

    test('英文语言 → source=quotable,风格不参与', () async {
      http.Request? captured;
      final QuoteService service = serviceWith(<String, String>{
        '/api/v1/saying/random': fixture,
      }, onRequest: (http.Request req) => captured = req);
      final DailyQuote q = await service.fetch(
        api: QuoteApi.uapi,
        style: QuoteStyle.beauty, // en 下应被忽略
        lang: 'en',
      );
      final Uri uri = captured!.url;
      expect(uri.queryParameters['source'], 'quotable');
      expect(uri.queryParameters.containsKey('category'), isFalse);
      expect(q.style, isNull, reason: '非中文语言风格不落模型');
    });

    test('混合语言 → 不传 source', () async {
      http.Request? captured;
      final QuoteService service = serviceWith(<String, String>{
        '/api/v1/saying/random': fixture,
      }, onRequest: (http.Request req) => captured = req);
      await service.fetch(api: QuoteApi.uapi, lang: 'mix');
      expect(captured!.url.queryParameters.containsKey('source'), isFalse);
    });

    test('动漫台词档(v1.28.0) → 中文双源 + category 动画,漫画', () async {
      http.Request? captured;
      final QuoteService service = serviceWith(<String, String>{
        '/api/v1/saying/random': fixture,
      }, onRequest: (http.Request req) => captured = req);
      final DailyQuote q = await service.fetch(
        api: QuoteApi.uapi,
        style: QuoteStyle.beauty, // anime 档忽略风格
        lang: 'anime',
      );
      final Uri uri = captured!.url;
      expect(
        uri.queryParameters['source'],
        'caoxingyu sentence,sentences bundle',
      );
      expect(uri.queryParameters['category'], '动画,漫画');
      expect(q.lang, 'anime');
      expect(q.style, isNull);
    });

    test('无 author/source 时 from 为空串', () async {
      final QuoteService service = serviceWith(<String, String>{
        '/api/v1/saying/random': '{"content":"一句话","contentLength":3}',
      });
      final DailyQuote q = await service.fetch(api: QuoteApi.uapi, lang: 'zh');
      expect(q.from, isEmpty);
    });

    test('包装形态兼容:{item:{content,…}}', () async {
      final QuoteService service = serviceWith(<String, String>{
        '/api/v1/saying/random':
            '{"date":"2026-09-03","item":{"content":"包装内正文","author":"甲"}}',
      });
      final DailyQuote q = await service.fetch(api: QuoteApi.uapi, lang: 'zh');
      expect(q.content, '包装内正文');
      expect(q.from, '甲');
    });

    test('source 已带书名号时不重复包裹', () async {
      final QuoteService service = serviceWith(<String, String>{
        '/api/v1/saying/random':
            '{"content":"内容","author":"乙","source":"《原书》"}',
      });
      final DailyQuote q = await service.fetch(api: QuoteApi.uapi, lang: 'zh');
      expect(q.from, '乙 · 《原书》');
    });
  });

  test('HTTP 错误收敛为 QuoteFetchException', () async {
    final QuoteService service = QuoteService(
      client: MockClient((_) async => http.Response('boom', 500)),
    );
    expect(
      () => service.fetch(api: QuoteApi.iciba),
      throwsA(isA<QuoteFetchException>()),
    );
  });

  test('坏 JSON 收敛为 QuoteFetchException', () async {
    final QuoteService service = QuoteService(
      client: MockClient((_) async => http.Response('<html>', 200)),
    );
    expect(
      () => service.fetch(api: QuoteApi.iciba),
      throwsA(isA<QuoteFetchException>()),
    );
  });
}
