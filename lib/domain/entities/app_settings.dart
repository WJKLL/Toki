// lib/domain/entities/app_settings.dart
// 编号：F-03 / F-08 · S-01 主题状态机 · S-02 设置存储
// 说明：纯领域实体，不依赖任何 UI 框架。PaletteStyle 以字符串键保存（'tonalSpot'…），
//       由 presentation 层映射为 flutter_miuix 的 MiuixThemePaletteStyle（F-08）。
import 'package:flutter/foundation.dart' show immutable, listEquals;

import 'dart:ui' show Color;

import 'class_period.dart';

/// UI 模式（F-03「UI 模式」设置项）。对应 S-01 状态机的明暗维度。
enum AppUiMode {
  /// 跟随系统
  system,

  /// 强制浅色
  light,

  /// 强制深色
  dark,
}

/// 应用设置聚合实体（S-01 主题状态机 + F-03 全部设置项）。
///
/// 不可变对象，变更通过 [copyWith] 产生新实例；持久化由 S-02 负责。
@immutable
class AppSettings {
  const AppSettings({
    this.uiMode = AppUiMode.system,
    this.monetEnabled = false,
    this.keyColor,
    this.paletteStyle = 'tonalSpot',
    this.blurEnabled = true,
    this.floatingBarEnabled = false,
    this.pageScale = 1.0,
    this.logCaptureEnabled = false,
    this.classPeriods = ClassPeriod.defaults,
    this.quoteEnabled = true,
    this.quoteApi = 'hitokoto',
    this.quoteStyle = 'classic',
    this.quoteLang = 'zh',
    this.courseReminderEnabled = true,
  });

  /// UI 模式（跟随系统 / 浅色 / 深色）。
  final AppUiMode uiMode;

  /// Monet 动态取色总开关（默认关闭，PROJECT_SPEC §10.2）。
  final bool monetEnabled;

  /// 手动取色种子色（keyColor）；为 null 时使用默认 Miuix 蓝。
  final Color? keyColor;

  /// 取色风格键（MiuixThemePaletteStyle 枚举名），默认 TonalSpot（§10.2）。
  final String paletteStyle;

  /// 毛玻璃效果总开关（默认开；实际生效与否由 U-03 策略裁决，§11.7）。
  final bool blurEnabled;

  /// 悬浮底栏（C-12）开关，默认关（§11.7 悬浮底栏为模糊允许区域）。
  final bool floatingBarEnabled;

  /// 页面缩放（C-15），0.8 ~ 1.2，一次性 Transform 应用，禁带动画（§5 C-15）。
  final double pageScale;

  /// 日志采集总开关（S-13/S-14，v1.9.0）。默认关闭 —— 关闭时日志服务与
  /// 帧采样零成本（§11.1/§11.8 功耗约束）。
  final bool logCaptureEnabled;

  /// 全局节次时间表（v1.21.0，S-02 key settings.classPeriods）：
  /// 固定 16 项（与 P-06 课表网格对齐），默认启用前 12 节；
  /// 同时作为「动效开关」的低性能档依据（关闭时首页圆环动画跳变）。
  final List<ClassPeriod> classPeriods;

  // ── v1.26.0（S-21/S-22）：首页动态内容设置（内容设置分组）────────

  /// 每日一言总开关（默认开；关闭 = 不联网、摘要区显示本地文案）。
  final bool quoteEnabled;

  /// 每日一言 API 来源键（S-21，白名单见 kQuoteApiOptions）。
  final String quoteApi;

  /// 每日一言风格键（S-21，仅多风格 API 生效；白名单见 kQuoteStyleOptions）。
  final String quoteStyle;

  /// 每日一言语言档键（v1.27.0，S-21，仅 UAPI 生效；'zh'/'en'/'mix'）。
  final String quoteLang;

  /// v1.36.0：课程提醒总开关（到点闹钟 + 上课常驻通知；默认开）。
  final bool courseReminderEnabled;

  static const double kPageScaleMin = 0.8;
  static const double kPageScaleMax = 1.2;

  AppSettings copyWith({
    AppUiMode? uiMode,
    bool? monetEnabled,
    Color? keyColor,
    bool clearKeyColor = false,
    String? paletteStyle,
    bool? blurEnabled,
    bool? floatingBarEnabled,
    double? pageScale,
    bool? logCaptureEnabled,
    List<ClassPeriod>? classPeriods,
    bool? quoteEnabled,
    String? quoteApi,
    String? quoteStyle,
    String? quoteLang,
    bool? courseReminderEnabled,
  }) {
    return AppSettings(
      uiMode: uiMode ?? this.uiMode,
      monetEnabled: monetEnabled ?? this.monetEnabled,
      keyColor: clearKeyColor ? null : (keyColor ?? this.keyColor),
      paletteStyle: paletteStyle ?? this.paletteStyle,
      blurEnabled: blurEnabled ?? this.blurEnabled,
      floatingBarEnabled: floatingBarEnabled ?? this.floatingBarEnabled,
      pageScale: pageScale ?? this.pageScale,
      logCaptureEnabled: logCaptureEnabled ?? this.logCaptureEnabled,
      classPeriods: classPeriods ?? this.classPeriods,
      quoteEnabled: quoteEnabled ?? this.quoteEnabled,
      quoteApi: quoteApi ?? this.quoteApi,
      quoteStyle: quoteStyle ?? this.quoteStyle,
      quoteLang: quoteLang ?? this.quoteLang,
      courseReminderEnabled: courseReminderEnabled ?? this.courseReminderEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppSettings &&
            other.uiMode == uiMode &&
            other.monetEnabled == monetEnabled &&
            other.keyColor == keyColor &&
            other.paletteStyle == paletteStyle &&
            other.blurEnabled == blurEnabled &&
            other.floatingBarEnabled == floatingBarEnabled &&
            other.pageScale == pageScale &&
            other.logCaptureEnabled == logCaptureEnabled &&
            other.quoteEnabled == quoteEnabled &&
            other.quoteApi == quoteApi &&
            other.quoteStyle == quoteStyle &&
            other.quoteLang == quoteLang &&
            other.courseReminderEnabled == courseReminderEnabled &&
            listEquals(other.classPeriods, classPeriods);
  }

  @override
  int get hashCode => Object.hash(
    uiMode,
    monetEnabled,
    keyColor,
    paletteStyle,
    blurEnabled,
    floatingBarEnabled,
    pageScale,
    logCaptureEnabled,
    quoteEnabled,
    quoteApi,
    quoteStyle,
    quoteLang,
    courseReminderEnabled,
    Object.hashAll(classPeriods),
  );
}
