// lib/data/repositories/settings_repository_impl.dart
// 编号：S-02 设置存储服务（实现：shared_preferences，读写合并 + 防抖落盘）
// 功耗要点：读全部走内存缓存；写统一走 300ms 防抖 Timer 合并，滑动/连点场景
//          只落盘一次，避免高频 IO 唤醒（§11.6）。
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/class_period.dart';
import '../../domain/entities/daily_quote.dart';
import '../../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._prefs, {this.debounceDuration = _kDebounce});

  final SharedPreferences _prefs;
  final Duration debounceDuration;

  static const Duration _kDebounce = Duration(milliseconds: 300);
  static const String _kUiMode = 'settings.uiMode';
  static const String _kMonetEnabled = 'settings.monetEnabled';
  static const String _kKeyColor = 'settings.keyColor';
  static const String _kPaletteStyle = 'settings.paletteStyle';
  static const String _kBlurEnabled = 'settings.blurEnabled';
  static const String _kFloatingBarEnabled = 'settings.floatingBarEnabled';
  static const String _kPageScale = 'settings.pageScale';
  static const String _kLogCaptureEnabled = 'settings.logCaptureEnabled';
  // v1.21.0:全局节次时间表(16 项 JSON 单串,<1KB)。
  static const String _kClassPeriods = 'settings.classPeriods';
  // v1.22.0:首页网格卡顺序(id 列表 JSON,<300B)。
  static const String _kCardOrder = 'settings.cardOrder';
  // v1.26.0(S-21):每日一言当日缓存(单条 JSON,<1KB)。
  static const String _kQuoteCache = 'settings.dailyQuoteCache';
  // v1.26.0/v1.27.0(S-21):每日一言开关/API 来源/风格/语言
  // (并入 AppSettings 批量防抖)。
  static const String _kQuoteEnabled = 'settings.quoteEnabled';
  static const String _kQuoteApi = 'settings.quoteApi';
  static const String _kQuoteStyle = 'settings.quoteStyle';
  // v1.27.0:语言档(仅 UAPI 生效;'zh'/'en'/'mix')。
  static const String _kQuoteLang = 'settings.quoteLang';
  // v1.36.0:课程提醒总开关。
  static const String _kCourseReminderEnabled = 'settings.courseReminderEnabled';

  Timer? _debounce;
  AppSettings? _pending;

  // v1.22.0:卡片顺序独立防抖(拖拽松手单次写,与设置写盘互不干扰)。
  Timer? _orderDebounce;
  Map<String, List<String>>? _pendingOrder;

  @override
  AppSettings load() {
    // SharedPreferences 为内存缓存，get* 为同步读，零 IO、零帧耗。
    final String? palette = _prefs.getString(_kPaletteStyle);
    final int? keyColorInt = _prefs.getInt(_kKeyColor);
    return AppSettings(
      uiMode:
          AppUiMode.values.asNameMap()[_prefs.getString(_kUiMode)] ??
          AppUiMode.system,
      monetEnabled: _prefs.getBool(_kMonetEnabled) ?? false,
      keyColor: keyColorInt == null ? null : Color(keyColorInt),
      paletteStyle: palette ?? 'tonalSpot',
      blurEnabled: _prefs.getBool(_kBlurEnabled) ?? true,
      // 🔧 修复（S-02）：悬浮底栏开关持久化读取——应用启动时恢复上次状态
      //    （main() → ProviderScope 注入 → AppSettingsController.build → load()）。
      floatingBarEnabled: _prefs.getBool(_kFloatingBarEnabled) ?? false,
      pageScale: _prefs.getDouble(_kPageScale) ?? 1.0,
      logCaptureEnabled: _prefs.getBool(_kLogCaptureEnabled) ?? false,
      classPeriods: _decodePeriods(_prefs.getString(_kClassPeriods)),
      quoteEnabled: _prefs.getBool(_kQuoteEnabled) ?? true,
      quoteApi: _prefs.getString(_kQuoteApi) ?? 'hitokoto',
      quoteStyle: _prefs.getString(_kQuoteStyle) ?? 'classic',
      quoteLang: _prefs.getString(_kQuoteLang) ?? 'zh',
      courseReminderEnabled:
          _prefs.getBool(_kCourseReminderEnabled) ?? true,
    );
  }

  /// 节次时间表解码:坏数据/长度异常 → 归一化(截断/模板补齐),绝不崩溃。
  static List<ClassPeriod> _decodePeriods(String? raw) {
    if (raw == null || raw.isEmpty) return ClassPeriod.defaults;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return ClassPeriod.defaults;
      final List<ClassPeriod> list = <ClassPeriod>[];
      for (final Object? item in decoded) {
        if (item is Map) {
          list.add(ClassPeriod.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      if (list.isEmpty) return ClassPeriod.defaults;
      return ClassPeriod.normalize(list);
    } catch (_) {
      return ClassPeriod.defaults; // 容错:解析失败回默认模板。
    }
  }

  @override
  void save(AppSettings settings) {
    // ⚡ 功耗优化：防抖合并——300ms 内的连续变更只写盘一次；
    //   每次 save 只保留最新快照，Timer 触发时执行最后一次写。
    _pending = settings;
    _debounce?.cancel();
    _debounce = Timer(debounceDuration, _flush);
  }

  Future<void> _flush() async {
    final AppSettings? s = _pending;
    _pending = null;
    if (s == null) return;
    // 一次性批量写盘（减少 SharedPreferences 通道次数）。
    await _prefs.setString(_kUiMode, s.uiMode.name);
    await _prefs.setBool(_kMonetEnabled, s.monetEnabled);
    final int? keyColor = s.keyColor?.toARGB32();
    if (keyColor == null) {
      await _prefs.remove(_kKeyColor);
    } else {
      await _prefs.setInt(_kKeyColor, keyColor);
    }
    await _prefs.setString(_kPaletteStyle, s.paletteStyle);
    await _prefs.setBool(_kBlurEnabled, s.blurEnabled);
    // 🔧 修复（S-02）：悬浮底栏开关持久化写回（防抖合并后批量落盘）。
    await _prefs.setBool(_kFloatingBarEnabled, s.floatingBarEnabled);
    await _prefs.setDouble(_kPageScale, s.pageScale);
    await _prefs.setBool(_kLogCaptureEnabled, s.logCaptureEnabled);
    // v1.21.0:节次时间表整表单串写(与其余设置同批落盘)。
    await _prefs.setString(
      _kClassPeriods,
      jsonEncode(<Map<String, dynamic>>[
        for (final ClassPeriod p in s.classPeriods) p.toJson(),
      ]),
    );
    // v1.26.0/v1.27.0(S-21):每日一言设置四键同批落盘。
    await _prefs.setBool(_kQuoteEnabled, s.quoteEnabled);
    await _prefs.setString(_kQuoteApi, s.quoteApi);
    await _prefs.setString(_kQuoteStyle, s.quoteStyle);
    await _prefs.setString(_kQuoteLang, s.quoteLang);
  }

  @override
  void dispose() {
    // ⚡ 功耗优化：防抖 Timer 必须取消（否则 App 退出后仍会唤醒落盘）。
    _debounce?.cancel();
    _debounce = null;
    _orderDebounce?.cancel();
    _orderDebounce = null;
  }

  // ── v1.22.0/v1.23.1:首页网格卡顺序(竖/横各一套,单 key 对象)────────

  @override
  ({List<String>? portrait, List<String>? landscape}) loadCardOrder() {
    final String? raw = _prefs.getString(_kCardOrder);
    if (raw == null || raw.isEmpty) {
      return (portrait: null, landscape: null);
    }
    try {
      final Object? decoded = jsonDecode(raw);
      // 新格式:{"p": [...], "l": [...]}
      if (decoded is Map) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
        return (
          portrait: _decodeIdList(map['p']),
          landscape: _decodeIdList(map['l']),
        );
      }
      // 旧格式:id 数组 → 两方向共用(迁移语义,下次保存写回新格式)。
      if (decoded is List) {
        final List<String>? ids = _decodeIdList(decoded);
        return (portrait: ids, landscape: ids);
      }
      return (portrait: null, landscape: null);
    } catch (_) {
      return (portrait: null, landscape: null); // 坏数据 → 默认顺序。
    }
  }

  static List<String>? _decodeIdList(Object? raw) {
    if (raw is! List) return null;
    final List<String> out = <String>[];
    for (final Object? item in raw) {
      if (item is String && item.isNotEmpty) out.add(item);
    }
    return out.isEmpty ? null : out;
  }

  @override
  void saveCardOrder({
    required List<String> portrait,
    required List<String> landscape,
  }) {
    // 防抖合并:拖拽连发只落盘一次(与 AppSettings 写盘通道分开)。
    _pendingOrder = <String, List<String>>{'p': portrait, 'l': landscape};
    _orderDebounce?.cancel();
    _orderDebounce = Timer(_kDebounce, _flushOrder);
  }

  Future<void> _flushOrder() async {
    final Map<String, List<String>>? order = _pendingOrder;
    _pendingOrder = null;
    if (order == null) return;
    await _prefs.setString(
      _kCardOrder,
      jsonEncode(<String, Object>{
        'p': order['p'] ?? const <String>[],
        'l': order['l'] ?? const <String>[],
      }),
    );
  }

  // ── v1.26.0(S-21):每日一言当日缓存(独立 key,单条直接读写)───────

  @override
  DailyQuote? loadQuoteCache() {
    final String? raw = _prefs.getString(_kQuoteCache);
    if (raw == null || raw.isEmpty) return null;
    try {
      return DailyQuote.fromJson(jsonDecode(raw));
    } catch (_) {
      return null; // 坏数据 → null(调用方请求新内容)。
    }
  }

  @override
  void saveQuoteCache(DailyQuote quote) {
    // 每日仅 1~2 次写,无需防抖;失败静默(下次启动重取)。
    unawaited(_prefs.setString(_kQuoteCache, jsonEncode(quote.toJson())));
  }

  // ── v1.34.0(P-08):首页工具目录(settings.homeToolItems,独立 key)───

  static const String _kHomeToolItems = 'settings.homeToolItems';

  @override
  List<String> loadHomeToolItems() {
    final String? raw = _prefs.getString(_kHomeToolItems);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      final List<String> out = <String>[];
      for (final Object? item in decoded) {
        if (item is String && item.isNotEmpty) out.add(item);
      }
      return out;
    } catch (_) {
      return const <String>[]; // 坏数据 → 空(不追加动态卡)。
    }
  }

  @override
  void saveHomeToolItems(List<String> toolIds) {
    // 低频操作(长按添加/移除),直接写盘,失败静默。
    unawaited(
      _prefs.setString(
        _kHomeToolItems,
        jsonEncode(<String>[
          for (final String id in toolIds)
            if (id.isNotEmpty) id,
        ]),
      ),
    );
  }
}
