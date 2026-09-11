// lib/presentation/widgets/kernel/spatial_component_layer.dart
// 编号：C-67 空间组件层（P-24 空间壁纸 · 期 1）
//
// 职责：把 `List<SpatialComponent>` 渲染成叠在分层视差画面【之上】的可交互图层。
//   · 位置：归一化 u/v → 像素（u/v 指向组件中心，跟随画面尺寸与比例）
//   · 3D ：Matrix4 透视 + 平面倾角（含随晃动方向的"倾斜跟随"）
//   · 视差：自身位移 = shift × amount × parallax（默认 0 = 完全固定）
//   · 交互：点击选中 / 拖动改 u,v（空白区域的拖动仍归舞台的焦点手势）
//
// ★ 为什么组件不进 shader（PLAN_components_v1.53.md §3 决策 3）
//   时钟每分钟变、文字要矢量清晰、玻璃要模糊"正在移动的背景" ——
//   三者都更适合 Flutter 层；进 shader 需每分钟上传纹理且文字会糊。
//   代价：遮挡要自己用图层 alpha 做遮罩（期 6），而非白拿深度测试。
//
// ★ 期 1 的"外壳"是简易半透明玻璃（纯 Flutter 绘制）。
//   期 2 换成 LensRefraction（折射 + 色散 + 厚度感）时，只需替换 [_shell]，
//   本文件的定位 / 3D / 视差 / 手势逻辑全部零改动。
import 'package:flutter/widgets.dart';

import '../../../domain/entities/spatial_component.dart';
import 'component_clock.dart';

/// 组件被拖动时回调（归一化增量，0..1 相对画面）。
typedef ComponentMoveCallback =
    void Function(String id, Offset deltaUv);

/// C-67 空间组件层。
class SpatialComponentLayer extends StatelessWidget {
  const SpatialComponentLayer({
    super.key,
    required this.components,
    required this.size,
    required this.shift,
    required this.amount,
    this.tiltFollow = 0.4,
    this.selectedId,
    this.onSelect,
    this.onMove,
  });

  /// 组件列表（按顺序绘制，靠后的在上层 —— 期 8 会加显式层级排序）。
  final List<SpatialComponent> components;

  /// 舞台尺寸（用于归一化坐标换算）。
  final Size size;

  /// 晃动单位方向（各分量 -1..1），与分层视差**同一个源**。
  final Offset shift;

  /// 视差强度（逻辑像素），与分层视差**同一个值**。
  final double amount;

  /// 全局倾斜跟随强度 0..1：晃动时组件平面轻微反向倾斜，
  /// 产生"贴在空间里"的侧向透视感（而位置不动）。
  final double tiltFollow;

  /// 当前选中的组件 id。
  final String? selectedId;

  final ValueChanged<String>? onSelect;
  final ComponentMoveCallback? onMove;

  @override
  Widget build(BuildContext context) {
    if (size.isEmpty || components.isEmpty) return const SizedBox.expand();
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        for (final SpatialComponent c in components)
          if (c.visible) _buildOne(c),
      ],
    );
  }

  Widget _buildOne(SpatialComponent c) {
    // ── 位移：由 parallax 独立控制（默认 0 = 完全固定，不随晃动平移）──
    final Offset offset = shift * (amount * c.parallax);

    // ── 倾斜：跟随晃动方向反向微倾 → "贴在空间里" 的侧视感 ──
    final double tf = tiltFollow * c.tiltFollow;
    final double ry = c.tiltY + shift.dx * tf * 0.18; // 绕垂直轴
    final double rx = c.tiltX - shift.dy * tf * 0.13; // 绕水平轴

    final bool selected = selectedId != null && selectedId == c.id;

    // ★ 定位用【Positioned.fill + Transform.translate + Align】，而不是
    //   Positioned(left, top)：后者把 Stack 的剩余空间当作约束，组件靠右/靠下
    //   时可用宽高随之变小 → 时钟会被压扁或溢出。fill + Align 让组件始终拿到
    //   完整舞台的 loose 约束，保持自然尺寸，同时 u/v 精确指向组件中心。
    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(
          (c.u - 0.5) * size.width + offset.dx,
          (c.v - 0.5) * size.height + offset.dy,
        ),
        child: Align(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, c.perspective) // 透视强度 → 侧视感
              ..rotateX(rx)
              ..rotateY(ry)
              ..rotateZ(c.rotation)
              // scale 已废弃（v3.27+）：scaleByDouble(sx, sy, sz, sw)。
              ..scaleByDouble(c.scale, c.scale, c.scale, 1.0),
            child: Opacity(
              opacity: c.opacity.clamp(0.0, 1.0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect?.call(c.id),
                onPanStart: (_) => onSelect?.call(c.id),
                onPanUpdate: (DragUpdateDetails d) {
                  if (size.isEmpty) return;
                  // 拖动按【舞台尺寸】归一化 → 换屏幕/换图仍落在同一相对位置。
                  onMove?.call(
                    c.id,
                    Offset(d.delta.dx / size.width, d.delta.dy / size.height),
                  );
                },
                child: _shell(c, selected, _body(c)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 内容分发。期 7 起改成注册表查询（PLAN_components_v1.53.md §8.2）。
  Widget _body(SpatialComponent c) {
    switch (c.kind) {
      case SpatialComponentKind.clock:
        return ComponentClock(
          h24: c.boolProp('h24', or: true),
          showDate: c.boolProp('showDate', or: true),
          showSeconds: c.boolProp('showSeconds'),
        );
    }
  }

  /// 组件外壳：期 1 = 简易半透明玻璃；期 2 替换为折射玻璃（仅此函数需改）。
  Widget _shell(SpatialComponent c, bool selected, Widget child) {
    // 玻璃浓度随"玻璃感"旋钮走（期 2 该值将改为驱动模糊/折射/色散）。
    final double g = c.glass.clamp(0.0, 1.0);
    final double tintA = 0.04 + 0.26 * g;
    final double rimA = 0.10 + 0.55 * g;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF).withValues(alpha: tintA),
        borderRadius: BorderRadius.circular(c.corner),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: rimA),
          width: selected ? 1.6 : 1.0,
        ),
        boxShadow: <BoxShadow>[
          // 投影强度随 Z 增大（越靠前越"浮起来"）—— 这是最简单的一层景深线索。
          BoxShadow(
            color: const Color(0xFF000000).withValues(
              alpha: 0.14 + 0.22 * c.depth.clamp(0.0, 1.0),
            ),
            blurRadius: 16 + 14 * c.depth.clamp(0.0, 1.0),
            offset: Offset(0, 5 + 6 * c.depth.clamp(0.0, 1.0)),
          ),
        ],
      ),
      child: child,
    );
  }
}
