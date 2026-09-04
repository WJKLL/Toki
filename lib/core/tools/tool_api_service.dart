// === 文件: lib/core/tools/tool_api_service.dart ===
// 编号：P-09 通用工具 · 统一调用管道（v1.35.0 新增，C-40/C-41/P-09 共用）
// 说明：UAPI 批量工具的统一请求层 —— 参数由 tools.json 配置驱动，新增工具
//   不改代码（复用率目标 >90%）。
//   - 方法：GET(query) / POST(json body) / POST(json body + query 混合)，
//     参数归属由 ToolParam.inQuery 决定（实测：翻译 to_lang 走 query）；
//   - **双态返回**：JSON 接口返回 [ToolApiResult.json]，图片接口返回
//     [ToolApiResult.bytes]（实测必应壁纸/二维码/新闻图直接返回图片字节；
//     http 默认 followRedirects 自动跟随 302 —— 随机图片）；
//   - 错误统一 [ToolApiException]（分类 + 服务端 message 优先展示）；
//   - 并发限制（默认 3）+ 同参数在途去重（复用同一 Future）；
//   - http.Client 可注入（单元测试 fixture，与 SteamApiService/S-21 同模式）。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/entities/tool_config.dart';
import '../constants/app_constants.dart';

/// 调用失败分类（UI 按类提示；文案本地化，服务端 message 可覆盖展示）。
enum ToolApiError {
  /// 400：参数/输入无法识别。
  invalid('参数无效，请检查后重试'),

  /// 401/403：key 无效 / 未授权。
  unauthorized('API 密钥无效或服务繁忙'),

  /// requiresAuth 工具但未配置 key。
  needsKey('需要 UAPI 密钥，请先配置'),

  /// 404：查无结果 / 资源不可用。
  notFound('未找到结果，或内容不可用'),

  /// 429 / 5xx：限流或服务端暂时不可用。
  unavailable('服务暂时不可用，请稍后重试'),

  /// 网络 / 超时。
  network('网络错误，请检查连接后重试'),

  /// 响应解析失败（结构异常）。
  parse('服务返回异常，请稍后重试');

  const ToolApiError(this.message);

  final String message;
}

/// 调用失败（携带分类 + 服务端 message 优先）。
class ToolApiException implements Exception {
  const ToolApiException(this.error, [this.serverMessage]);

  final ToolApiError error;

  /// 服务端错误体 `{code,message}` 的 message（中文提示优先展示）。
  final String? serverMessage;

  /// UI 直接展示的文案。
  String get message => (serverMessage == null || serverMessage!.isEmpty)
      ? error.message
      : serverMessage!;

  @override
  String toString() => 'ToolApiException: ${error.name}';
}

/// 调用结果：json / bytes / text 三态（按响应 content-type 判定）。
class ToolApiResult {
  const ToolApiResult({this.json, this.bytes, this.text});

  /// JSON 响应（Map 或 List；成功接口外层均为对象）。
  final Object? json;

  /// 二进制响应（图片字节流；displayType=image 用 Image.memory 渲染）。
  final Uint8List? bytes;

  /// 纯文本兜底（非 JSON 且非图片）。
  final String? text;

  bool get isBytes => bytes != null;
}

/// 轻量信号量（并发限制）。
class _Semaphore {
  _Semaphore(this.max);

  final int max;
  int _used = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<void> acquire() async {
    if (_used < max) {
      _used++;
      return;
    }
    final Completer<void> c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _used--;
    }
  }
}

/// 通用工具调用服务（v1.35.0）。
class ToolApiService {
  ToolApiService({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    int maxConcurrent = 3,
  }) : _client = client ?? http.Client(),
       _sem = _Semaphore(maxConcurrent);

  final http.Client _client;
  final Duration timeout;
  final _Semaphore _sem;

  /// 在途请求去重表（key = 方法+路径+参数+key；完成即移除）。
  final Map<String, Future<ToolApiResult>> _inflight =
      <String, Future<ToolApiResult>>{};

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'Mozilla/5.0',
  };

  /// 调用一个工具。参数 [values] = 参数名 → 用户输入值（已过滤空值）。
  /// [apiKey] 可选：非空自动加 query `key`（UAPI 惯例；匿名可用）。
  Future<ToolApiResult> call({
    required ToolConfig tool,
    required Map<String, String> values,
    String? apiKey,
  }) async {
    if (tool.requiresAuth && (apiKey == null || apiKey.trim().isEmpty)) {
      throw const ToolApiException(ToolApiError.needsKey);
    }
    await _sem.acquire();
    final String key = _requestKey(tool, values, apiKey);
    final Future<ToolApiResult>? existing = _inflight[key];
    if (existing != null) {
      // 在途同参请求：复用，不重复发起。
      _sem.release();
      return existing;
    }
    final Future<ToolApiResult> future = _perform(
      tool,
      values,
      apiKey,
    ).whenComplete(() {
      // ignore: discarded_futures —— Map.remove 返回被移除的 Future 值，此处仅清表。
      _inflight.remove(key);
      _sem.release();
    });
    _inflight[key] = future;
    return future;
  }

  String _requestKey(
    ToolConfig tool,
    Map<String, String> values,
    String? apiKey,
  ) {
    final List<String> kvs = <String>[
      for (final MapEntry<String, String> e in values.entries)
        '${e.key}=${e.value}',
    ]..sort();
    return '${tool.method}|${tool.apiPath}|${kvs.join('&')}|$apiKey';
  }

  Future<ToolApiResult> _perform(
    ToolConfig tool,
    Map<String, String> values,
    String? apiKey,
  ) async {
    final bool get = tool.method != 'POST';
    final Map<String, String> query = <String, String>{};
    final Map<String, String> body = <String, String>{};
    for (final ToolParam p in tool.params) {
      final String? v = values[p.name];
      if (v == null || v.isEmpty) continue;
      (get || p.inQuery ? query : body)[p.name] = v;
    }
    final String key = apiKey == null ? '' : apiKey.trim();
    if (key.isNotEmpty) query['key'] = key;

    final Uri uri = Uri.parse(
      '${AppConstants.uapiBaseUrl}${tool.apiPath}',
    ).replace(queryParameters: query.isEmpty ? null : query);

    final http.Response resp;
    try {
      if (get) {
        resp = await _client.get(uri, headers: _headers).timeout(timeout);
      } else {
        resp = await _client
            .post(
              uri,
              headers: <String, String>{
                ..._headers,
                'Content-Type': 'application/json',
              },
              body: body.isEmpty ? '{}' : jsonEncode(body),
            )
            .timeout(timeout);
      }
    } on TimeoutException {
      throw const ToolApiException(ToolApiError.network);
    } on http.ClientException {
      throw const ToolApiException(ToolApiError.network);
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _errorForStatus(
        resp.statusCode,
        utf8.decode(resp.bodyBytes, allowMalformed: true),
      );
    }
    return _parseResult(resp);
  }

  ToolApiException _errorForStatus(int status, String bodyText) {
    String? serverMessage;
    try {
      final Object? decoded = jsonDecode(bodyText);
      if (decoded is Map<String, dynamic>) {
        final Object? m = decoded['message'];
        if (m is String && m.trim().isNotEmpty) serverMessage = m.trim();
      }
    } on FormatException {
      // 非 JSON 错误体：忽略，用分类文案。
    }
    final ToolApiError error = switch (status) {
      400 => ToolApiError.invalid,
      401 || 403 => ToolApiError.unauthorized,
      404 => ToolApiError.notFound,
      429 => ToolApiError.unavailable,
      _ when status >= 500 => ToolApiError.unavailable,
      _ => ToolApiError.unavailable,
    };
    return ToolApiException(error, serverMessage);
  }

  ToolApiResult _parseResult(http.Response resp) {
    final String ct =
        (resp.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('image') ||
        ct.contains('octet-stream') ||
        ct.contains('audio') ||
        ct.contains('video') ||
        ct.contains('font')) {
      return ToolApiResult(bytes: Uint8List.fromList(resp.bodyBytes));
    }
    final String text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (text.trim().isEmpty) return ToolApiResult(text: text);
    try {
      return ToolApiResult(json: jsonDecode(text));
    } on FormatException {
      return ToolApiResult(text: text);
    }
  }
}
