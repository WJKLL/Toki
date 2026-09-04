// lib/core/widgets/app_scroll_behavior.dart
// 编号：F-01 应用外壳基础设施（全局滚动物理配置）
// 职责：全局 ScrollBehavior —— 所有 ListView/GridView/PageView 统一
//   BouncingScrollPhysics（列表回弹 + 长惯性，HyperOS/iOS 手感）；
//   经 MaterialApp.scrollBehavior 一处生效。
// v1.18.x（T1+D1+S-全局）：dragStartBehavior 无全局 Hook（Scrollable 构造参数），
//   由各滚动体显式传 DragStartBehavior.down（见各页面）；physics 走本类全局覆写。
import 'package:flutter/material.dart';

/// 全局滚动物理：Bouncing（回弹）而非 Android 默认 Clamping（硬停）。
/// parent 用 RangeMaintainingScrollPhysics —— 页面内容动态变化（如刷新后
/// 变短）时保持滚动位置在合法范围内，避免越界跳动。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Android 默认 ClampingScrollPhysics（无回弹、阻尼硬）；
    // 本项目统一改用 Bouncing（对齐 HyperOS 系统列表手感，v1.18.x）。
    return const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());
  }
}
