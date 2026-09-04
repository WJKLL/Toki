// lib/core/widgets/c03_group_card.dart
// 编号：C-03 Miuix 卡片列表项（分组卡片，复刻蓝本 SettingsItem / 卡片组）
// 功耗要点：const 构造、零对象创建；MiuixCard 默认自带圆角与主题色。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 设置页分组卡片：MiuixCard 包裹 [Column]，组内项之间用 MiuixHorizontalDivider 分隔。
///
/// ⚡ 功耗优化：整卡是静态内容，只在状态变化时重绘一次；
///   内部子项一律 const 构造，build 零对象创建（§11.2）。
class C03GroupCard extends StatelessWidget {
  const C03GroupCard({
    super.key,
    required this.children,
    this.horizontalPadding = 12,
  });

  final List<Widget> children;

  /// 卡片外水平留白。
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: MiuixCard(
        // MiuixCard 默认 insideMargin=zero，内边距由组内项自行控制。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// 组内项之间的缩进分隔线（对齐列表项标题，避开起始图标槽位）。
class C03IndentDivider extends StatelessWidget {
  const C03IndentDivider({super.key, this.indent = 56});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const MiuixHorizontalDivider(),
    );
  }
}
