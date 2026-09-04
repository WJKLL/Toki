// lib/presentation/widgets/cards/card_steam_tool.dart
// 编号：C-37 工具启动卡（v1.34.0 新增,P-08 配套）
// 说明：首页网格动态工具卡(1×1,样式对齐 C-33 倒计时小卡 —— MiuixCard
//   主题表面 + squircle 圆角,阴影由 C-34 槽位 CardShadow 提供):
//   - 内容:徽标(C-38 自绘)+ 工具名 + 一句说明;点击 → 工具路由(R-11);
//   - 移除交互(v1.34.2):由 C-34 编辑态统一承担 —— 长按静止松手进入
//     编辑态,网格层在右上角叠加 ✕(本组件保持纯展示,不感知编辑态);
//   - 未知 toolId(目录下架)由 provider 层滤除,本组件不出现。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/steam_logo_icon.dart';
import '../../../domain/entities/home_card.dart';
import '../../../domain/entities/tool_item.dart';

/// C-37 工具启动卡(当前目录唯一项 Steam 用户;未来按 toolId 分发)。
class C37SteamToolCard extends StatelessWidget {
  const C37SteamToolCard({super.key, required this.data});

  final ToolLaunchCardData data;

  @override
  Widget build(BuildContext context) {
    final ToolItem? item = ToolItem.byId(data.toolId);
    if (item == null) return const SizedBox.shrink(); // 防御(下架滤除)。
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    return MiuixCard(
      onPressed: () => context.push(item.route),
      insideMargin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          SteamLogoIcon(size: 26, tint: colors.onSurfaceContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MiuixText(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.body2.copyWith(
                    color: colors.onSurfaceContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                MiuixText(
                  item.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
