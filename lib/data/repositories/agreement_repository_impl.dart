// lib/data/repositories/agreement_repository_impl.dart
// 编号:S-20 用户协议状态服务(实现:shared_preferences,v1.20.0)
// 说明:同意状态 + 版本号整体落盘,单次 setBool/setString <1KB;
//   同步读(启动时 prefs 已内存化),异步写;与 S-02 共用 prefs 实例。
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/agreement_repository.dart';

class AgreementRepositoryImpl implements AgreementRepository {
  AgreementRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  /// key 命名遵循「模块.字段」惯例(与 settings.* / daily.activity 一致)。
  static const String _kAccepted = 'user_agreement_accepted';
  static const String _kVersion = 'user_agreement_version';

  @override
  ({bool accepted, String version}) load() {
    return (
      accepted: _prefs.getBool(_kAccepted) ?? false,
      version: _prefs.getString(_kVersion) ?? '',
    );
  }

  @override
  Future<void> save({required bool accepted, required String version}) async {
    await _prefs.setBool(_kAccepted, accepted);
    if (accepted) {
      await _prefs.setString(_kVersion, version);
    } else {
      await _prefs.remove(_kVersion);
    }
  }
}
