// test/tool_api_service_test.dart
// v1.35.0（P-09）：ToolApiService 统一调用管道单测 —— GET query 组装、
//  POST JSON body、POST body+query 混合（翻译 to_lang）、图片字节双态、
//  错误分类（服务端 message 覆盖）、requiresAuth 无 key → needsKey。
//  MockClient fixture（http/testing），零真实网络。
import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiangjugong/core/tools/tool_api_service.dart';
import 'package:xiangjugong/domain/entities/tool_config.dart';

ToolConfig _tool({
  String id = 't1',
  String apiPath = '/api/v1/test/echo',
  String method = 'GET',
  bool requiresAuth = false,
  List<ToolParam> params = const <ToolParam>[],
  String? categoryId = 'game',
}) {
  return ToolConfig(
    id: id,
    name: id,
    summary: '',
    icon: '',
    category: ToolCategory.fromId(categoryId) ?? ToolCategory.misc,
    apiPath: apiPath,
    method: method,
    requiresAuth: requiresAuth,
    params: params,
  );
}

/// 记录请求并回 JSON 的 fixture。
ToolApiService serviceCapturing(
  void Function(http.Request req) capture, {
  int status = 200,
  String body = '{"ok":true}',
  String contentType = 'application/json; charset=utf-8',
}) {
  return ToolApiService(
    client: MockClient((http.Request req) async {
      capture(req);
      return http.Response(
        body,
        status,
        headers: <String, String>{'content-type': contentType},
      );
    }),
  );
}

void main() {
  test('GET：query 参数组装 + key 走 Bearer 头(v1.42.0) + json 解析', () async {
    late http.Request seen;
    final ToolApiService s = serviceCapturing((req) => seen = req);
    final ToolApiResult r = await s.call(
      tool: _tool(
        apiPath: '/api/v1/random/string',
        params: const <ToolParam>[
          ToolParam(name: 'length', label: '长度'),
        ],
      ),
      values: const <String, String>{'length': '8'},
      apiKey: 'secret',
    );
    expect(seen.method, 'GET');
    expect(seen.url.path, '/api/v1/random/string');
    expect(seen.url.queryParameters['length'], '8');
    // v1.42.0:key 改走 Authorization: Bearer 头,不再塞 query(实测 query
    // key 被 UAPI 校验拒绝 → 401,即使匿名可用也被拖垮)。
    expect(seen.url.queryParameters.containsKey('key'), isFalse);
    expect(seen.headers['Authorization'], 'Bearer secret');
    expect(r.json, <String, dynamic>{'ok': true});
  });

  test('无 key → 匿名请求,不带 Authorization 头(v1.42.0)', () async {
    late http.Request seen;
    final ToolApiService s = serviceCapturing((req) => seen = req);
    await s.call(
      tool: _tool(apiPath: '/api/v1/random/string'),
      values: const <String, String>{},
    );
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('POST：JSON body + 字段名透传（base64 encode）', () async {
    late http.Request seen;
    final ToolApiService s = serviceCapturing(
      (req) => seen = req,
      body: '{"encoded":"aGVsbG8="}',
    );
    final ToolApiResult r = await s.call(
      tool: _tool(
        method: 'POST',
        apiPath: '/api/v1/text/base64/encode',
        params: const <ToolParam>[
          ToolParam(name: 'text', label: '原文'),
        ],
      ),
      values: const <String, String>{'text': 'hello'},
    );
    expect(seen.method, 'POST');
    expect(seen.headers['content-type'], contains('application/json'));
    final Map<String, dynamic> body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['text'], 'hello');
    expect(r.json, isNotNull);
  });

  test('POST body + query 混合（翻译 to_lang 走 query）', () async {
    late http.Request seen;
    final ToolApiService s = serviceCapturing(
      (req) => seen = req,
      body: '{"text":"hi","translate":"你好"}',
    );
    final ToolApiResult r = await s.call(
      tool: _tool(
        method: 'POST',
        apiPath: '/api/v1/translate/text',
        params: const <ToolParam>[
          ToolParam(name: 'to_lang', label: '目标语言', inQuery: true),
          ToolParam(name: 'text', label: '原文'),
        ],
      ),
      values: const <String, String>{'to_lang': 'zh', 'text': 'hi'},
    );
    expect(seen.url.queryParameters['to_lang'], 'zh');
    final Map<String, dynamic> body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body.containsKey('to_lang'), isFalse); // to_lang 不在 body。
    expect(body['text'], 'hi');
    expect(r.json, isNotNull);
  });

  test('图片接口 → bytes 双态返回（content-type image/png）', () async {
    final ToolApiService s = ToolApiService(
      client: MockClient((http.Request req) async {
        return http.Response.bytes(
          <int>[137, 80, 78, 71],
          200,
          headers: <String, String>{'content-type': 'image/png'},
        );
      }),
    );
    final ToolApiResult r = await s.call(
      tool: _tool(apiPath: '/api/v1/image/qrcode'),
      values: const <String, String>{},
    );
    expect(r.isBytes, isTrue);
    expect(r.json, isNull);
    expect(r.bytes, isNotNull);
  });

  test('400 → invalid + 服务端 message 覆盖展示文案', () async {
    final ToolApiService s = serviceCapturing(
      (_) {},
      status: 400,
      body: '{"code":"INVALID_PARAMETER","message":"无法解析目标地址"}',
    );
    try {
      await s.call(tool: _tool(), values: const <String, String>{});
      fail('应抛 ToolApiException');
    } on ToolApiException catch (e) {
      expect(e.error, ToolApiError.invalid);
      expect(e.message, '无法解析目标地址'); // 服务端 message 优先。
    }
  });

  test('404 → notFound；5xx → unavailable', () async {
    final ToolApiService s404 = serviceCapturing((_) {}, status: 404);
    try {
      await s404.call(tool: _tool(), values: const <String, String>{});
      fail('应抛');
    } on ToolApiException catch (e) {
      expect(e.error, ToolApiError.notFound);
    }
    final ToolApiService s500 = serviceCapturing((_) {}, status: 502);
    try {
      await s500.call(tool: _tool(), values: const <String, String>{});
      fail('应抛');
    } on ToolApiException catch (e) {
      expect(e.error, ToolApiError.unavailable);
    }
  });

  test('requiresAuth 无 key → needsKey；空值参数被过滤', () async {
    final ToolApiService s = serviceCapturing((_) {});
    try {
      await s.call(
        tool: _tool(
          requiresAuth: true,
          params: const <ToolParam>[
            ToolParam(name: 'text', label: '原文'),
          ],
        ),
        values: const <String, String>{'text': 'hello', 'extra': ''},
      );
      fail('应抛 needsKey');
    } on ToolApiException catch (e) {
      expect(e.error, ToolApiError.needsKey);
    }
  });

  test('file 参数 → multipart/form-data 上传 + query 携带(v1.41.0)', () async {
    // MockClient 内部按 utf8 解码 body，无法承载 multipart 二进制 →
    // 用自定义 BaseClient 捕获 finalize 后的原始字节流。
    final _CaptureClient capture = _CaptureClient();
    final ToolApiService s = ToolApiService(client: capture);
    final ToolApiResult r = await s.call(
      tool: _tool(
        method: 'POST',
        apiPath: '/api/v1/image/compress',
        params: const <ToolParam>[
          ToolParam(name: 'file', label: '图片', type: ToolParamType.file),
          ToolParam(name: 'level', label: '级别', inQuery: true),
        ],
      ),
      values: const <String, String>{'level': '3'},
      files: <String, Uint8List>{
        'file': Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3, 4]),
      },
    );
    expect(capture.uri?.queryParameters['level'], '3'); // query 正常携带。
    expect(capture.contentType, contains('multipart/form-data'));
    final String raw = String.fromCharCodes(capture.lastBody ?? Uint8List(0));
    expect(raw, contains('name="file"')); // 文件 part 字段名。
    expect(raw, contains('toki_file.png')); // PNG 魔数 → 补扩展名。
    expect(r.json, isNotNull);
  });
}

/// 捕获 multipart 原始字节的自定义客户端（MockClient 无法承载二进制）。
class _CaptureClient extends http.BaseClient {
  Uri? uri;
  String? contentType;
  Uint8List? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    uri = request.url;
    final http.ByteStream bs = request.finalize(); // 生成 boundary/头(同步)。
    contentType = request.headers['content-type'];
    lastBody = await bs.toBytes();
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(
        <List<int>>[utf8.encode('{"ok":true}')],
      ),
      200,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }
}
