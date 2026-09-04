// lib/core/widgets/app_icons.dart
// 编号：F-01 应用外壳（图标统一出口，core 层基础设施）
// 说明：MiuixIcons.extended 为惰性缓存查找（同图标只构建一次，§11.2），
//       统一经此出口取图标，杜绝 build 中重复构建与硬编码查找；
//       未知名回退 basic.arrowRight，绝不抛出异常。
// v1.34.0(P-08)：Steam 徽标为**自绘组件**(C-38,core/widgets/steam_logo_icon.dart
//   SteamLogoIcon)—— 不进 MiuixIcons 槽位,调用方按 logoKind 直接使用。
import 'package:flutter_miuix/miuix.dart';

/// 取扩展图标（默认 Regular 字重）。未知名称回退基础箭头图标。
MiuixVectorIcon appIcon(String name) =>
    MiuixIcons.extended.byName(name) ?? MiuixIcons.basic.arrowRight;
