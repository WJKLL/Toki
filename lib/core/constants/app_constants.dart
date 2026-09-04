// lib/core/constants/app_constants.dart
// 编号：F-01 应用外壳（全局常量）
// 说明：静态配置集中定义（§11.2：static const，build 中零对象创建）。
import 'dart:ui' show Color;

abstract final class AppConstants {
  // v1.30.0:应用更名 Toki(新图标见 android res mipmap / web icons)。
  static const String appName = 'Toki';
  static const String appNameEn = 'Toki';
  static const String tagline = 'Converter Toolbox · Miuix 风格换算工具箱';

  /// 应用版本（与 pubspec version 同步，S-04 平台信息服务读取）。
  /// v1.34.0:同步为当前发布版本(此前长期滞留 1.17.4,关于页/日志失真)。
  static const String appVersion = '1.35.2';
  static const String buildNumber = '126';

  /// UAPI 接口平台 base（v1.35.0：通用工具 apiPath 统一前缀）。
  static const String uapiBaseUrl = 'https://uapis.cn';

  /// 响应式断点（U-04）：< 700px 竖屏底部导航；≥ 700px 左侧导航栏（§1 技术栈）。
  static const double breakpointWidth = 700;

  /// 默认 Miuix 种子色（Monet 关闭 / 无自定义 keyColor 时使用）。
  static const Color defaultKeyColor = Color(0xFF3482FF);

  /// P-01-02-01 可选种子色（§10.2 手动 keyColor）。
  static const List<Color> presetKeyColors = <Color>[
    Color(0xFF3482FF), // Miuix 蓝（默认）
    Color(0xFFFF5B29), // 活力橙
    Color(0xFF36D167), // 生态绿
    Color(0xFFFFB21D), // 明黄
    Color(0xFF8E5BFF), // 星紫
    Color(0xFFEB4B96), // 樱粉
    Color(0xFF00A6B5), // 湖青
    Color(0xFF5C6B7A), // 石板灰
  ];

  static const String license = 'Apache License 2.0';
  static const String projectUrl = 'https://github.com/example/xiangjugong';
  static const String changelogUrl =
      'https://github.com/example/xiangjugong/releases';

  /// 长列表滚动缓存区（§11.3：cacheExtent 默认 250px，禁止过大）。
  static const double listCacheExtent = 250;
}
