// test/steam_api_service_test.dart
// P-08 Steam 查询服务单元测试(v1.34.0):
//  输入 4 格式识别(detect)、UAPI summary 响应解析(实测字段;可选字段
//  缺失容错)、HTTP 状态 → 错误分类收敛。MockClient fixture,零真实网络。
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiangjugong/core/tools/steam_api_service.dart';
import 'package:xiangjugong/domain/entities/steam_user.dart';

/// 实测响应样本(用户 alexpenfold:无 realname/loccountrycode/timecreated
/// 之外的字段缺失情形在其它用例覆盖)。
const String _kFullJson =
    '{"steamid":"76561198012523355","steamid3":"[U:1:52257627]",'
    '"communityvisibilitystate":3,"profilestate":1,'
    '"personaname":"alexpenfold",'
    '"profileurl":"https://steamcommunity.com/profiles/76561198012523355/",'
    '"avatar":"https://avatars.steamstatic.com/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb.jpg",'
    '"avatarmedium":"https://avatars.steamstatic.com/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_medium.jpg",'
    '"avatarfull":"https://avatars.steamstatic.com/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg",'
    '"avatarhash":"fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb","personastate":0,'
    '"primaryclanid":"103582791429521408","timecreated":1249484586,'
    '"timecreated_str":"2009-08-05 23:03:06"}';

/// 全字段样本(公开 realname + 国家,用户 gabeloganewell 风格)。
const String _kRichJson =
    '{"steamid":"76561197960435530","steamid3":"[U:1:22202]",'
    '"communityvisibilitystate":3,"profilestate":1,"personaname":"Gabe Newell",'
    '"profileurl":"https://steamcommunity.com/id/gabeloganewell/",'
    '"avatarmedium":"https://avatars.steamstatic.com/x_medium.jpg",'
    '"avatarfull":"https://avatars.steamstatic.com/x_full.jpg",'
    '"personastate":1,"realname":"Gabe Logan Newell","loccountrycode":"US",'
    '"timecreated":1063407589,"timecreated_str":"2003-09-12 22:59:49"}';

SteamApiService serviceReturning(int status, String body) {
  return SteamApiService(
    client: MockClient((http.Request req) async {
      return http.Response(
        body,
        status,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  group('detect:4 格式识别', () {
    test('17 位纯数字 → steamid', () {
      final d = SteamApiService.detect('76561198012523355');
      expect(d, isNotNull);
      expect(d!.param, 'steamid');
      expect(d.value, '76561198012523355');
    });

    test('STEAM_x:y:z → id3', () {
      final d = SteamApiService.detect('STEAM_0:1:52257627');
      expect(d!.param, 'id3');
      expect(d.value, 'STEAM_0:1:52257627');
    });

    test('steamcommunity 完整链接 → steamid(服务端自识别)', () {
      final d = SteamApiService.detect(
        'https://steamcommunity.com/id/gabeloganewell/',
      );
      expect(d!.param, 'steamid');
    });

    test('自定义 URL 名(vanity)/好友代码 → steamid', () {
      expect(SteamApiService.detect('gabeloganewell')!.param, 'steamid');
      expect(SteamApiService.detect('22202')!.param, 'steamid');
    });

    test('空/纯空白 → null', () {
      expect(SteamApiService.detect(''), isNull);
      expect(SteamApiService.detect('   '), isNull);
    });

    test('前后空白剥离', () {
      final d = SteamApiService.detect('  76561198012523355 ');
      expect(d!.value, '76561198012523355');
    });
  });

  group('fetchSummary:URL 与解析', () {
    test('字段齐全:按 id3 请求 + key 参数 + 解析全部字段', () async {
      http.Request? captured;
      final SteamApiService service = SteamApiService(
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(
            _kRichJson,
            200,
            headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final SteamUser u = await service.fetchSummary(
        input: 'STEAM_0:0:22202',
        apiKey: 'secret-key',
      );
      expect(captured!.url.path, '/api/v1/game/steam/summary');
      expect(captured!.url.queryParameters['id3'], 'STEAM_0:0:22202');
      expect(captured!.url.queryParameters['key'], 'secret-key');
      expect(captured!.url.queryParameters.containsKey('steamid'), isFalse);
      expect(u.steamid, '76561197960435530');
      expect(u.steamid3, '[U:1:22202]');
      expect(u.personaname, 'Gabe Newell');
      expect(u.realNameOrNull, 'Gabe Logan Newell');
      expect(u.countryCode, 'US');
      expect(u.personaState, 1);
      expect(u.isPublic, isTrue);
      expect(u.createdDate, '2003-09-12');
    });

    test('可选字段缺失容错(无 realname/国家)仍解析', () async {
      final SteamUser u = await serviceReturning(200, _kFullJson)
          .fetchSummary(input: '76561198012523355');
      expect(u.steamid, '76561198012523355');
      expect(u.realNameOrNull, isNull);
      expect(u.countryCode, isNull);
      expect(u.personaState, 0);
      expect(u.createdDate, '2009-08-05');
    });

    test('无 key(匿名)→ 请求不含 key 参数', () async {
      http.Request? captured;
      final SteamApiService service = SteamApiService(
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(_kFullJson, 200);
        }),
      );
      await service.fetchSummary(input: '76561198012523355');
      expect(captured!.url.queryParameters.containsKey('key'), isFalse);
    });

    test('200 但非对象(结构异常)→ parse', () async {
      expect(
        () => serviceReturning(200, '[1,2,3]').fetchSummary(input: 'x'),
        throwsA(isA<SteamFetchException>().having(
          (e) => e.error,
          'error',
          SteamFetchError.parse,
        )),
      );
    });

    test('200 但缺 steamid → parse', () async {
      expect(
        () => serviceReturning(200, '{"personaname":"no id"}')
            .fetchSummary(input: 'x'),
        throwsA(isA<SteamFetchException>().having(
          (e) => e.error,
          'error',
          SteamFetchError.parse,
        )),
      );
    });
  });

  group('fetchSummary:HTTP 状态 → 错误分类', () {
    Future<void> expectError(int status, SteamFetchError expected) async {
      expect(
        () => serviceReturning(status, '{}').fetchSummary(input: 'x'),
        throwsA(isA<SteamFetchException>().having(
          (e) => e.error,
          'error',
          expected,
        )),
      );
    }

    test('400 → invalid', () => expectError(400, SteamFetchError.invalid));
    test('401 → unauthorized', () => expectError(401, SteamFetchError.unauthorized));
    test('404 → notFound', () => expectError(404, SteamFetchError.notFound));
    test('502 → unavailable', () => expectError(502, SteamFetchError.unavailable));
    test('500 → unavailable', () => expectError(500, SteamFetchError.unavailable));
  });

  group('实体:状态枚举与可见性', () {
    test('personastate 0-6 文案映射', () {
      expect(SteamUserState.of(0).label, '离线');
      expect(SteamUserState.of(1).label, '在线');
      expect(SteamUserState.of(2).label, '忙碌');
      expect(SteamUserState.of(3).label, '离开');
      expect(SteamUserState.of(4).label, '打盹');
      expect(SteamUserState.of(5).label, '想交易');
      expect(SteamUserState.of(6).label, '想玩');
      expect(SteamUserState.of(99), SteamUserState.offline); // 越界容错
    });

    test('可见性 1=私密 3=公开', () {
      expect(
        SteamUser.fromJson(<String, dynamic>{
          'steamid': '1',
          'communityvisibilitystate': 1,
        }).isPublic,
        isFalse,
      );
    });
  });
}
