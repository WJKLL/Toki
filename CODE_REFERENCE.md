# Toki 代码功能说明书

> 本文档基于项目**当前实际代码**生成，给不熟悉结构的人看：每个文件是干什么的、想改某个功能去哪个文件。
> 编号体系（P-页面 / C-组件 / S-服务 / U-工具 / R-路由）与各文件头注释及 PROJECT_SPEC 保持一致。
> 文档本身不影响版本号（版本规则：功能=minor、修复/优化=patch，只升不降）。
> 注：v1.34.0 曾因 PowerShell 编码事故损坏，本版依据 v1.33 底稿（程序化恢复）+ 代码现状重建。

---

## 🧭 开发工作流（Pro / Flash 双模式 · 会话规则）

> 来源：用户工作流指令（Toki 项目）。**每个新会话默认遵守**，与下文编号体系、版本规则同权。

### 角色与模式

- **Pro 模式（规划模式）**：触发条件 = 新增功能模块 / 架构调整 / 新增编号 / 多文件改动 / 复杂重构。
  行为：输出 `PLAN_*.md` 文档（含编号分配、数据模型、任务清单），**不做具体代码生成**。
- **Flash 模式（编码模式）**：触发条件 = 代码生成 / Bug 修复 / UI 微调 / 单文件改动。
  行为：只输出代码不输出解释，每个文件用 `// === 文件: [完整路径] ===` 分隔。

### ⚠️ 歧义处理规则（重要，节省开支）

遇到以下情况 **立即停止推理，用通俗语言向用户提问确认**（≤2 次提问，禁止自我循环推理超过 3 轮）：

1. 需求描述模糊——无法确定具体交互/视觉/行为；
2. 技术选型不明确——多种实现方式无法判断；
3. 编号或命名歧义——不清楚应分配什么编号/命名；
4. 依赖关系不确定——不确定哪个任务先执行。

提问格式：「我遇到了一个不明确的地方：[具体描述]。有以下几种可能：[选项A]、[选项B]。你希望我按哪个方向继续？」

**禁止**：猜测用户意图 / 自行假设上下文 / 歧义状态下继续生成代码或规划 / 循环推理超 3 轮未确认。目标：1-2 次提问确认方向，避免返工浪费。

### 项目约束（必须遵守）

- UI 框架：flutter_miuix（禁用 Material 视觉组件）
- 状态管理：Riverpod（Notifier/AsyncNotifier）
- 路由：go_router
- 渲染后端：Skia（EnableImpeller=false）
- 编号体系：见下文各章（P-/C-/S-/R-/U-/A-）
- 版本规则：功能 → Minor，修复/优化 → Patch（只升不降，每次推送必增）
- 存储：SharedPreferences（S-02）；敏感凭证：flutter_secure_storage（v1.34.0）

### 工作流程

1. 用户提供需求 → 判断模式；
2. 遇到歧义 → 立即提问确认（不要继续推理）；
3. 用户确认后继续执行；
4. 新功能 → Pro 模式 → 输出 `PLAN_*.md`；
5. 用户选择任务 → Flash 模式 → 输出代码；
6. 用户验证后反馈 → 继续下一任务或修复。

### 判断规则

- 含「新增 / 规划 / 设计 / 编号」→ **Pro 模式**
- 含「实现 / 修复 / 修改 / 生成代码」→ **Flash 模式**
- 不确定 → **直接提问**，不要猜测。

---

## 0. 项目全景（30 秒版）

```
xiangjugong/
├─ lib/main.dart                    应用入口：ProviderScope + 主题装配 + go_router + 全局滚动
├─ lib/core/                        基础设施：常量 / 工具 / 日志 / Excel / 通用小组件
├─ lib/domain/                      纯业务：实体（Entity）+ 仓库抽象（Repository）
├─ lib/data/repositories/           仓库实现：SharedPreferences + JSON
└─ lib/presentation/
   ├─ shell/main_shell_page.dart    主框架：<700px 底栏 / ≥700px 侧边栏 + PageView 一级页
   ├─ router/app_router.dart        路由表（go_router，R-01~R-12）
   ├─ providers/                    Riverpod 状态：主题/课表/每日活动/卡片/导航项等
   ├─ features/                     页面（P-01-xx 首页/设置/工具，P-02/03/05/06/08…）
   └─ widgets/                      组件：C-21~C-28 等 + cards/（C-27~C-30/C-33…）、kernel/（底栏内核）
```

技术栈：**Flutter + flutter_miuix 1.1.1**（界面统一 Miuix 组件，禁 Material 视觉）+ **Riverpod**（状态）+ **go_router**（路由）+ **shared_preferences**（存储）。数据流以每日活动为例：`UI 点击保存 → Provider(saveAll) → Repository(S-05) → SharedPreferences(key: daily.activity)`。

---

## 1. 核心文件索引

### 1.1 入口与配置

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/main.dart` | 应用入口（F-01）：ProviderScope、S-02 存储注入、`MiuixThemeController` 主题装配、`appRouterProvider`、全局滚动行为、滚动心跳监听、全局去下划线 DefaultTextStyle、根 surface 垫底（防转场黑帧） | 改应用初始化、全局 Provider 注册、**主题整体装配** |
| `pubspec.yaml` | 依赖管理、版本号 `version:` | 增删依赖、**发布前升版本号** |
| `android/app/src/main/AndroidManifest.xml` | 含 `EnableImpeller=false`（锁定 Skia 渲染） | 想切换 Impeller 时删除该 meta-data（注释有说明） |
| `lib/core/constants/app_constants.dart` | 全局常量：应用名 `Toki`、版本号（与 pubspec 同步）、响应式断点等 | 改应用名等静态文案 |

> ⚠️ 项目**没有**独立 theme 目录——主题由 `MiuixThemeController`（S-01 状态机，在 main.dart 中）+ flutter_miuix 生成，设置页 `P-01-02-01` 是操作入口。

### 1.2 路由与主框架

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/presentation/router/app_router.dart` | 导航服务（S-03）：全部路由表（R-01~R-08、R-10~R-12）、redirect 规则（未知路径回 `/`，`/tool/` 前缀放行）、路由日志；v1.29.0：路由页统一经 `_pageFor`（动效开关开 → `CustomTransitionPage` + 二级页转场；关 → `NoTransitionPage` 直切） | 加页面、改路由路径、调转场开关联动 |
| `lib/presentation/router/miuix_route_transitions.dart` | 二级页切换过渡（v1.29.0 定稿）：MIUI 阻尼曲线 `MiuixNavCurve`（移植 miuix-navigation3-ui 0.9.2，damping 0.75）、统一 `buildMiuixRouteTransitions`（500ms；新页从右整宽滑入 + 动画期左缘圆角 32；**一级页不动**——v1.31.0 移除让位与压暗） | 调动画时长/曲线/圆角等转场参数 |
| `lib/presentation/shell/main_shell_page.dart` | 主框架（P-01）：`<700px` 用底部导航（C-22 双模式）+ PageView 横滑一级页；`≥700px` 用左侧 `MiuixNavigationRail`；包 `C15PageScaleContainer`（页面缩放）与 `AgreementGate`（P-07） | 改一级页组织方式、断点行为、深链 page 参数 |

### 1.3 全局状态（providers）

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/presentation/providers/settings_providers.dart` | 主题服务（S-01）`AppSettingsController`（**唯一设置写入口**）+ 派生 Provider（如 `effectiveBlurProvider`）+ 每日一言 API/风格/语言选项表 | 改主题/设置状态逻辑、加设置项 |
| `lib/presentation/providers/platform_providers.dart` | 平台信息（S-04）快照：isWeb/isAndroid/SDK 版本（一次探测） | 需要按平台分支时读取，勿改 |
| `lib/presentation/providers/scroll_activity_provider.dart` | 全局「滚动/切页活跃度」（C-22 辅助件）：驱动快照心跳 | 改采样节流逻辑 |
| `lib/presentation/providers/blur_degrade_provider.dart` | 模糊降级策略（S-19）：快速滚动时临时降低模糊强度 | 调降级阈值/系数 |
| `lib/presentation/providers/steam_providers.dart` | P-08（v1.34.0）：Steam 查询服务注入点 + 凭证状态 `steamApiKeyProvider` + 存取/清除 helper（`saveSteamApiKey`/`clearSteamApiKey`/`steamApiKeyOrNull`） | 换 Steam 服务实现、改凭证读取 |
| `lib/presentation/providers/drag_active_provider.dart` | 卡片拖拽进行中标记（拖拽期首页禁滚） | 改拖拽与滚动互斥逻辑 |

### 1.4 数据层（domain / data / 数据 Provider）

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/domain/entities/app_settings.dart` | 设置实体（F-03/F-08）：uiMode/monetEnabled/keyColor/paletteStyle/blurEnabled/quote* 等 | 加设置字段 |
| `lib/domain/entities/course.dart` | 课程实体（P-06/S-15）：day×start×len 定位网格、week 单双周 | 改课程模型 |
| `lib/domain/entities/daily_activity.dart` | 每日活动实体（S-05）：一周 7 天起止分钟 + 启用开关 + JSON 编解码 | 改活动模型/默认时间 |
| `lib/domain/entities/home_card.dart` | 首页卡片数据模型（P-01-01）：sealed 类型 + `CardSize`（small/wide/large）+ `id`（排序/ValueKey）；v1.34.0 加 `HomeCardType.tool`/`ToolLaunchCardData` | 改卡片数据类/加新卡 |
| `lib/domain/entities/class_period.dart` | 节次时间表模型（S-02/P-06）：16 节起止分钟 + 启用开关、默认模板（前 12 节启用） | 改节次默认模板 |
| `lib/domain/entities/tool_config.dart` | 工具目录实体（F-04，v1.35.0 由 ToolItem 演进）：`ToolConfig`（JSON 外部化 —— 调用路径/参数/displayType/**`result` 字段映射**）+ `ToolCategory`/`ToolParamType`/`ResponseDisplayType` 枚举 + `ToolCategoryNode` 分组节点 | **加新工具 = 改 `assets/tools/tools.json`，不改代码** |
| `lib/domain/entities/steam_user.dart` | P-08（v1.34.0）：Steam 用户实体 + `SteamUserState`（0-6 状态标签）+ fromJson 容错解析 | 改响应字段映射 |
| `lib/domain/repositories/*.dart` | 仓库抽象（课程/每日活动/设置/协议） | 需要新存储源时扩展接口 |
| `lib/data/repositories/course_repository_impl.dart` | 课程存储实现（S-15）：整体 JSON 到 `course.list`、元信息 `course.meta` | 改课表读写/迁移 |
| `lib/data/repositories/daily_activity_repository_impl.dart` | 每日活动存储实现（S-05）：整表 JSON 到 `daily.activity`（<1KB） | 改活动读写 |
| `lib/data/repositories/settings_repository_impl.dart` | 设置存储实现（S-02）：各 `settings.*` key + `settings.cardOrder`，写合并防抖（300ms）；v1.34.0 加 `settings.homeToolItems` | 改设置持久化 |
| `lib/presentation/providers/course_provider.dart` | 课表状态：`CourseListNotifier`（增删改/导入合并持久化）+ `ScheduleMetaNotifier` + **`currentClassProvider`**（当前课程）+ **`nextClassProvider`**（下一节） | 改课表逻辑/倒计时计算 |
| `lib/presentation/providers/daily_activity_provider.dart` | 每日活动状态：`DailyActivityNotifier`（`updateDay`/`saveAll` 整表单写/`resetDefaults`）+ `todayRemainingProvider`（今日剩余计算） | 改剩余时间算法 |
| `lib/presentation/providers/home_cards_provider.dart` | 首页卡数据源：`gridCardsProvider`/`HomeCardsController`（网格顺序，竖/横各一套，排序持久化 `settings.cardOrder`）；v1.34.0 加 `homeToolItemsProvider`（首页工具目录，尾部动态追加工具启动卡） | 改卡片顺序/加默认卡/改工具目录持久化 |
| `lib/presentation/providers/nav_items_providers.dart` | 底栏项（`bottomBarItemsProvider`，首页/工具）与更多菜单项（`moreMenuItemsProvider`，设置/关于）数据源 | **加底栏页 / 加菜单项**（见 §2.3） |
| `lib/presentation/providers/agreement_provider.dart` | 协议状态管理（S-20）：`agreementProvider`（是否需要弹协议）+ `accept()` 落盘复位 | 改协议版本检查/同意逻辑 |
| `lib/domain/repositories/agreement_repository.dart` | 协议仓储接口（S-20）+ `kAgreementVersion` 常量 | **协议文案更新时改版本常量**（触发老用户重看） |
| `lib/data/repositories/agreement_repository_impl.dart` | 协议存储实现（S-20）：key `user_agreement_accepted` / `user_agreement_version` | 改协议落盘 |

### 1.5 页面（features）

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/presentation/features/home/page_p01_01_home_page.dart` | 首页（P-01-01）：C-25 顶栏 + C-26 菜单 + C-24 FAB + 摘要卡 + 卡片网格（C-34） | 改首页整体布局 |
| `lib/presentation/features/home/p05_activity_editor.dart` | 每日活动编辑器（P-05）：**deferred 懒加载**，首页卡片点击才载入；竖屏 BottomSheet/横屏 Dialog 自适应 | 改编辑交互（见 §2.5） |
| `lib/presentation/features/tools/page_p01_04_tools_page.dart` | 工具集页（P-01-04，一级页底栏第 2 项）：v1.35.0 **按 UAPI 实测分类分组** —— C-42 折叠面板（14 类默认折叠、点击展开、展开才渲染）+ C-36 入口（点按进工具、长按 500ms 添加至首页）；数据源 `toolCatalogProvider`（tools.json 启动预加载） | 改工具页分组/入口布局 |
| `lib/presentation/features/tools/page_p08_steam_query_page.dart` | Steam 用户查询页（P-08，v1.34.0，R-11 /steam）：四态机（idle/loading/success/error）+ 输入识别 + 成功详情卡 + 凭证入口（C-39） | 改查询页 UI/交互 |
| `lib/presentation/features/tools/page_p09_tool_generic.dart` | 通用工具页（P-09，v1.35.0，R-12 /tool/:toolId）：C-40 动态参数 + ToolApiService 统一调用 + C-41 结果展示；凭证行(C-39 复用)；无参工具进页自动请求；Steam 等定制路由工具不经此页 | 改通用页交互/状态机 |
| `lib/presentation/features/settings/page_p01_02_settings_page.dart` | 设置页（P-01-02，C-03 分组卡）：UI 模式/动效/悬浮底栏/内容设置（每日一言）/其他（调色板/权限/Steam 查询密钥/关于） | 加设置分组 |
| `lib/presentation/features/settings/page_p01_02_01_theme_config_page.dart` | 主题与色彩配置页（P-01-02-01）：深色/Monet/keyColor/PaletteStyle | 改主题设置 UI |
| `lib/presentation/features/about/page_p01_03_about_page.dart` | 关于页（P-01-03） | 改关于文案 |
| `lib/presentation/features/palette/page_p02_color_palette_page.dart` | 调色板展示页（P-02，只读） | 改色板展示 |
| `lib/presentation/features/permissions/page_p03_permissions_page.dart` | 权限页（P-03，静态声明） | 加权限声明 |
| `lib/presentation/features/timetable/page_p06_timetable_page.dart` | 大课表编辑页（P-06，周网格，可横滚） | 改课表编辑交互 |
| `lib/presentation/widgets/agreement_gate.dart` | 开屏协议门（P-07）：包住主框架，需弹 C-31 时屏蔽主界面并延迟加载 | 改协议弹出时机/入口 |
| `lib/presentation/widgets/c31_agreement_card.dart` | 鸿蒙风格协议卡（C-31，deferred）：遮罩+动画+自适应+协议链接 | 改协议文案/样式/按钮 |

### 1.6 首页卡片（cards/）

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/presentation/widgets/c34_responsive_card_grid.dart` | **C-34 响应式卡片网格**（v1.22.0）：CardSize 行流排布（行高 104，列数 2/3/4）；**v1.23.0 拖拽排序**（A-05：长按 300ms → 跟手 + 让位 300ms + 落位持久化，仿 iOS 阻尼）；**v1.23.1 横竖屏各一套顺序**；v1.34.0 switch 穷尽加 `ToolLaunchCardData` → C-37；**v1.34.2 编辑态**（长按静止松手进入：微缩 + 工具卡 ✕ 由槽位层叠加，主体 IgnorePointer 禁点，点空白/返回键退出） | **改网格布局/拖拽行为** |
| `lib/presentation/widgets/cards/card_shell.dart` | `CardShadow`：全首页卡片统一边缘阴影（浅/深 × 常态/浮起四组预构建） | 调阴影 |
| `lib/presentation/widgets/cards/card_summary.dart` | 首页摘要卡（C-27，v1.26.0 动态化；v1.27.0 点击刷新；v1.28.0 45 分钟自动换新）：问候语 S-22 + 每日一言 S-21（限 16 字，来源行仅真实出处非空显示）；整卡点击 → MiniToast 手动刷新（25s 冷却）；重建走 `refreshIfDayChanged` 跨天保守检查 | 改问候语卡片 |
| `lib/presentation/widgets/cards/card_class_countdown.dart` | 课程倒计时卡 A-04/C-33（网格 small 横排档）：三态（上课/空闲/未设时间），环 40 + 剩余百分比，每分钟刷新 | **改倒计时显示/交互** |
| `lib/presentation/widgets/cards/card_combo.dart` | 组合大卡 C-28（网格 large 2×2）：左列小课表（#a01 红卡：标题/当前课程大字/教室/下一节小字，整卡点击→大课表），右列今日剩余（#a04 厚轨圆环 + #a05 文本 + #a06 点击打开编辑器） | **改小课表/剩余环**（高频） |
| `lib/presentation/widgets/cards/card_dashboard.dart` | 仪表盘卡 C-29（网格 wide 2×1）：3 统计项 + 分段进度条 | 改统计展示 |
| `lib/presentation/widgets/cards/card_steam_tool.dart` | 工具启动卡 C-37（v1.34.0，网格 small）：徽标 + 工具名 + 点击进工具路由；**v1.34.2 起纯展示**（✕ 移除交互移交 C-34 编辑态，见上） | 改工具卡展示 |

### 1.7 底栏内核（kernel/ 与 C-22）

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/presentation/widgets/kernel/kernel_bottombar.dart` | KernelFloatingBottomBar：1:1 复刻 KernelSU `FloatingBottomBar.kt`（demo backup_08 移植），图标改用 MiuixVectorIcon | 改底栏本体视觉/手势 |
| `lib/presentation/widgets/kernel/damped_drag.dart` | DampedDragController：按压缩放 78/56 + 阻尼拖动 + 速度弹簧（Ticker + 半隐式欧拉） | 调按压/回弹手感 |
| `lib/presentation/widgets/kernel/inner_shadow.dart` | 内阴影（玻璃板厚度立体感，evenOdd 环形替代 BlendMode.Clear） | 调内阴影 |
| `lib/presentation/widgets/kernel/lens.dart` | 边缘折射（lens 着色器，FragmentShader） | 调折射彩虹 |
| `lib/presentation/widgets/kernel/dual_peak_highlight.dart` | 双峰高光（可关闭；当前 Pill+指示器已用 `dualPeak`，修黄双线问题） | 调居中高光 |
| `lib/presentation/widgets/kernel/blur.dart` | BackdropBlur：预模糊取样（像素映射到 backdrop.pixelRatio，配合降采样） | 调模糊实现 |
| `lib/presentation/widgets/c22_content_through_floating_bottom_bar.dart` | C-22 外壳：悬浮模式=Kernel 内核；普通模式=C22MaskSelectionBar；暴露 `contentBottomInset` | 改底栏与内容间距联动 |
| `lib/presentation/widgets/c22_mask_selection_bar.dart` | 蒙版选择栏（无毛玻璃/无动画的静态模式） | 改静态底栏样式 |
| `lib/presentation/widgets/c22_visual_params.dart` | **底栏全部视觉/物理参数单一事实源**（T58）——业务文件一律引用，禁止魔法数字 | 调底栏尺寸/速度/颜色参数 |
| `lib/presentation/widgets/c22_backdrop_heartbeat.dart` | 快照心跳（透明 CustomPaint 强制重绘采样，被动脉冲，无 Ticker） | 改快照刷新机制 |

### 1.8 通用组件

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/presentation/widgets/c21_collapsing_title_bar.dart` | 折叠标题栏（C-21，MiuixTopAppBar largeTitle）+ `C21CapsuleIconButton` 胶囊按钮 | 二级页大标题场景/顶栏按钮 |
| `lib/presentation/widgets/c23_push_collapsing_header.dart` | 内容推动折叠标题栏（自定义，大标题 1:1 上移） | 首页/设置/关于等统一顶栏 |
| `lib/presentation/widgets/c24_frosted_fab.dart` | 毛玻璃悬浮按钮（右下快捷入口） | 改 FAB 行为/位置 |
| `lib/presentation/widgets/c25_frosted_top_bar.dart` | 顶部标题栏（C-25）：**纯蒙版背景**（v1.24.0，不再采样模糊）——动效开关开=下部渐变半透明（无分界线过渡）/关=不透明遮罩；基色 surfaceContainer（跟随 Monet） | 改顶栏蒙版/渐变 |
| `lib/presentation/widgets/c26_more_menu.dart` | 顶部「更多」三点菜单（v1.32.1 定稿）：裸三点图标 + **`MiuixOverlayIconDropdownMenu`** 悬浮展开菜单（锚点定位，非底部弹层/非对话框），选中即收；菜单项在 `nav_items_providers.dart` | 改菜单样式/菜单项 |
| `lib/presentation/widgets/c27_prefrosted_blur.dart` | 预模糊组件（快照一次性模糊成纹理缓存，每帧 drawImageRect，Impeller 优化） | 毛玻璃性能优化参数 |
| `lib/presentation/widgets/c28_downsampled_capture.dart` | 降采样快照捕获（默认 downsample 0.5，toImageSync 成本约 1/4） | 改快照分辨率 |
| `lib/presentation/widgets/c32_ring_progress.dart` | 环形进度通用组件 C-32：`RingProgressPainter`（自今日剩余卡 1:1 抽取）+ `C32AnimatedRing`（800ms 平滑补间/跳变） | 画圆环的地方都走它 |
| `lib/presentation/widgets/c35_quote_option_sheet.dart` | **C-35 悬浮单选选择窗**（v1.27.0）：MiuixOverlayDialog 封装，内容设置三行共用（API/语言/风格），窄屏底部弹出/宽屏居中 | 改选择弹层 |
| `lib/presentation/widgets/c36_tool_entry_button.dart` | 工具入口按钮 C-36（v1.34.0；v1.35.0 数据源 `ToolItem`→`ToolConfig`）：48dp、MiuixCard squircle + CardShadow + sink 按压；点按 push 派生路由（customRoute 或 /tool/:id）、长按 500ms + 触觉弹「添加到首页」（MiuixOverlayDialog）；图标经 ToolBrandIcon（custom:steam 自绘 / MiuixIcons） | 改入口按钮行为/样式 |
| `lib/presentation/widgets/c39_steam_key_sheet.dart` | UAPI 密钥弹层 C-39（v1.34.0）：obscure 输入 + lock/unlock 明文切换 + 清除操作（P-08/P-09 共用） | 改凭证弹层 |
| `lib/presentation/widgets/c40_tool_dynamic_params.dart` | **C-40 动态参数输入**（v1.35.0）：按 `params` 配置生成控件 —— text/number(MiuixTextField)/select(胶囊单选)/其余兜底文本框 | 改参数控件类型 |
| `lib/presentation/widgets/c41_tool_result_display.dart` | **C-41 通用结果展示**（v1.35.0）：按 `displayType`+`result` 分发 —— image 两态(Image.memory 字节 / Image.network 字段 URL)/text/keyValue/list/json | 改结果模板/字段取值 |
| `lib/presentation/widgets/c42_tool_category_panel.dart` | **C-42 分类折叠面板**（v1.35.0）：分类头(MiuixPressable sink+旋转箭头)+ 分割线 + 展开区(AnimatedSize 300ms,懒渲染);入口网格列数复用 C-34 | 改分组折叠交互 |
| `lib/core/widgets/c03_group_card.dart` | 分组卡片（设置页标题卡 + 分隔线 C03IndentDivider；v1.35.1 深色外圈微亮描边光晕） | 设置页分组样式 |
| `lib/core/widgets/card_dark_glow.dart` | **CardDarkGlow**（v1.35.1）：深色卡片描边光晕统一入口 —— 1px 微亮描边 + 极弱白环境光，浅色零开销透传；radius 与内卡圆角对齐（MiuixCard 16 / C-42 标题 14） | 深色卡片描边参数(alpha/radius) |
| `lib/core/widgets/c05_warning_card.dart` | 警告横条（黄 warning / 红 error） | 出提示条 |
| `lib/core/widgets/c15_page_scale_container.dart` | 页面缩放容器（设置项 pageScale，纯几何；1.0 零开销直通） | 不用改 |
| `lib/core/widgets/app_icons.dart` | 图标统一出口 `appIcon(name)`（MiuixIcons.extended 缓存，未知回退箭头）；v1.34.0 注记 Steam 徽标为自绘 C-38 例外 | 换图标时经它取 |
| `lib/core/widgets/steam_logo_icon.dart` | **C-38 Steam 徽标自绘**（v1.34.0）：官方单色剪影 CustomPainter（路径程序化转换自 simple-icons steam.svg，非手绘），单一 tint 跟随主题 | 换徽标造型/取色 |
| `lib/core/widgets/tool_brand_icon.dart` | **C-38 泛化 `ToolBrandIcon`**（v1.35.0）：工具图标统一出口 —— `custom:steam` 走 SteamLogoIcon 自绘，其余 MiuixIcons.extended（工具 icon 缺省回退分类 icon） | 加新工具图标时经它 |
| `lib/core/widgets/app_scroll_behavior.dart` | 全局滚动物理：Bouncing（回弹）+ RangeMaintaining（刷新不跳） | 调全局滚动手感 |

### 1.9 基础设施（core）

| 文件 | 作用 | 什么时候改 |
| :--- | :--- | :--- |
| `lib/core/utils/u02_color_utils.dart` | 颜色工具（U-02）：Hex ↔ Color、对比度 | 颜色转换 |
| `lib/core/utils/u03_blur_policy.dart` | 毛玻璃策略（U-03）：Android 13+ 才真模糊，否则半透明降级；sigma 上限 20 | 调模糊门控 |
| `lib/core/utils/u04_platform_utils.dart` | 平台探测（U-04）：真实 API Level 探测（厂商 ROM 覆盖防御） | 不改，直接读 |
| `lib/core/logging/app_log_service.dart` | 日志服务（S-13）：分级 + 环形内存 + 全局异常捕获，可关零成本 | 加日志点 |
| `lib/core/logging/log_export_service.dart` | 日志导出（S-13 子服务）：序列化 .txt → 保存到公共 Download/（MediaStore） | 改导出格式 |
| `lib/core/logging/perf_monitor.dart` | 性能监控（S-14）：帧耗时→fps/平均/P95/掉帧（最近 600 帧环形） | 分析卡顿时看它 |
| `lib/core/refresh_rate/refresh_rate_controller.dart` | 高刷新率控制器（S-16）：帧活动期请求 120Hz，空闲 3s 释放（LTPO） | 调 idleTimeout |
| `lib/core/excel/excel_timetable_parser.dart` | Excel 课表解析（S-18，纯 Dart）：.xls/.xlsx → ParsedCourse（兼容合并单元格） | 改解析规则 |
| `lib/core/greeting/s22_greeting_service.dart` | 问候语生成（S-22，v1.26.0）：节日>节气>时段，2026 数据表；clock/random 可注入；同小时确定性 | 换问候文案/加节日 |
| `lib/core/quotes/s21_quote_service.dart` | 每日一言联网（S-21，v1.26.0；v1.27.0 UAPI 重写）：5 家免注册 API；UAPI 走 `/api/v1/saying/random`（语言 source / 风格 category，无日文原文）；from=真实出处，无则空 | 换 API/改解析 |
| `lib/core/tools/steam_api_service.dart` | P-08（v1.34.0）：UAPI `GET uapis.cn/api/v1/game/steam/summary` 客户端 —— 输入 4 格式识别（id3 单列，其余走 steamid 万能参数）+ 状态码 → 错误分类（400/401/404/502）；http.Client 可注入 | 改 Steam 请求/识别规则 |
| `lib/core/tools/steam_auth_service.dart` | P-08（v1.34.0）：凭证存储 —— Android/桌面 flutter_secure_storage（Keystore 加密），Web 降级 shared_preferences；接口可替换 | 改凭证存取/平台分支 |
| `lib/core/tools/tool_api_service.dart` | **P-09（v1.35.0）通用调用管道**：GET(query)/POST(json body+query 混合)；**双态返回**（json / 图片字节）；错误统一 `ToolApiException`（服务端 message 优先）；并发限制 3 + 同参去重；http.Client 可注入 | 改通用请求/错误分类/限流 |
| `lib/core/tools/tool_catalog_store.dart` | **F-04（v1.35.0）目录缓存单例**：`main()` 预加载 tools.json → 内存缓存；`byIdSync` 同步查询（首页卡对账）；`seedFallback` 降级内置 Steam | 改目录缓存/降级策略 |
| `lib/core/reminder/reminder_service.dart` | **课程提醒桥（v1.36.0）**：MethodChannel「xiangjugong/reminder」—— scheduleAlert(到点闹钟)/cancelAllAlarms/startCountdown(自治常驻)/stopCountdown/权限跳转(getDiagnostics) | 改提醒调度调用 |
| `lib/domain/entities/daily_quote.dart` | S-21 模型（v1.26.0；v1.27.0 +lang）：DailyQuote（content/from/api/style/lang/dateKey/fetchedAt）+ QuoteApi/QuoteStyle 枚举 | 改模型 |
| `lib/presentation/providers/quote_provider.dart` | S-21/S-22 首页内容源（v1.26.0；v1.27.0 手动刷新；v1.28.0 自动换新；v1.31.0 跨天保守检查）：dailyQuoteProvider（新鲜=同日&&同源&&同风格&&<45min，否则拉新）+ `forceRefresh`（25s 冷却）+ `autoRefresh`（45min Timer）+ `refreshIfDayChanged` + 本地文案池 | 改一言逻辑 |
| `lib/core/widgets/mini_toast.dart` | MiniToast 轻提示（v1.28.0，无编号）：MIUI 风格底部胶囊，Overlay 实现（MiuixScaffold 无 Material Scaffold，替代 SnackBar） | 出轻提示 |

---

## 2. 修改指南（想改 X → 去改 Y）

### 2.1 UI 相关

| 想改什么 | 去哪个文件 | 怎么改 |
| :--- | :--- | :--- |
| 卡片圆角/背景 | `cards/card_*.dart` | 改 `borderRadius`（如 15~20）与 `surfaceContainerLow`/`surfaceContainerHigh` 背景 |
| 卡片统一阴影 | `cards/card_shell.dart` | 改 `CardShadow`（DecoratedBox boxShadow，常态/浮起两档，深色提倍） |
| 网格行高/间距/列数 | `widgets/c34_responsive_card_grid.dart` | 改 `kGridRowHeight`/`kGridCardGap`/`gridColumnsForWidth` |
| 首页问候语/每日一言 | `providers/quote_provider.dart`（S-21/S-22） | 动态内容逻辑在那，别改静态文案 |
| 网格卡片顺序（数据源） | `providers/home_cards_provider.dart` | `gridCardsProvider` / `HomeCardsController.reorder`（拖拽 UI v1.23.0） |
| 小课表内容 | `cards/card_combo.dart` | 当前课程 `currentClassProvider` + 下一节 `nextClassProvider`（判空用 `courseListProvider`） |
| 今日剩余环样式 | `cards/card_combo.dart` + `widgets/c32_ring_progress.dart` | 环形统一用 `RingProgressPainter`/`C32AnimatedRing`（C-32） |
| 圆环点击行为 | `cards/card_combo.dart` | 改 `_openEditor()`（deferred 懒加载 ActivityEditor） |
| 底栏视觉/物理参数 | `widgets/c22_visual_params.dart` | **一律改这里**（唯一事实源，别在业务文件里写） |
| 底栏按压/回弹手感 | `widgets/kernel/damped_drag.dart` | 弹簧参数（如速度 spring） |
| 底栏内阴影/折射 | `widgets/kernel/inner_shadow.dart` / `lens.dart` | 改对应效果参数 |
| 顶部标题栏蒙版 | `widgets/c25_frosted_top_bar.dart` | 渐变（动效开关开）/实色（关）；改 `LinearGradient` stops 与基色（surfaceContainer） |
| 更多菜单项 | `providers/nav_items_providers.dart` | `moreMenuItemsProvider` 列表增删（iconName/label/route） |
| FAB 行为 | `widgets/c24_frosted_fab.dart` | 改 onPressed / 位置 |
| 全局主题/深色/Monet | 设置页 `P-01-02-01` + `main.dart` 的 `MiuixThemeController` | 不要硬编码颜色；走 keyColor/PaletteStyle（S-01） |
| 全局滚动手感 | `core/widgets/app_scroll_behavior.dart` | `BouncingScrollPhysics` 包装参数 |
| 图标统一入口 | `core/widgets/app_icons.dart` / `core/widgets/tool_brand_icon.dart` | `appIcon('名字')`，未知自动回退箭头；工具图标统一走 ToolBrandIcon（Steam 自绘 / MiuixIcons，v1.35.0） |
| 工具入口按钮/工具卡 | `widgets/c36_tool_entry_button.dart` / `cards/card_steam_tool.dart` | 改长按/点按行为或卡内容（工具目录在 `assets/tools/tools.json`，代码查询走 `core/tools/tool_catalog_store.dart` 的 `byIdSync`） |
| 加新工具/分类 | `assets/tools/tools.json` | **只改 JSON**（路径/参数/displayType/result 字段映射），零代码；图标/枚举兜底见 `domain/entities/tool_config.dart` |

### 2.2 数据相关

| 想改什么 | 去哪个文件 | 怎么改 |
| :--- | :--- | :--- |
| 课表增删改/导入 | `providers/course_provider.dart` | `addCourse`/`updateCourse`/`deleteCourse`/`importCourses`（Excel→ParsedCourse 走 S-18） |
| 课程落盘格式/key | `data/repositories/course_repository_impl.dart` | `course.list` / `course.meta` |
| 每日活动保存逻辑 | `providers/daily_activity_provider.dart` | `updateDay`（单天）/ `saveAll`（整表**单次写盘**，别每天调 updateDay） |
| 默认活动时间（工作日 09:00-18:00 等） | `domain/entities/daily_activity.dart` | 改 defaults 相关静态方法 |
| 今日剩余算法 | `providers/daily_activity_provider.dart` | `todayRemainingProvider`（ratio/leftText/deadlineText） |
| 设置项字段 | `domain/entities/app_settings.dart` + `settings_repository_impl.dart` + `settings_providers.dart` | 三处联动：实体加字段、repo 加 key、Controller 加 setter（参照 `setBlurEnabled`） |
| 本地存储 key | `data/repositories/*_impl.dart` | 各文件顶部 `_kXxx` 常量 |
| 首页工具目录（添加/移除） | `providers/home_cards_provider.dart` | `homeToolItemsProvider.notifier` 的 `add`/`remove`（持久化 `settings.homeToolItems`） |
| Steam 凭证 | `core/tools/steam_auth_service.dart` + `providers/steam_providers.dart` | 换存取实现/平台分支；密钥不回显、不入日志 |

**存储 key 全表**：`settings.uiMode / settings.monetEnabled / settings.keyColor / settings.paletteStyle / settings.blurEnabled / settings.floatingBarEnabled / settings.pageScale / settings.logCaptureEnabled`（S-02，300ms 防抖合并）｜`settings.classPeriods`（S-02，节次时间表 16 项 JSON）｜`settings.cardOrder`（S-02，首页网格卡顺序**竖/横两套** JSON 对象，旧数组自动迁移）｜`settings.dailyQuoteCache`（S-21 当日缓存）｜`settings.quoteEnabled/quoteApi/quoteStyle/quoteLang`（S-21）｜`settings.homeToolItems`（S-02，v1.34.0 首页工具目录）｜`settings.courseReminderEnabled`（S-02，v1.36.0 课程提醒总开关）｜`course.list`、`course.meta`（S-15）｜`daily.activity`（S-05）｜`user_agreement_accepted`、`user_agreement_version`（S-20）。Steam 凭证走 flutter_secure_storage（非 SharedPreferences，见 steam_auth_service.dart）。

### 2.3 路由与导航

| 想改什么 | 去哪个文件 | 怎么改 |
| :--- | :--- | :--- |
| 加顶层二级页 | `router/app_router.dart` | 先在 features/ 下建页面 → 在 `_knownPaths` 加路径 → 追加 `GoRoute`（分配 R-xx）→ 加入口（菜单项或按钮 `context.push`） |
| 加一级页（底栏页） | `providers/nav_items_providers.dart` + `shell/main_shell_page.dart` | 在 `bottomBarItemsProvider` 加 `C22BarItemData`（PageView 页数与底栏同源自动跟随）；在 features/ 下建页面并加入 PageView 列表；注意若在 R-03 `/tools` 之后还需同步 redirect 映射 |
| 加底栏项跳转页面 | `providers/nav_items_providers.dart` | 改项顺序/图标 key（如 home/tools） |
| 改页面入口路由 | `router/app_router.dart` | 改 `route` 字段；老路径别删（redirect 兼容） |
| 底部→二级页 | 任意按钮 | `context.push('/settings')` 等（覆盖 shell） |

### 2.4 状态管理（Riverpod）

| 想改什么 | 去哪个文件 | 怎么改 |
| :--- | :--- | :--- |
| 改 Provider 状态逻辑 | `presentation/providers/` | `AsyncNotifier`/`Notifier` 子类；只经 public setter 改状态 |
| 订阅最小化（防重建） | 各页面 | `ref.watch(provider.select(...))`，别整包 watch |
| 新增全局状态 | `presentation/providers/` | 新建 `xxx_provider.dart`；启动注入的放 main.dart override |

### 2.5 每日活动编辑器（P-05）专项

| 想改什么 | 去哪个文件 | 怎么改 |
| :--- | :--- | :--- |
| 编辑交互（一次编辑一天） | `features/home/p05_activity_editor.dart` | 顶部 7 个 MiuixTabRow + `_DayEditorForm`（整页滚动）；竖屏 BottomSheet / 横屏 Dialog 自适应 |
| 时间输入（时/分双框） | 同上，`_TimeField` | 独立时分框 + 中间冒号，失焦提交（勿改成输入中自动格式化，会丢位） |
| 键盘弹起布局 | 同上 | `MiuixOverlayBottomSheet` + `AnimatedPadding(viewInsets)` + `defaultWindowInsetsPadding:false` |
| 保存按钮消失/点不到 | 同上 | 按钮在滚动体内；外层 `ConstrainedBox(maxHeight: (屏高-键盘)×0.85)` |
| 卡片点开入口 | `cards/card_combo.dart` | `_openEditor()` + deferred import（#a20） |

---

## 3. 组件编号速查

| 编号 | 组件 | 文件位置 | 用途 |
| :--- | :--- | :--- | :--- |
| C-03 | 分组卡片 | `lib/core/widgets/c03_group_card.dart` | 设置页分组（MiuixCard+分隔线） |
| C-05 | 警告卡片 | `lib/core/widgets/c05_warning_card.dart` | 黄/红警告横条 |
| C-15 | 页面缩放容器 | `lib/core/widgets/c15_page_scale_container.dart` | 设置项 pageScale 几何缩放 |
| C-21 | 折叠标题栏 | `lib/presentation/widgets/c21_collapsing_title_bar.dart` | 大标题→小标题折叠 |
| C-22 | 悬浮底栏（主） | `c22_content_through_floating_bottom_bar.dart` | 底部导航（液态玻璃内核/蒙版双模式），见 §1.7 全家 |
| C-23 | 内容推动折叠标题栏 | `c23_push_collapsing_header.dart` | 首页/设置/关于统一顶栏 |
| C-24 | 毛玻璃 FAB | `c24_frosted_fab.dart` | 右下悬浮快捷按钮 |
| C-25 | 顶部标题栏 | `c25_frosted_top_bar.dart` | 纯蒙版背景（开=渐变/关=不透明） |
| C-26 | 顶部更多菜单 | `c26_more_menu.dart` | 裸三点 + MiuixOverlayIconDropdownMenu 悬浮菜单（设置/关于；v1.32.1 定稿） |
| C-27 | 预模糊组件 | `c27_prefrosted_blur.dart` | 快照一次性模糊纹理（性能） |
| C-28 | 降采样快照捕获 | `c28_downsampled_capture.dart` | 快照降采样（downsample 0.5） |
| C-27 | 首页摘要卡 | `cards/card_summary.dart` | 问候语 + 每日一言（v1.26.0 动态化） |
| C-28 | 组合大卡 | `cards/card_combo.dart` | 小课表 + 今日剩余环 |
| C-29 | 仪表盘卡 | `cards/card_dashboard.dart` | 3 统计+分段进度 |
| C-30 | 占位卡 | ~~`cards/card_placeholder.dart`~~ | **v1.34.1 停用**：占位卡体系移除，文件已删除（编号保留不重用） |
| C-31 | 协议卡 | `widgets/c31_agreement_card.dart` | 鸿蒙风格开屏协议卡（毛玻璃/大圆角 24/双按钮/deferred） |
| C-32 | 环形进度 | `widgets/c32_ring_progress.dart` | RingProgressPainter + C32AnimatedRing（平滑补间） |
| C-33 | 课程倒计时卡 | `cards/card_class_countdown.dart` | A-04（网格 small）：当前课程环 40+剩余百分比 |
| C-34 | 响应式卡片网格 | `widgets/c34_responsive_card_grid.dart` | 首页网格：尺寸档/列数 2-3-4/行流排布（拖拽 v1.23.0；**编辑态 v1.34.2**） |
| C-35 | 悬浮单选选择窗 | `widgets/c35_quote_option_sheet.dart` | 内容设置 API/语言/风格选择浮窗（v1.27.0） |
| C-36 | 工具入口按钮 | `widgets/c36_tool_entry_button.dart` | 工具目录入口（48dp，squircle+CardShadow+sink）：点按进路由 / 长按 500ms+触觉弹「添加到首页」（v1.34.0） |
| C-37 | 工具启动卡 | `cards/card_steam_tool.dart` | 首页网格尾部动态卡（点击进工具；纯展示,v1.34.2 起 ✕ 由 C-34 编辑态叠加）（v1.34.0） |
| C-38 | Steam 徽标自绘 | `core/widgets/steam_logo_icon.dart` | 官方剪影 CustomPainter（路径程序化自 simple-icons，非手绘；tint 单色）（v1.34.0） |
| C-39 | UAPI 密钥弹层 | `widgets/c39_steam_key_sheet.dart` | 查询页/通用页共用：obscure 输入 + lock/unlock 切换 + 清除（C-35 同体系）（v1.34.0） |
| C-40 | 动态参数输入 | `widgets/c40_tool_dynamic_params.dart` | 按 tools.json `params` 配置生成控件（text/number/select 胶囊；v1.35.0） |
| C-41 | 通用结果展示 | `widgets/c41_tool_result_display.dart` | displayType 分发：image 两态/text/keyValue/list/json（v1.35.0） |
| C-42 | 分类折叠面板 | `widgets/c42_tool_category_panel.dart` | 工具页分组：默认折叠/点击展开/懒渲染（v1.35.0） |
| C-22 内核组 | （无独立编号） | `widgets/kernel/*.dart` | KernelSU 1:1 复刻的底栏内核（见 §1.7） |
| — | 块级编号 | 卡片内注释 | `#a01` 小课表（标题/当前课程/下一节）/ `#a04` 环 / `#a05` 文本 / `#a06` 点击区（剩余环→编辑器；小课表整卡→大课表）/ `#a10` 单天视图 / `#a20` 懒加载编辑器 |

> C-01/C-02/C-12 为早期设计编号（主框架注释残留），现窄屏底栏由 C-22 承担、宽屏为 `MiuixNavigationRail`，无独立文件，不要去找。

---

## 4. 页面入口速查

| 页面 | 编号 | 路由 | 入口方式 | 文件位置 |
| :--- | :--- | :--- | :--- | :--- |
| 主框架 | P-01 | `/`（R-01） | 应用启动 | `shell/main_shell_page.dart` |
| 首页 | P-01-01 | `/home`→`/?page=0`（R-02） | 底栏第 1 页 | `features/home/page_p01_01_home_page.dart` |
| 工具集 | P-01-04 | `/tools`→`/?page=1`（R-03） | 底栏第 2 页（C-42 分类折叠分组，v1.35.0） | `features/tools/page_p01_04_tools_page.dart` |
| 设置 | P-01-02 | `/settings`（R-04） | 顶部三点菜单 | `features/settings/page_p01_02_settings_page.dart` |
| 关于 | P-01-03 | `/about`（R-05） | 顶部三点菜单 | `features/about/page_p01_03_about_page.dart` |
| 调色板 | P-02 | `/color-palette`（R-06） | 设置页入口 | `features/palette/page_p02_color_palette_page.dart` |
| 权限 | P-03 | `/permissions`（R-07） | 设置页入口 | `features/permissions/page_p03_permissions_page.dart` |
| 主题配置 | P-01-02-01 | `/settings/theme`（R-08） | 设置页入口 | `features/settings/page_p01_02_01_theme_config_page.dart` |
| 大课表 | P-06 | `/timetable`（R-10） | 首页组合卡「查看全部」（#a02） | `features/timetable/page_p06_timetable_page.dart`（含**节次时间表** 16 节设置） |
| Steam 用户查询 | P-08 | `/steam`（R-11） | 工具页入口点按 / 首页工具卡（C-37）点击 | `features/tools/page_p08_steam_query_page.dart`（四态机；凭证 C-39；服务 `core/tools/steam_api_service.dart`+`steam_auth_service.dart`，v1.34.0） |
| 通用工具 | P-09 | `/tool/:toolId`（R-12） | 工具页非定制工具点按 / 首页工具卡（C-37）点击 | `features/tools/page_p09_tool_generic.dart`（C-40/C-41/`core/tools/tool_api_service.dart`，v1.35.0） |
| 每日活动编辑器 | P-05 | （非路由弹层） | 首页组合卡剩余环点击（#a06）→ deferred 懒加载 | `features/home/p05_activity_editor.dart` |
| 开屏用户协议 | P-07 | （启动浮层，非路由） | 首次启动/协议版本变更自动弹出；Gate 包在 `main_shell_page.dart` 外层 | `widgets/agreement_gate.dart` + `widgets/c31_agreement_card.dart` |

> R-09 编号按历史预留未占用；未知路径统一 redirect 到 `/?page=0`。

---

## 5. 常见问题速查（FAQ）

### Q：改完代码不生效？
1. 运行中按 `r`（热重载）或 `R`（热重启）；改了 `main.dart`/`pubspec.yaml` 需重启或重新 `run`。
2. 确认改的文件是对的（对照 §2 表）。
3. 看控制台报错；`flutter analyze` 查静态问题。

### Q：怎么找某页面/组件对应文件？
看界面上的编号线索 → 对照 §3 组件表 / §4 页面表 → 打开文件。文件头注释都有「编号：XX」可交叉验证。

### Q：怎么加一个新首页卡片？
1. `domain/entities/home_card.dart` 加数据类（继承 sealed `HomeCardData`，给唯一 `id` 与 `CardSize`：1 格 small / 2×1 wide / 2×2 large）。
2. 在 `cards/` 新建 `card_xxx.dart`（参考 C-33 紧凑结构；尺寸按格高：small 行高 104）。
3. `home_cards_provider.dart` 的 `kDefaultGridCards` 加入默认实例（替换一张占位卡）；组件分发在 `c34_responsive_card_grid.dart` 的 `_cardWidget` switch 补分支（sealed 穷尽，漏分支编译报错）。
4. 真实数据在卡内自己 watch Provider（顺序与静态文案在 provider 里）。

### Q：怎么加一个新一级页（底栏页）？
1. `nav_items_providers.dart` 的 `bottomBarItemsProvider` 加 `C22BarItemData(key, 标签)`（页数自动跟随）。
2. `features/` 新建页面文件，并加入 `main_shell_page.dart` 的 PageView 页列表。
3. 若页面可用 URL 直达，同步 `app_router.dart` 的 redirect 与 `_knownPaths`。
4. 图标用 `appIcon()` 取。

### Q：怎么改底栏（项数/大小/颜色）？
- 项数/标签 → `nav_items_providers.dart`；页间横滑联动 → `main_shell_page.dart`。
- 尺寸/动画/颜色等视觉物理参数 → **只改** `c22_visual_params.dart`（防魔法数）；按压手感 → `kernel/damped_drag.dart`。

### Q：毛玻璃没生效？
U-03 策略：Android 13+ 才真模糊；**Android 12 及以下 / Web 一律半透明降级**（属预期）。真机连不上时可查 `u04_platform_utils.dart` 的 API 探测（厂商 ROM 覆盖防御）。

### Q：想调性能/看帧率？
`core/logging/perf_monitor.dart`（S-14，开启后环形记录最近 600 帧，可导出分析）；滚动时毛玻璃掉帧 → 查 `blur_degrade_provider.dart`（S-19 降级）、C-27/C-28 是否启用。设备锁屏/失焦报 "Lost connection" 属正常。

### Q：怎么构建发布？
```bash
flutter analyze                       # 先零告警
flutter build apk --release           # Android 正式包（入口默认 lib/main.dart，勿加 -t）
flutter build web --release           # Web 包（产物在 build/web，部署前清空旧目录再传）
```
产物复制到 `发布包/` 目录，文件名带版本（如 `xiangjugong_vX.Y.Z_official-release.apk`）。升版本：**功能→minor、修复/优化→patch，只升不降**，同步 `pubspec.yaml` 与 `CHANGELOG.md`。

### Q：为什么不能用 Material 组件？
项目约定界面全部使用 flutter_miuix 组件（MiuixCard/MiuixButton/MiuixText 等），Material 仅保留 `MaterialApp` 作 Flutter 壳与个别底层类型（如 `TextField` 输入、`RangeMaintainingScrollPhysics`）。新 UI 一律参照既有文件风格。

### Q：数据丢了/想重置？
每日活动：设置或编辑器内「恢复默认」（`resetDefaults`）；手动清数据即删除对应 key（见 §2.2 存储 key 表）。
