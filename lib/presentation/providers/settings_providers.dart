// lib/presentation/providers/settings_providers.dart
// 编号：S-01 主题服务（Riverpod 状态机）+ S-02 设置存储（注入）
// 说明：
//   - AppSettingsController 是唯一写入口；每次变更 → 新状态 → 防抖持久化（S-02）。
//   - 派生 Provider（effectiveBlurProvider 等）只暴露最小状态切片，
//     订阅方用 Consumer + select 精确监听，避免无关 Widget 重建（§11.2.2）。
//   - paletteStyle 字符串键 ↔ MiuixThemePaletteStyle 映射在 appTheme 完成（F-08）。
import 'package:flutter/material.dart' show Color;
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_log_service.dart';
import '../../core/utils/u03_blur_policy.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/class_period.dart';
import '../../domain/entities/daily_quote.dart';
import '../../domain/repositories/settings_repository.dart';
import 'platform_providers.dart';

/// S-02 仓储注入点：main() 中以 overrideWithValue 覆盖。
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError('settingsRepositoryProvider 必须在 main() 中 override');
});

/// S-01 主题状态机控制器（Riverpod 3 Notifier）。
final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettingsController extends Notifier<AppSettings> {
  SettingsRepository? _repository;

  @override
  AppSettings build() {
    final SettingsRepository repo = ref.read(settingsRepositoryProvider);
    _repository = repo;
    // ⚡ 功耗优化：Provider 销毁时释放防抖 Timer，避免后台落盘唤醒。
    ref.onDispose(repo.dispose);
    return repo.load();
  }

  void _update(AppSettings next) {
    state = next;
    // v1.10.3（S-13 覆盖增强）：设置变更日志（开关关闭时零成本）。
    AppLogService.instance.info(
      'settings',
      '设置变更: uiMode=${next.uiMode.name}'
          ' monet=${next.monetEnabled} blur=${next.blurEnabled}'
          ' floating=${next.floatingBarEnabled} pageScale=${next.pageScale}'
          ' log=${next.logCaptureEnabled}',
    );
    // ⚡ 功耗优化：写回走 S-02 防抖合并（300ms），连续变更只落盘一次。
    _repository?.save(next);
  }

  void setUiMode(AppUiMode mode) => _update(state.copyWith(uiMode: mode));

  /// 深色模式开关（主题页）：null=跟随系统。
  void setDarkOverride(bool? dark) {
    final AppUiMode mode = dark == null
        ? AppUiMode.system
        : (dark ? AppUiMode.dark : AppUiMode.light);
    _update(state.copyWith(uiMode: mode));
  }

  void setMonetEnabled(bool enabled) =>
      _update(state.copyWith(monetEnabled: enabled));

  void setKeyColor(Color? color) =>
      _update(state.copyWith(keyColor: color, clearKeyColor: color == null));

  void setPaletteStyle(String style) {
    // 🔧 修复：仅接受已登记风格键——未知键（旧持久化脏数据）直接忽略，
    //   杜绝"功能已生效但分段高亮错位/不更新"（高亮索引与 S-01 色板映射同源）。
    if (!kPaletteStyleOptions.contains(style)) return;
    _update(state.copyWith(paletteStyle: style));
  }

  void setBlurEnabled(bool enabled) =>
      _update(state.copyWith(blurEnabled: enabled));

  /// v1.21.0:节次时间表整表替换(16 项;UI 每次行提交 → 防抖单次落盘)。
  void setClassPeriods(List<ClassPeriod> periods) =>
      _update(state.copyWith(classPeriods: ClassPeriod.normalize(periods)));

  void setFloatingBarEnabled(bool enabled) =>
      _update(state.copyWith(floatingBarEnabled: enabled));

  void setPageScale(double scale) => _update(state.copyWith(pageScale: scale));

  /// 日志采集开关（S-13/S-14，v1.9.0）：写入 S-01 状态 → 持久化；
  ///   AppLogService/PerfMonitor 的 enabled 由 XiangJuGongApp 同步。
  void setLogCaptureEnabled(bool enabled) =>
      _update(state.copyWith(logCaptureEnabled: enabled));

  // ── v1.26.0（S-21）：每日一言设置 ─────────────────────────────

  void setQuoteEnabled(bool enabled) =>
      _update(state.copyWith(quoteEnabled: enabled));

  // ── v1.36.0：课程提醒开关 ────────────────────────────────────

  void setCourseReminderEnabled(bool enabled) =>
      _update(state.copyWith(courseReminderEnabled: enabled));

  /// 切换 API 来源（白名单校验）;风格联动:
  /// 目标 API 支持多风格且当前风格不在其支持集 → 回落到该 API 默认风格;
  /// 固定风格 API(支持集为空)→ 风格键保留不动(风格行隐藏)。
  void setQuoteApi(String api) {
    if (!kQuoteApiOptions.contains(api)) return; // 未知键忽略(脏数据防御)。
    final QuoteApi target = QuoteApi.fromKey(api);
    final String current = state.quoteStyle;
    String? reset;
    if (target.supportsStyles &&
        !target.styles.contains(QuoteStyle.fromKey(current))) {
      reset = target.defaultStyle.key;
    }
    _update(state.copyWith(quoteApi: api, quoteStyle: reset ?? current));
  }

  /// 设置风格（白名单 + 支持集校验:仅当当前 API 支持该风格才生效）。
  void setQuoteStyle(String style) {
    final QuoteApi api = QuoteApi.fromKey(state.quoteApi);
    if (!api.supportsStyles ||
        !api.styles.contains(QuoteStyle.fromKey(style))) {
      return;
    }
    _update(state.copyWith(quoteStyle: style));
  }

  /// 设置语言档（v1.27.0,白名单校验;仅 UAPI 请求时生效,其它 API 忽略）。
  void setQuoteLang(String lang) {
    if (!kQuoteLangOptions.contains(lang)) return;
    _update(state.copyWith(quoteLang: lang));
  }
}

/// Monet 取色风格映射（F-08 / §10.2）：字符串键 ↔ MiuixThemePaletteStyle。
const Map<String, MiuixThemePaletteStyle> kPaletteStyleMap = {
  'tonalSpot': MiuixThemePaletteStyle.tonalSpot,
  'vibrant': MiuixThemePaletteStyle.vibrant,
  'expressive': MiuixThemePaletteStyle.expressive,
  'neutral': MiuixThemePaletteStyle.neutral,
};

const List<String> kPaletteStyleOptions = <String>[
  'tonalSpot',
  'vibrant',
  'expressive',
  'neutral',
];

// ── v1.26.0（S-21）：每日一言 API/风格选项表（键 ↔ 中文标签）──────

/// 可用 API 键(与 [QuoteApi] 一致;持久化 settings.quoteApi)。
const List<String> kQuoteApiOptions = <String>[
  'hitokoto',
  'iciba',
  'poetry',
  'jinrishici',
  'uapi',
];

const Map<String, String> kQuoteApiLabels = <String, String>{
  'hitokoto': '一言 (Hitokoto)',
  'iciba': '金山词霸每日一句',
  'poetry': '诗泉(古诗词)',
  'jinrishici': '今日诗词',
  'uapi': 'UAPI 一言',
};

/// 风格键(与 [QuoteStyle] 一致;持久化 settings.quoteStyle)。
const List<String> kQuoteStyleOptions = <String>[
  'classic',
  'poetry',
  'inspire',
  'beauty',
  'mix',
];

const Map<String, String> kQuoteStyleLabels = <String, String>{
  'classic': '📖 经典语录',
  'poetry': '🏮 古风诗词',
  'inspire': '🎯 励志哲理',
  'beauty': '🌸 唯美古风',
  'mix': '🎲 随机混合',
};

/// 固定内容类型 API 的说明（风格行隐藏时 API 行的 summary 补充）。
const Map<String, String> kQuoteApiFixedStyleSummary = <String, String>{
  'iciba': '固定:中英双语(每日一句)',
  'poetry': '固定:古诗词随机',
  'jinrishici': '固定:智能推荐',
};

// ── v1.27.0/v1.28.0（S-21）：UAPI 语言档选项表 ────────────────

/// 语言档键(持久化 settings.quoteLang;官方语料无日文原文,「动漫台词」
/// 为动画/漫画中文台词档:category=动画,漫画 的中文语料)。
const List<String> kQuoteLangOptions = <String>['zh', 'en', 'anime', 'mix'];

const Map<String, String> kQuoteLangLabels = <String, String>{
  'zh': '中文',
  'en': 'English',
  'anime': '🎬 动漫台词',
  'mix': '混合',
};

/// 毛玻璃生效裁决（U-03 §11.7）：用户开关 × 平台能力。
/// 只监听 settings.blurEnabled 与平台快照，最小重建范围。
final effectiveBlurProvider = Provider<bool>((ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  final PlatformInfo platform = ref.watch(platformInfoProvider);
  return U03BlurPolicy.allowBlur(
    userEnabled: settings.blurEnabled,
    isWeb: platform.isWeb,
    androidSdkInt: platform.androidSdkInt,
  );
});

/// 毛玻璃降级说明（设置页 summary / 警告卡用）。
final blurReasonProvider = Provider<String>((ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  final PlatformInfo platform = ref.watch(platformInfoProvider);
  return U03BlurPolicy.reason(
    userEnabled: settings.blurEnabled,
    isWeb: platform.isWeb,
    androidSdkInt: platform.androidSdkInt,
  );
});
