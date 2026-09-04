// lib/core/tools/steam_api_service.dart
// 编号：P-08 Steam 用户查询 · 联网服务（v1.34.0 新增）
// 说明：UAPI `GET https://uapis.cn/api/v1/game/steam/summary` 归一客户端
//   (Endpoint 经用户确认;匿名可用,key 可选 query 参数 —— 见 S-07 文档)。
//   - 输入识别(4 格式):STEAM_x:y:z → id3 参数;其余(17 位 SteamID64 /
//     自定义 URL 名 / 完整资料链接 / 好友代码)统一走 steamid 参数 ——
//     UAPI 官方文档:steamid 参数即接受上述全部格式(仅 ID3 需单列)。
//   - 失败统一抛 [SteamFetchException](code + 中文提示),调用方直接展示;
//   - http.Client 可注入(单元测试 fixture 客户端,与 S-21 同模式)。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/steam_user.dart';

/// 拉取失败分类(UI 按类展示提示;文案已本地化)。
enum SteamFetchError {
  /// 输入无法识别(理论上 UI 已前置过滤,防御)。
  invalid('无法识别的输入,请检查后重试'),

  /// 401:密钥无效 / 未授权(匿名池繁忙时也可能出现)。
  unauthorized('API 密钥无效或服务繁忙,请稍后重试'),

  /// 404:查无此人 / 资料完全私密。
  notFound('未找到该用户,或资料完全私密'),

  /// 502 / 其它非 2xx:服务端暂时不可用。
  unavailable('服务暂时不可用,请稍后重试'),

  /// 网络 / 超时。
  network('网络错误,请检查连接后重试'),

  /// 响应解析失败(结构异常)。
  parse('服务返回异常,请稍后重试');

  const SteamFetchError(this.message);

  final String message;
}

/// 拉取失败(携带分类,UI 可特殊处理)。
class SteamFetchException implements Exception {
  const SteamFetchException(this.error);

  final SteamFetchError error;

  @override
  String toString() => 'SteamFetchException: ${error.name}';
}

/// Steam 用户查询服务(P-08)。
class SteamApiService {
  SteamApiService({http.Client? client, this.timeout = const Duration(seconds: 10)})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static final RegExp _id3Pattern = RegExp(r'^STEAM_[0-9]:[0-9]:[0-9]+$');

  /// 识别输入 → (参数名, 参数值);空输入返回 null。
  /// 规则(与查询页帮助小字一致):
  ///   - `STEAM_x:y:z` → id3;
  ///   - 17 位纯数字 / steamcommunity.com 链接 / 自定义 URL 名 /
  ///     好友代码 → steamid(参数万能,服务端自识别)。
  static ({String param, String value})? detect(String raw) {
    final String input = raw.trim();
    if (input.isEmpty) return null;
    if (_id3Pattern.hasMatch(input)) return (param: 'id3', value: input);
    return (param: 'steamid', value: input);
  }

  /// 查询公开摘要。
  Future<SteamUser> fetchSummary({
    required String input,
    String? apiKey,
  }) async {
    final ({String param, String value})? detected = detect(input);
    if (detected == null) {
      throw const SteamFetchException(SteamFetchError.invalid);
    }
    final Map<String, String> query = <String, String>{
      detected.param: detected.value,
    };
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      query['key'] = apiKey.trim();
    }
    final Uri uri = Uri.parse('https://uapis.cn/api/v1/game/steam/summary')
        .replace(queryParameters: query);

    final http.Response resp;
    try {
      resp = await _client
          .get(uri, headers: const <String, String>{'User-Agent': 'Mozilla/5.0'})
          .timeout(timeout);
    } on TimeoutException {
      throw const SteamFetchException(SteamFetchError.network);
    } on http.ClientException {
      throw const SteamFetchException(SteamFetchError.network);
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return _parseBody(resp.bodyBytes);
    }
    throw _errorForStatus(resp.statusCode);
  }

  SteamFetchException _errorForStatus(int status) {
    // 400/401/404 响应体含 {code, message};分类按 HTTP 状态即足够。
    return switch (status) {
      400 => const SteamFetchException(SteamFetchError.invalid),
      401 => const SteamFetchException(SteamFetchError.unauthorized),
      404 => const SteamFetchException(SteamFetchError.notFound),
      _ => const SteamFetchException(SteamFetchError.unavailable),
    };
  }

  SteamUser _parseBody(List<int> bodyBytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
    } on FormatException {
      throw const SteamFetchException(SteamFetchError.parse);
    }
    if (decoded is! Map) {
      throw const SteamFetchException(SteamFetchError.parse);
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(decoded);
    // 防御:成功但缺 steamid(结构异常)→ parse。
    final Object? steamid = json['steamid'];
    if (steamid is! String || steamid.trim().isEmpty) {
      throw const SteamFetchException(SteamFetchError.parse);
    }
    return SteamUser.fromJson(json);
  }
}
