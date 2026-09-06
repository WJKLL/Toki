// === 文件: lib/presentation/widgets/cards/card_steam_tool.dart ===
// 编号：C-37 工具启动卡（v1.34.0 新增;v1.35.0 泛化 ToolConfig 分发）
// 说明：首页网格动态工具卡(1×1,样式对齐 C-33 倒计时小卡 —— MiuixCard
//   主题表面 + squircle 圆角;阴影与暗色高光由 C-34 槽位统一提供
//   (CardShadow + CardDarkGlow, v1.44.x 起),本组件保持纯展示):
//   - 内容:徽标(ToolBrandIcon:C-38 泛化)+ 工具名 + 一句说明;
//     点击 → 工具派生 route(customRoute 或 /tool/:id);
//   - 移除交互(v1.34.2):由 C-34 编辑态统一承担 —— 本组件保持纯展示;
//   - 未知 toolId(目录下架)由 provider 层滤除,本组件防御性不渲染。
//   类名 C37SteamToolCard 保留(历史命名,现服务全部目录工具;测试按类名引用)。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:go_router/go_router.dart';

import '../../../core/tools/tool_catalog_store.dart';
import '../../../core/widgets/tool_brand_icon.dart';
import '../../../domain/entities/home_card.dart';
import '../../../domain/entities/tool_config.dart';

/// C-37 工具启动卡(v1.35.0 起按 toolId 从目录缓存取 ToolConfig 分发)。
class C37SteamToolCard extends StatelessWidget {
  const C37SteamToolCard({super.key, required this.data});

  final ToolLaunchCardData data;

  @override
  Widget build(BuildContext context) {
    final ToolConfig? item = ToolCatalogStore.instance.byIdSync(data.toolId);
    if (item == null) return const SizedBox.shrink(); // 防御(下架滤除)。
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    return MiuixCard(
      onPressed: () => context.push(item.route),
      insideMargin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          ToolBrandIcon(
            tool: item,
            size: 26,
            tint: colors.onSurfaceContainer,
          ),
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
