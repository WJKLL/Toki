# Toki · 架构与编号速查（开发者文档）

> 面向贡献者：本文件说明项目**分层架构**、**编号体系**与「想改 X 去改 Y」的导航。
> 技术栈：Flutter + flutter_miuix（禁 Material 视觉）+ Riverpod + go_router + shared_preferences / flutter_secure_storage。

---

## 0. 分层架构

项目采用 **Clean Architecture 简化分层**，依赖方向单向向内：

```
presentation（UI/状态，flutter_miuix + Riverpod）
      ↓ 经 Repository 抽象
domain（纯业务实体 + 仓库接口，不依赖 UI 框架）
      ↓ 实现
data（SharedPreferences / 加密存储 / JSON / http）
      ↑
core（常量、通用组件、日志、性能、工具服务）
```

- **presentation**：`shell/`（主框架底栏/侧边栏 + PageView 一级页）→ `router/`（go_router）→ `providers/`（Riverpod）→ `features/`（页面）→ `widgets/`（组件）。
- **domain / data**：实体定义与持久化 key 一一对应；仓库接口在 `domain/repositories/`，实现在 `data/repositories/`。
- **core**：被各层共用的基础设施；所有组件/服务文件头都有「编号：XX」注释，是唯一可信的交叉索引。

---

## 1. 编号体系

| 前缀 | 含义 | 分配/使用规则 |
| :--- | :--- | :--- |
| **P-** | 页面（含子页，如 P-01-01） | 新增页面时分配 |
| **C-** | 组件（widgets/ 与 cards/） | 新增可复用组件时分配 |
| **S-** | 服务/状态机/存储（settings、quote、course…） | 有独立状态或基础设施时分配 |
| **R-** | 路由 | 每注册一条 GoRoute 分配 |
| **U-** | 工具（core/utils 纯函数） | 通用算法/策略 |
| **A-** | 功能点（如 A-04 倒计时、A-05 拖拽） | 无 UI 文件的功能 |

规则：**编号一经分配不重用于其他功能**；组件内更细的「块级编号」（如 `#a01` 小课表）仅存在于卡片内部注释，贡献代码无需关注。

---

## 2. 关键子系统

### 2.1 首页网格（C-34 等）

- 卡片数据模型：`lib/domain/entities/home_card.dart`（sealed `HomeCardData` + `CardSize` small/wide/large + 唯一 `id`）。
- 网格容器：`lib/presentation/widgets/c34_responsive_card_grid.dart` —— 行高 `kGridRowHeight=104`、间距 `kGridCardGap=12`、列数 `gridColumnsForWidth`（<600→2 / 600–1099→3 / ≥1100→4）。支持**长按拖拽排序**（300ms 激活、跟手让位、落位持久化）与**长按静止松手进入编辑态**（卡片微缩、右上 ✕ 移除、点空白/返回键退出）。
- 卡片内容：`cards/card_combo.dart`（组合大卡）、`card_dashboard.dart`、`card_class_countdown.dart`、`card_steam_tool.dart`（工具启动卡）；分发在 C-34 的 `_cardWidget` switch（sealed 穷尽，漏分支编译报错）。
- 顺序/工具目录状态：`providers/home_cards_provider.dart`（`gridCardsProvider` 竖/横两套顺序；`homeToolItemsProvider` 持久化 `settings.homeToolItems`）。

### 2.2 悬浮底栏（C-22）

- 窄屏底部悬浮底栏复刻 KernelSU `FloatingBottomBar`：内核在 `widgets/kernel/`（按压阻尼 `damped_drag.dart`、内阴影 `inner_shadow.dart`、折射 `lens.dart`、模糊 `blur.dart`、双峰高光）。
- **所有视觉/物理参数集中在 `widgets/c22_visual_params.dart`（唯一事实源，禁止魔法数）**；业务文件只做状态分发。
- 宽屏（≥700px）自动切换 `MiuixNavigationRail` 侧边栏；一级页为 PageView 横滑。

### 2.3 路由与转场（S-03 / R-xx）

- `router/app_router.dart`：路由表 + `_knownPaths`（未知路径 redirect 回 `/?page=0`）。
- 二级页统一经 `_pageFor`：动效开 → `CustomTransitionPage` + MIUI 阻尼转场（`miuix_route_transitions.dart`，500ms 右滑入 + 左缘圆角）；动效关 → `NoTransitionPage` 直切。
- 一级页（首页/工具）为 PageView 页索引路由（`/home`→`/?page=0`、`/tools`→`/?page=1`）。

### 2.4 主题与设置（S-01 / S-02）

- 无独立 theme 目录：主题由 `main.dart` 的 `MiuixThemeController` 状态机 + flutter_miuix 生成；设置页 P-01-02-01 是操作入口（深色 / Monet / 种子色 / 调色板）。
- 设置持久化唯一写入口：`settings_providers.dart` 的 `AppSettingsController`；落盘 key 见下方存储表。
- **毛玻璃策略（U-03）**：Android 13+ 真模糊；Android 12 及以下 / Web 一律半透明降级（预期行为）。动效开关关闭时全局无动画。

### 2.5 工具页与 Steam 查询（P-08）

- 工具目录：`domain/entities/tool_item.dart`（`kToolCatalog`，工具页入口网格与首页动态卡共用）。
- 工具入口 C-36：点按进工具路由；长按 500ms + 触觉 → 「添加到首页」（`MiuixOverlayDialog` 自适应弹层）。
- Steam 查询页 P-08：四态机（idle/loading/success/error）；输入自动识别 4 种格式；`core/tools/steam_api_service.dart` 封装 UAPI `GET uapis.cn/api/v1/game/steam/summary`（无 key 可用；错误按 400/401/404/502 分类）。
- 凭证：`steam_auth_service.dart` —— Android/桌面 `flutter_secure_storage`（Keystore 加密），Web 降级 shared_preferences；密钥不进日志、不回显。

### 2.6 内容源与性能

- 每日一言 S-21（多免费 API / UAPI）+ 问候语 S-22：`providers/quote_provider.dart` 统一管理刷新窗口（45 分钟自动换新、跨天保守检查）。
- 性能：`core/refresh_rate/`（空闲 3s 释放高刷）、`core/logging/perf_monitor.dart`（环形帧耗时）、模糊降级 `blur_degrade_provider.dart`、二级页 deferred 懒加载。

---

## 3. 当前编号速查

### 3.1 组件（C-）

| 编号 | 组件 | 文件 | 用途 |
| :--- | :--- | :--- | :--- |
| C-03 | 分组卡片 | `lib/core/widgets/c03_group_card.dart` | 设置页分组（MiuixCard + 分隔线） |
| C-05 | 警告卡片 | `lib/core/widgets/c05_warning_card.dart` | 黄/红警告横条 |
| C-15 | 页面缩放容器 | `lib/core/widgets/c15_page_scale_container.dart` | 设置项 pageScale 几何缩放 |
| C-21 | 折叠标题栏 | `presentation/widgets/c21_collapsing_title_bar.dart` | 大标题→小标题折叠（含胶囊按钮） |
| C-22 | 悬浮底栏 | `widgets/c22_*` + `kernel/*` | 底部导航（液态玻璃内核 / 蒙版双模式） |
| C-23 | 内容推动折叠标题栏 | `widgets/c23_push_collapsing_header.dart` | 首页/设置/关于统一顶栏 |
| C-24 | 毛玻璃 FAB | `widgets/c24_frosted_fab.dart` | 右下悬浮快捷按钮 |
| C-25 | 顶部标题栏 | `widgets/c25_frosted_top_bar.dart` | 蒙版背景（开=渐变 / 关=不透明） |
| C-26 | 顶部更多菜单 | `widgets/c26_more_menu.dart` | 三点悬浮菜单（MiuixOverlayIconDropdownMenu） |
| C-27 | 首页摘要卡 | `cards/card_summary.dart` | 问候语 + 每日一言（动态） |
| C-28 | 组合大卡 | `cards/card_combo.dart` | 小课表 + 今日剩余环 |
| C-29 | 仪表盘卡 | `cards/card_dashboard.dart` | 统计 + 分段进度 |
| C-30 | ~~占位卡~~ | ~~cards/card_placeholder.dart~~ | **已停用**：占位卡体系移除，文件已删除（编号保留不重用） |
| C-31 | 协议卡 | `widgets/c31_agreement_card.dart` | 开屏用户协议 |
| C-32 | 环形进度 | `widgets/c32_ring_progress.dart` | RingProgressPainter + C32AnimatedRing |
| C-33 | 课程倒计时卡 | `cards/card_class_countdown.dart` | 当前课程环 + 剩余百分比 |
| C-34 | 响应式卡片网格 | `widgets/c34_responsive_card_grid.dart` | 首页网格：列数 2/3/4、拖拽排序、编辑态 |
| C-35 | 悬浮单选选择窗 | `widgets/c35_quote_option_sheet.dart` | 内容设置选择浮窗（MiuixOverlayDialog 自适应） |
| C-36 | 工具入口按钮 | `widgets/c36_tool_entry_button.dart` | 工具目录入口：点按进路由 / 长按添加至首页 |
| C-37 | 工具启动卡 | `cards/card_steam_tool.dart` | 首页网格动态工具卡（✕ 移除由 C-34 编辑态提供） |
| C-38 | Steam 徽标自绘 | `core/widgets/steam_logo_icon.dart` | 官方剪影 CustomPainter（tint 单色） |
| C-39 | 密钥弹层 | `widgets/c39_steam_key_sheet.dart` | 凭证 obscure 输入 + 切换 + 清除 |
| C-27/28 | 预模糊 / 降采样快照 | `widgets/c27_prefrosted_blur.dart` / `c28_downsampled_capture.dart` | 毛玻璃性能方案 |

> C-01/C-02/C-12 为早期设计编号残留，无独立文件；窄屏底栏由 C-22 承担、宽屏为 `MiuixNavigationRail`。

### 3.2 页面（P-）与路由（R-）

| 页面 | 编号 | 路由 | 文件 |
| :--- | :--- | :--- | :--- |
| 主框架 | P-01 | `/`（R-01） | `shell/main_shell_page.dart` |
| 首页 | P-01-01 | `/home`→`/?page=0`（R-02） | `features/home/page_p01_01_home_page.dart` |
| 工具集 | P-01-04 | `/tools`→`/?page=1`（R-03） | `features/tools/page_p01_04_tools_page.dart` |
| 设置 | P-01-02 | `/settings`（R-04） | `features/settings/page_p01_02_settings_page.dart` |
| 关于 | P-01-03 | `/about`（R-05） | `features/about/page_p01_03_about_page.dart` |
| 调色板 | P-02 | `/color-palette`（R-06） | `features/palette/page_p02_color_palette_page.dart` |
| 权限 | P-03 | `/permissions`（R-07） | `features/permissions/page_p03_permissions_page.dart` |
| 主题配置 | P-01-02-01 | `/settings/theme`（R-08） | `features/settings/page_p01_02_01_theme_config_page.dart` |
| 大课表 | P-06 | `/timetable`（R-10） | `features/timetable/page_p06_timetable_page.dart` |
| Steam 用户查询 | P-08 | `/steam`（R-11） | `features/tools/page_p08_steam_query_page.dart` |
| 每日活动编辑器 | P-05 | 非路由弹层（deferred） | `features/home/p05_activity_editor.dart` |
| 开屏用户协议 | P-07 | 启动浮层（非路由） | `widgets/agreement_gate.dart` + `c31_agreement_card.dart` |

> R-09 预留未占用；未知路径统一 redirect 到 `/?page=0`。

### 3.3 存储 key（SharedPreferences）

`settings.uiMode / monetEnabled / keyColor / paletteStyle / blurEnabled / floatingBarEnabled / pageScale / logCaptureEnabled`（S-02，300ms 防抖合并）｜`settings.classPeriods`（节次时间表）｜`settings.cardOrder`（首页网格卡顺序，竖/横两套）｜`settings.dailyQuoteCache`、`settings.quoteEnabled/quoteApi/quoteStyle/quoteLang`（S-21）｜`settings.homeToolItems`（首页工具目录）｜`course.list`、`course.meta`（S-15）｜`daily.activity`（S-05）｜`user_agreement_accepted/version`（S-20）。

**敏感凭证（Steam 密钥）不走 SharedPreferences**：Android/桌面用 flutter_secure_storage，Web 降级普通存储（见 `steam_auth_service.dart`）。

---

## 4. 常见修改指南

| 想改什么 | 去哪个文件 |
| :--- | :--- |
| 网格行高/间距/列数 | `c34_responsive_card_grid.dart` 顶部常量（`kGridRowHeight`/`kGridCardGap`/`gridColumnsForWidth`） |
| 卡片阴影/圆角 | `cards/card_shell.dart`（CardShadow）/ 各卡 `borderRadius` |
| 首页卡片顺序或加新卡 | `home_cards_provider.dart`（顺序）→ `home_card.dart`（加 sealed 数据类）→ `cards/` 新建 + C-34 `_cardWidget` 补分支 |
| 今日剩余算法 | `providers/daily_activity_provider.dart`（`todayRemainingProvider`） |
| 课表增删改/导入 | `providers/course_provider.dart`（Excel 解析在 `core/excel/`） |
| 设置项字段 | `domain/entities/app_settings.dart` + `settings_repository_impl.dart` + `settings_providers.dart` 三处联动 |
| 底栏视觉/物理参数 | **只改** `widgets/c22_visual_params.dart` |
| 顶部更多菜单项 | `providers/nav_items_providers.dart`（`moreMenuItemsProvider`） |
| 加一级页（底栏页） | `nav_items_providers.dart`（项）→ `features/` 建页 → `main_shell_page.dart`（PageView）→ `app_router.dart`（redirect） |
| 加二级页 | `features/` 建页 → `app_router.dart`（`_knownPaths` + `GoRoute`，分配 R-xx）→ 加入口 |
| 工具目录/工具页 | `domain/entities/tool_item.dart`（目录）→ `features/tools/page_p01_04_tools_page.dart`（分组展示） |
| 主题/深色/Monet | `main.dart`（MiuixThemeController）+ 设置页 P-01-02-01；勿硬编码颜色 |
| 每日一言/问候语 | `providers/quote_provider.dart`（S-21/S-22），改静态文案没用 |
| 图标 | 统一经 `core/widgets/app_icons.dart` 的 `appIcon()`；Steam 徽标用 C-38 组件 |

---

## 5. 约定与 FAQ

- **UI 必须用 flutter_miuix 组件**（MiuixCard/MiuixButton/MiuixText…）；Material 仅保留 `MaterialApp` 壳与个别底层类型。
- **状态管理**：Riverpod Notifier/AsyncNotifier；订阅用 `ref.watch(provider.select(...))` 最小化；只经 public setter 改状态。
- **版本规则**：功能→minor，修复/优化→patch，只升不降；同步 `pubspec.yaml` + `app_constants.dart` + `CHANGELOG.md`。
- **改完不生效**：热重载 `r` / 热重启 `R`；改 `main.dart`/`pubspec.yaml` 需重启 run。
- **毛玻璃没生效**：Android 12 及以下 / Web 半透明降级属预期（U-03）。
- **想调性能/看帧率**：`core/logging/perf_monitor.dart`（S-14）环形记录 600 帧；滚动模糊掉帧看 `blur_degrade_provider.dart`（S-19）。
- **数据想重置**：每日活动可在设置/编辑器内恢复默认；或删除对应存储 key（见 §3.3）。
