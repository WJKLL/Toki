// lib/domain/entities/steam_user.dart
// 编号：P-08 Steam 用户查询 · 领域实体（v1.34.0 新增）
// 说明：UAPI /game/steam/summary 响应归一模型(实测字段;可选字段全部容错,
//   真实世界大量用户无 realname/loccountrycode)。纯领域,不依赖 UI 框架。
class SteamUser {
  const SteamUser({
    required this.steamid,
    required this.steamid3,
    required this.personaname,
    required this.profileurl,
    required this.avatarMedium,
    required this.avatarFull,
    required this.personaState,
    required this.communityVisibility,
    this.realName,
    this.countryCode,
    this.timecreated,
    this.timecreatedStr,
  });

  /// 64 位 SteamID(7656119…)。
  final String steamid;

  /// ID3 表示(如 [U:1:52257627])。
  final String steamid3;

  /// 当前昵称。
  final String personaname;

  /// 社区资料页完整 URL。
  final String profileurl;

  /// 64×64 头像。
  final String avatarMedium;

  /// 184×184 头像。
  final String avatarFull;

  /// 在线状态(0-6,见 [SteamUserState]);缺失按 0(离线)容错。
  final int personaState;

  /// 资料可见性(1 私密 / 3 公开);缺失按 1 容错。
  final int communityVisibility;

  /// 真实姓名(未公开为 null)。
  final String? realName;

  /// 国家代码(ISO 3166-1;未公开为 null)。
  final String? countryCode;

  /// 注册时间(Unix 秒;缺失为 null)。
  final int? timecreated;

  /// 服务端格式化注册时间(如 '2009-08-05 23:03:06')。
  final String? timecreatedStr;

  bool get isPublic => communityVisibility == 3;

  /// 展示用注册日期(取 timecreated_str 前 10 位 yyyy-MM-dd;缺失空串)。
  String get createdDate {
    final String? s = timecreatedStr;
    if (s != null && s.length >= 10) return s.substring(0, 10);
    return '';
  }

  /// 真实姓名(空串归一为 null)。
  String? get realNameOrNull {
    final String? v = realName;
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  static SteamUser fromJson(Map<String, dynamic> json) {
    String s(Object? v) => v is String ? v.trim() : '';
    int i(Object? v, [int fallback = 0]) => v is int ? v : fallback;
    return SteamUser(
      steamid: s(json['steamid']),
      steamid3: s(json['steamid3']),
      personaname: s(json['personaname']),
      profileurl: s(json['profileurl']),
      avatarMedium: s(json['avatarmedium']),
      avatarFull: s(json['avatarfull']),
      personaState: i(json['personastate']),
      communityVisibility: i(json['communityvisibilitystate'], 1),
      realName: s(json['realname']).isEmpty ? null : s(json['realname']),
      countryCode: s(json['loccountrycode']).isEmpty
          ? null
          : s(json['loccountrycode']),
      timecreated: json['timecreated'] is int ? json['timecreated'] as int : null,
      timecreatedStr: s(json['timecreated_str']).isEmpty
          ? null
          : s(json['timecreated_str']),
    );
  }
}

/// Steam 在线状态(0-6;UAPI 官方语义 + 展示标签)。
enum SteamUserState {
  offline(0, '离线'),
  online(1, '在线'),
  busy(2, '忙碌'),
  away(3, '离开'),
  snooze(4, '打盹'),
  trade(5, '想交易'),
  play(6, '想玩');

  const SteamUserState(this.value, this.label);

  final int value;
  final String label;

  /// 按数值取状态;越界回离线(0)。
  static SteamUserState of(int value) {
    for (final SteamUserState s in SteamUserState.values) {
      if (s.value == value) return s;
    }
    return SteamUserState.offline;
  }
}
