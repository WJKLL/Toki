// lib/data/repositories/ledger_repository_impl.dart
// 编号：S-25 记账数据服务（实现：shared_preferences + JSON）
// 说明：与 todo/course/settings repository 同模式 —— 读走内存缓存（同步），
//   写全量 JSON 串异步落盘。key：
//   - ledger.entries     账目全量
//   - ledger.categories  分类全量（首读为空时播种内置预设并落盘）
// 功耗：getString 为内存读零 IO；写由调用方（Provider）节流。
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/ledger_category.dart';
import '../../domain/entities/ledger_entry.dart';
import '../../domain/repositories/ledger_repository.dart';

class LedgerRepositoryImpl implements LedgerRepository {
  LedgerRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;

  static const String _kEntries = 'ledger.entries';
  static const String _kCategories = 'ledger.categories';
  static const String _kBudget = 'ledger.budgetCents';

  @override
  List<LedgerEntry> loadEntries() {
    final String? raw = _prefs.getString(_kEntries);
    if (raw == null || raw.isEmpty) return const <LedgerEntry>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return <LedgerEntry>[
        for (final Object? o in list)
          if (o is Map<String, dynamic>) LedgerEntry.fromJson(o),
      ];
    } on FormatException {
      return const <LedgerEntry>[];
    }
  }

  @override
  Future<void> saveEntries(List<LedgerEntry> entries) async {
    await _prefs.setString(
      _kEntries,
      jsonEncode(<Map<String, dynamic>>[
        for (final LedgerEntry e in entries) e.toJson(),
      ]),
    );
  }

  @override
  List<LedgerCategory> loadCategories() {
    final String? raw = _prefs.getString(_kCategories);
    if (raw == null || raw.isEmpty) {
      // 首次启动：播种内置预设（异步落盘，本次同步返回内存副本）。
      final List<LedgerCategory> seeded = defaultLedgerCategories();
      unawaited(saveCategories(seeded));
      return seeded;
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final List<LedgerCategory> out = <LedgerCategory>[
        for (final Object? o in list)
          if (o is Map<String, dynamic>) LedgerCategory.fromJson(o),
      ];
      // 空表（用户删空）也回落到预设，避免记账无分类可用。
      return out.isEmpty ? defaultLedgerCategories() : out;
    } on FormatException {
      return defaultLedgerCategories();
    }
  }

  @override
  Future<void> saveCategories(List<LedgerCategory> categories) async {
    await _prefs.setString(
      _kCategories,
      jsonEncode(<Map<String, dynamic>>[
        for (final LedgerCategory c in categories) c.toJson(),
      ]),
    );
  }

  @override
  Future<void> resetCategories() async {
    await saveCategories(defaultLedgerCategories());
  }

  @override
  int loadBudgetCents() => _prefs.getInt(_kBudget) ?? 0;

  @override
  Future<void> saveBudgetCents(int cents) async {
    await _prefs.setInt(_kBudget, cents < 0 ? 0 : cents);
  }
}
