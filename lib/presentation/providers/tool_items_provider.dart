// === 文件: lib/presentation/providers/tool_items_provider.dart ===
// 编号：P-09 通用工具 · 服务注入与目录暴露（v1.35.0 新增）
// 说明：
//   - toolCatalogProvider：目录分组（C-42/P-01-04 渲染；同步读 Store 缓存）；
//   - toolApiServiceProvider：通用调用管道注入点（测试可 override fixture，
//     与 steamApiServiceProvider 同模式）；
//   - 同步对账查询（首页卡过滤/添加入口）统一走
//     ToolCatalogStore.instance.byIdSync，不经本文件。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tools/tool_api_service.dart';
import '../../domain/entities/tool_config.dart';
import '../../core/tools/tool_catalog_store.dart';

/// 工具目录分类分组（启动已预加载；同步读 Store 缓存，永不 loading）。
final toolCatalogProvider = Provider<List<ToolCategoryNode>>((ref) {
  return ToolCatalogStore.instance.groups;
});

/// 通用调用管道注入点（单元测试 override）。
final toolApiServiceProvider = Provider<ToolApiService>((ref) {
  return ToolApiService();
});
