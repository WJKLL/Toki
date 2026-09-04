// lib/core/widgets/c15_page_scale_container.dart
// 编号：C-15 页面缩放容器（设置项 pageScale，§5 C-15 / F-03）
// 规则：Transform 一次性应用（缩放为纯几何变换），禁带动画；scale=1.0 时零开销直通。
// ⚡ 功耗优化：缩放后内容仍由原 RenderObject 缓存绘制，不引入额外合成层；
//   1.0 时短路返回 child，避免 Transform 节点占位。
import 'package:flutter/widgets.dart';

class C15PageScaleContainer extends StatelessWidget {
  const C15PageScaleContainer({
    super.key,
    required this.scale,
    required this.child,
  });

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child; // ⚡ 功耗优化：默认缩放直通，零节点开销
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}
