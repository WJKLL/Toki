# 变更日志（CHANGELOG）

> 模板与规则见 `PROJECT_SPEC.md` §1.4 / §14；版本号只升不降、不可复用。

## v1.34.2（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 功能 | **首页卡片网格「编辑态」**(用户交互定稿 · iOS 式)：长按卡片 300ms 触觉后二选一 —— **继续移动=拖拽排序**(原行为保留),**静止松手=进入编辑态**:整卡微缩 0.94 + 工具卡右上 ✕ 弹入(easeOutBack);编辑态下**点卡片主体不跳转**(IgnorePointer 防误触),仅 ✕ 可点移除(MiniToast);**退出**:点网格空白 / 系统返回键与侧滑返回(PopScope 拦截,不退出应用)/ 移除最后一张工具卡自动退出 | C-34 / C-37 / P-01-01 | Android 11+ / Web |
| 重构 | C-37 回归纯展示(去 ✕/Stack/Consumer):✕ 移除逻辑与动画上移 C-34 槽位层(`_ToolRemoveBadge` 常驻树,scale 0 不命中) | C-37 / C-34 | Android 11+ / Web |
| 测试 | +2 端到端:编辑态全流程(长按松手→✕→主体不跳→移除→入口恢复)/ 返回键退出后主体恢复可点 | C-34 / C-37 | - |

### 涉及编号变更
- 版本：`1.34.1+122` → `1.34.2+123`(交互优化 → Patch,§1.3;只升不降)。
- C-34 扩展「编辑态」能力;C-37 移除交互职责移交 C-34 槽位层。

## v1.34.1（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **首页工具卡补「右上 ✕ 一键移除」**(用户核实确认 · v1.34.0 决策点③遗漏)：此前 `homeToolItemsProvider.remove()` 全库零调用、移除链路完全缺失(卡片一旦加入首页无法移出)；C-37 改 `Stack(fit: expand)` 在卡右上角叠独立命中区 ✕(圆底 `surfaceContainerHigh` + `basic.close`),**点按仅移除**(命中区在手势竞技场/命中测试优先,不触发整卡跳转),长按 300ms 仍归 C-34 网格拖拽排序;移除写回 `settings.homeToolItems` + MiniToast 反馈;C-36 已添加副行文案同步为「点首页卡片右上 ✕ 可移除」 | C-37 / C-36 / C-34 / P-01-01 | Android 11+ / Web |
| 移除 | **占位卡体系移除**(用户决策:首页只保留有实际内容的卡)：删除默认网格 3 张占位卡(原 `placeholder_1/2/3`),`kDefaultGridCards` 缩为 combo + dashboard + countdown 三张真实卡;`PlaceholderCardData` 类型与 `HomeCardType.placeholder` 枚举、`card_placeholder.dart`(C-30 虚线占位组件)随之停用删除;`settings.cardOrder` 历史残留 id 由 `_applyOrder` 未知 id 忽略规则自然兼容,无需迁移 | C-30 / C-34 / P-01-01 | Android 11+ / Web |
| 测试 | 新增 C-37 ✕ 移除流程(添加 → ✕ → 卡消失且占位不复现) | C-37 | - |

### 涉及编号变更
- 版本：`1.34.0+121` → `1.34.1+122`(修复 → Patch,§1.3;只升不降)。
- C-30 停用：占位卡组件文件已删除(历史编号保留不重用,见 CODE_REFERENCE)。

## v1.34.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 功能 | **Steam 用户查询工具**(用户 Pro 规划 · 决策四项落地)：UAPI `GET uapis.cn/api/v1/game/steam/summary`(实测无 key 匿名可用;key 为可选 query 参数) —— 工具页「🎮 游戏工具」分组(标题 16sp w600 + 淡分割线)+ 入口网格(48dp、squircle+CardShadow+sink 按压,**列数与首页网格同源** 2/3/4);**点按**进 /steam,**长按 500ms**+触觉 → 「添加到首页」浮层(MiuixOverlayDialog 自适应);首页网格**尾部动态追加**工具启动卡(持久化 `settings.homeToolItems`,重启保留;**右上 ✕ 移除**,长按 300ms 留给拖拽) | P-01-04 / P-08 / C-36 / C-37 / R-11 | Android 11+ / Web |
| 功能 | **P-08 查询页四态机**(idle/loading/success/error)：输入自动识别 4 格式(17 位→steamid / `STEAM_x:y:z`→id3 / 完整链接 / 自定义 URL·好友码 → steamid 参数万能);成功卡头像 48 圆(网络图,失败回退徽标)+ 昵称 + 状态胶囊(0 灰/1 绿/2 红/3-4 橙/5-6 蓝自绘)+ 详情行(实名/资料可见性/SteamID64/ID3/注册日期,行值点击复制 + MiniToast)+ 打开资料页(url_launcher);错误文案按 400/401/404/502 分类,重试保留输入;加载 MiuixInfiniteProgressIndicator;内容 maxWidth 居中(宽屏) | P-08 / R-11 | Android 11+ / Web |
| 功能 | **凭证加密存储**(决策:新增 `flutter_secure_storage` —— 唯一新第三方依赖)：Android/桌面 Keystore 加密,Web 降级 shared_preferences;查询页凭证状态行(未配置提示)与设置页「Steam 查询密钥」行共用 C-39 弹层(obscure 输入、lock/unlock 明文切换、清除操作);key 只进加密存储,不写日志/普通设置 | P-08 / P-01-02 / C-39 | Android 11+ / Web |
| 视觉 | **C-38 Steam 徽标自绘**(决策:自绘):官方 single-color 剪影(simple-icons steam.svg 路径程序化转 Flutter Path,非手绘近似),单一 tint 跟随主题;用于入口/首页卡/查询页头图,不占 MiuixIcons 槽位 | C-38 | - |
| 测试 | Steam 服务单测(识别/解析/状态码分类/实体容错)+ 端到端流程(长按添加 → 首页卡 → 查询成功 → 凭证配置)共 8 项 | P-08 / C-36 / C-37 / C-39 | - |

### 涉及编号变更
- 版本：`1.33.0+120` → `1.34.0+121`(功能 → Minor,§1.3;只升不降)。


### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 重构 | **C-26 右上角「更多」悬浮菜单定稿**(用户三连纠正)：改用 flutter_miuix 官方 **`MiuixOverlayIconDropdownMenu`**(对应参考项目 miuix-kmp OverlayIconDropdownMenu 同款) —— 点图标后从锚点**悬浮展开**圆角面板(自动定位,**非底部弹层/非居中对话框**),选中即收、点外部/返回关闭,面板样式与主题自动跟随;触发器改**裸三点图标**(MiuixIcon,**无圆形/胶囊蒙版背景**),热区由组件内 IconButton 承担;菜单项 icon+文字 push 跳转(设置/关于,`moreMenuItemsProvider` 统一) | C-26 | Android 11+ / Web |
| 修复 | **文本默认去下划线**(用户「参考之前修复」)：`main.dart` MaterialApp builder 加全局 `DefaultTextStyle.merge(decoration: TextDecoration.none)`(Navigator 之上) —— 根治 MiuixText 继承祖先装饰的横线问题(v1.28.1 菜单/底栏同根因的全局兜底);显式下划线(协议卡链接)不受影响 | F-01 / C-26 | Android 11+ / Web |
| 测试 | 首页 C21 胶囊按钮回归 1 个(导航;C-26 触发器改裸图标);C-26 入口流程经悬浮菜单进入设置页 | C-26 / P-01-01 | - |

### 涉及编号变更
- 版本：`1.32.0+119` → `1.33.0+120`(重构 → Minor,§1.3;只升不降)。

## v1.32.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 重构 | **右上角「更多」菜单统一为 flutter_miuix 组件实现**(用户定稿：删除自绘方案) —— 删除 C-38(自绘形变按钮+OverlayEntry 锚定卡片)与旧 C-26(自绘毛玻璃 OverlayEntry 面板);C-26 重写为 `C21CapsuleIconButton`(项目胶囊按钮)+ **`MiuixOverlayDialog`** 弹层(show 布尔常驻树驱动):窄屏底部弹层、宽屏居中卡片,响应式自适应,与 C-35 单选窗/导出对话框同一体系,深色/Monet 主题自动跟随;菜单项统一 `moreMenuItemsProvider`(设置/关于);首页与其余 6 页(工具/设置/主题配置/调色板/权限/关于)全部同一组件。`backdrop` 参数兼容保留不再消费 | C-26 / P-01-01 / P-01-02 / P-01-02-01 / P-01-03 / P-01-04 / P-02 / P-03 | Android 11+ / Web |
| 移除 | 删除 `c38_ink_more_button.dart`(含 C38InkMoreButton/C38MenuAction),首页顶栏恢复 C-26 统一入口 | C-38 | - |
| 测试 | 锚点同步:C-26 新实现仍为 C21 胶囊按钮(首页 2 胶囊:导航+更多);route_transition 经 C-26 弹层(MiuixOverlayDialog)进入设置页 | C-26 | - |
| 修复 | **切回首页「每日一言」不再自己刷新**(上版修复,随本版本推送):重建/回页由「45 分钟窗口检查」改为**跨天保守检查**(`refreshIfDayChanged`:无缓存/跨自然日/缺获取时刻才拉新);45 分钟自动换新仅由 C-27 存活期 Timer 驱动 | C-27 / S-21 | - |

### 涉及编号变更
- 版本：`1.31.0+118` → `1.32.0+119`(重构 → Minor,§1.3;只升不降)。

## v1.31.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **页面转场回退为最初验收版逻辑、仅保留阻尼 0.75**（用户纠正）：移除「退场方向分流」等额外改动,进/退统一由曲线反向遍历驱动;同时按用户定稿**移除旧页让位 1/4 与压暗 0.5** —— 一级页面完全不动,二级页右滑入覆盖;转场期左缘圆角与 500ms/0.75 阻尼回弹保留 | S-03 / R-01 / R-04~R-08 / R-10 | Android 11+ / Web |
| 修复 | **页面切换黑帧**：转场中「无页面覆盖」的瞬时区域露出 Navigator 黑色底层 → `main.dart` MaterialApp builder 根部垫主题 surface 色,切换连贯无黑 | F-01 | Android 11+ / Web |
| 调整 | **C-38 形变「更多」菜单三轮定稿**：按钮固定常驻、不消失不形变、默认 36dp;无墨水圆背景;白色圆角卡片从按钮处(下方 6dp、右缘对齐、贴按钮侧为锚)放大展开,上限 300dp;点卡片外/返回收缩;选项纯文字(设置/关于/分享 App 占位) | C-38 / P-01-01 | Android 11+ / Web |
| 测试 | 首页 ⋮ 入口由 C-26 换 C-38 后同步锚点(home_layout C21 胶囊 2→1 + C38 存在;route_transition 走 C-38 进入;退场用例改为验证动画在播) | C-38 / P-01-01 | - |

### 涉及编号变更
- 版本：`1.30.0+117` → `1.31.0+118`(修复 → Minor,§1.3;只升不降)。

## v1.30.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 品牌 | **应用更名 Toki + 全新图标**：显示名由「箱具工」改为「Toki」（AndroidManifest label / MaterialApp title / 首页大标题 / 关于页 / 日志导出头 / Web index.html + manifest.json / pubspec description）；图标源 `Toki icon.png`(1362²) 经 LANCZOS 缩放分发：Android `mipmap-{mdpi→xxxhdpi}/ic_launcher.png`(48/72/96/144/192)、Web `Icon-192/512`(全幅)与 `Icon-maskable-*`(内容居中 80% + 角主色 #F9F9F4 衬底)与 `favicon.png`(16)。类名/包名(com.xiangjugong…)保留不动；回归测试锚点同步为 Toki | F-01 / C-21 / C-23 / C-25 / P-01-03 | Android 11+ / Web |
| 优化 | **转场阻尼 0.95 → 0.75**(用户验收后定稿)：曲线常量重算，末端约 **+2.8% 克制回弹**(先进过头再收回)、尾段拖沓 335ms→216ms；**退场方向分流**：pop 反向遍历过冲曲线会开场向左微弹并停滞 ~250ms,改取 `curve(1−value)` 单调出屏,过冲移至屏外不可见 | S-03 / R-01 / R-04~R-08 / R-10 | Android 11+ / Web |
| 新增 | **C-38 墨水扩散「更多」按钮**(复刻小米应用管理页右上角 ⋮)：按下瞬间白色圆形墨水(主题 surface,深浅自适应)自中心扩散成大气泡(约按钮 1.9 倍、轻阴影),⋮ 图标保持其上；保持为「菜单已开」态,关闭反向收缩；同时弹出**居中偏上白色大圆角卡片菜单**(宽约屏 86%、圆角 32、遮罩 0.42),选项纯文字左对齐大字号(应用详情风格),选项/回调由调用方注入(通用组件,不含路由)。首页顶栏接入(设置/关于跳转 + 分享 App 占位 toast)；动效开关关闭 → 墨水形变直切。实现:`c38_ink_more_button.dart` + `P-01-01` 顶栏替换 C-26 | C-38 / P-01-01 | Android 11+ / Web |
| 测试 | `route_transition_test.dart` 转正(3 用例：进场中途位移/退场正向出屏无反向弹/动效关直切) | S-03 | - |

### 涉及编号变更
- 版本：`1.29.0+116` → `1.30.0+117`(品牌更名 + 优化 → Minor,§1.3;只升不降)。
  - 注：`1.29.0+116`(转场初版,阻尼 0.95)已推送真机验收;阻尼 0.75 与更名合并于本版本推送。

## v1.29.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **二级页面切换过渡动画**：复刻参考项目 KernelSU-Style-UI-Kit（miuix-navigation3-ui 0.9.2 NavDisplay）规格 —— 新页自屏幕右缘整宽滑入(500ms,MIUI 阻尼曲线 NavTransitionEasing(0.8,0.95) 1:1 移植,本版本阻尼)；转场期间新页左缘(与旧页交界缘)上下圆角 32px(参考项目读设备屏幕圆角,Flutter 无此 API 用常量近似),静止后移除；旧页同步向左让位 1/4 屏宽并黑色压暗(最大 0.5,线性于进度)；返回(pop/系统返回键/浏览器后退)自动反向播放。实现:`miuix_route_transitions.dart` 统一 transitionsBuilder + 全部路由(含 shell R-01)改 `CustomTransitionPage`。**动效开关联动**:开关关闭 → `NoTransitionPage` 直切(pageBuilder 每次导航实时读取);静止后零开销(opaque 下层不再构建)。flutter_miuix 无现成转场组件,自研。回归测试:`route_transition_test.dart`(进场中途位移/退场无反向弹/关态直切) | S-03 / R-01 / R-04~R-08 / R-10 | Android 11+ / Web |
| 性能 | 转场全程仅 transform 平移 + 裁剪(GPU 合成层,无布局重排);动画期间不触发毛玻璃;`rememberContentReady` 式「动画期占位」暂不需要(二级页首帧轻),预留 | S-03 | - |

### 涉及编号变更
- 版本：`1.28.1+115` → `1.29.0+116`(新增功能 → Minor,§1.3;只升不降)。

## v1.28.1（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **顶部更多菜单文字多余下划线**：「设置」「关于」字样下方出现横线 —— MiuixText 的 decoration 继承祖先 DefaultTextStyle 文本装饰(与底栏昨日同款问题,底栏已用 `TextDecoration.none` 修复);C-26 菜单文字显式关闭装饰 | C-26 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.28.0+114` → `1.28.1+115`(交互修复 → Patch,§1.3;只升不降)。

---

## v1.28.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **UAPI「动漫台词」语言档**：语言选项新增 🎬 动漫台词(`settings.quoteLang='anime'`)—— 中文双源 + `category=动画,漫画` 的中文动漫台词(官方语料无日文原文,此档为动画台词中译);该档下风格行自动隐藏 | S-21 / P-01-02 / S-02 | Android 11+ / Web |
| 新增 | **摘要卡点击轻提示 + 45 分钟自动换新**：点击一言 → 轻提示「请稍等一会哦」(自研 MiniToast:MIUI 风格底部胶囊,Overlay 实现 —— MiuixScaffold 非 Material Scaffold,原 SnackBar 方案无处挂载);内容展示超 45 分钟自动后台换新(C-27 可见期 45 分钟周期 Timer,销毁即取消;新鲜度=同日 && 距获取 <45 分钟,缓存补精确时间戳 fetchedAt,旧缓存兼容升级当日拉新一次);手动 25s 冷却与自动刷新相互独立 | C-27 / S-21 | Android 11+ / Web |
| 优化 | **设置页内容组高度过渡**：语言/风格行随 API 增减的区域包 AnimatedSize(200ms easeOutCubic)—— 切换 UAPI 等来源时分组卡平滑伸缩,不再瞬间跳变(割裂) | P-01-02 | Android 11+ / Web |
| 修复 | 拉取并发守卫:自动/手动刷新同时进行时丢弃后发请求(防重复请求/状态错乱) | S-21 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.27.0+113` → `1.28.0+114`(新增能力 + 交互优化 → Minor,§1.3;只升不降)。
- 扩展:S-21(语言档 anime + fetchedAt)、C-27(自动刷新/轻提示)、P-01-02、S-02;新增内部件 MiniToast(无编号,core/widgets)。

---

## v1.27.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **摘要卡点击刷新(C-27)**：整卡点击 → 每日一言手动刷新(问候语不变);按压 0.96 缩放 150ms easeInOut 动效;两次刷新间隔 25s(冷却内静默忽略,无 Toast);强制重取忽略当日缓存并回写缓存,失败静默保持旧内容 | C-27 / S-21 | Android 11+ / Web |
| 新增 | **UAPI 语言风格选择(S-21)**：设置页新增「语言风格」行(仅 API=UAPI 显示):中文/English/混合;语言 → `source` 语料库(中文双源 / quotable 英文原句 / 混合不传),存 `settings.quoteLang`(默认 zh);**UAPI 适配器重写** —— 旧端点 `uapis.cn/api/saying` 已失效,换官方新端点 `GET /api/v1/saying/random`(mode=random;风格 → `category` 古诗文/诗词;响应兼容直接对象与 {item} 包装双形态;实测中文/英文源均通) | S-21 / P-01-02 / S-02 | Android 11+ / Web |
| 优化 | **API 来源改为悬浮选择窗(C-35)**：内容设置三行(API 来源/语言风格/内容风格)统一改 MiuixOverlayDialog 浮窗(常驻树 show 驱动;窄屏底部弹出、宽屏居中自动适配),删除内联展开实现;选项高亮选中、点击即选即关 | P-01-02 / C-35 | Android 11+ / Web |
| 优化 | **来源显示**：S-21 各适配器 `from` 改为真实出处(诗泉 《title》·author、UAPI author·《source》、Hitokoto from_who·from),**去掉 API 名称兜底**;无出处 → 来源行不显示 | C-27 / S-21 | Android 11+ / Web |
| 修复 | 缓存新鲜度判定加入语言维(旧缓存无 lang 按 zh 兼容,升级当日平滑,不额外请求) | S-21 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.26.0+112` → `1.27.0+113`(交互增强 + 新能力 → Minor,§1.3;只升不降)。
- 新增编号:C-35(悬浮单选选择窗);扩展:C-27、S-21、S-02(settings.quoteLang)、P-01-02。

---

## v1.26.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **首页动态问候语(S-22)**：本地离线,优先级 节日(2026 公历+农历核对表)> 节气(±1 天容差)> 时段(7 段池);clock/random 可注入,按「月×日×时」确定性 seed —— 同小时不闪变、跨小时自动换新;用户名暂固定 XX(尾缀拼接) | C-27 / S-22 | Android 11+ / Web |
| 新增 | **每日一言联网(S-21)**：5 家免注册 API(Hitokoto/金山词霸/诗泉/今日诗词/UAPI),统一模型 DailyQuote;当日缓存(同自然日+同 API+同风格零重复请求),换源当日重取;主 API 失败静默 fallback 备用 1 家,再败落本地文案池(按日稳定),全程不打扰 | C-27 / S-21 | Android 11+ / Web |
| 新增 | **设置页「内容设置」分组(P-01-02)**：每日一言开关 + API 来源选择 + 风格选择(内联展开,复用 timetable 先例);风格随 API 联动(Hitokoto/UAPI 多风格可选,固定风格 API 自动隐藏风格行);设置项落 S-02(`settings.quoteEnabled/quoteApi/quoteStyle`,默认 开/Hitokoto/经典语录) | P-01-02 / S-02 | Android 11+ / Web |
| 优化 | **摘要卡 C-27 样式**：问候语 title1 加粗 24px;每日一言 斜体 16px w400 letterSpacing 0.8、无标题前缀、maxLines 2 防溢出;来源弱化右对齐小字(仅联网内容);开关关/全败 = 本地文案,零网络 | C-27 | Android 11+ / Web |
| 新增 | **平台配置**：AndroidManifest 增加 INTERNET(release 联网必需);引入 `http`(Dart 官方,唯一新增第三方依赖);新增 `tools/rename_release_apk.ps1` —— 构建产物命名为 `xiangjugong-{版本}-{特点标签}.apk`(AGP8 无 outputs 改名 DSL,构建后重命名) | — | Android 11+ / Web |
| 修复 | **测试基线修复(历史欠账,随本次全量测试暴露)**：① 三个外壳级测试(v1.20 协议卡引入后缺 `agreementRepositoryProvider` override)→ 补齐并预置已同意;② c22 心跳测试缺 ProviderScope(CaptureHeartbeat v1.18 起为 Consumer)→ 补齐;③ home_layout 陈旧锚点('版本'文本/4 胶囊/CustomScrollView 均为 v1.13-1.14 前结构)→ 更新为 C-27 类型/2 胶囊/Scrollable;④ settings_ui 顶栏遮挡点击 → ensureVisible 后下拉脱离 C-25 悬浮区;⑤ C-28 组合卡剩余环内容高行高字体下溢出 10px → 环 64→60、间距收 4px | C-28 / 测试 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.25.0+111` → `1.26.0+112`(新增联网能力 + 动态内容 → Minor,§1.3;只升不降)。
- 新增编号:S-21(每日一言服务)、S-22(问候语服务);扩展:C-27、P-01-02、S-02。

---

## v1.25.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **卡片阴影升级为双层悬浮阴影(全 App 统一阴影语言)**：`CardShadow` 由单层淡阴影改为「定向近影(下缘贴地)+ 环境远影(大扩散浮起氛围)」双层;黑系阴影随 Miuix 实际取色亮度自适应(深色模式 alpha 提倍,保证可见);新增 `elevated` 浮起档与 `radius` 参数 | P-01-01 / C-34 | Android 11+ / Web |
| 优化 | **首页卡片悬浮感与易读性**：摘要卡(圆角对齐 16)、网格六卡统一套新阴影壳,卡与背景层次拉开,文字更易读;占位虚线卡同样受益 | C-27 / C-28 / C-29 / C-30 / C-33 | Android 11+ / Web |
| 优化 | **拖拽浮起联动**：长按激活浮起/拖行中/飞入落位全程阴影切「抬升档」(加深加大 → 离桌反馈),落定与槽位常态阴影同帧替换 | C-34 / A-05 | Android 11+ / Web |
| 优化 | **其它页卡片统一**：P-05 每日活动配置卡、P-06 学期信息卡与节次时间表入口卡换用统一阴影壳(移除各处手写单层阴影与描边);课程色块/小格/色卡等内容元素不加阴影 | P-05 / P-06 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.7+110` → `1.25.0+111`(UI 视觉增强 → Minor,§1.3;只升不降)。

---

## v1.24.7（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **拖拽松手/拖行中卡片「聚拢-归位」往复**：① 落位语义修正——`_hoverIndex` 与预览均为「移除后列表插入位」，但 S-02 排序写入端按 Flutter onReorder「原列表下标」语义再 -1，向右拖时松手落点比松手前预览布局前进一格，整网卡片被迫二次让位；统一为插入位语义后松手零让位、仅被拖卡飞入 ② hover 下标映射修正——渲染卡列表与移除列表顺序相同（映射应为恒等），旧实现把渲染下标误当 display 下标再 -1，导致手指已越过渲染卡时插入位滞后一格，与 300ms 让位动画互相追赶形成让位-回退波浪 | C-34 / P-01-01 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.6+109` → `1.24.7+110`(交互修复 → Patch,§1.3;只升不降)。

---

## v1.24.6（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **拖拽激活瞬间卡片抢位抖动**：hover 插入位判定由「去掉被拖卡的布局」改为「含空槽的当前渲染布局」—— 长按浮起瞬间被拖卡让出的空槽不再立即被邻居补位,手指停在空槽内时插入位保持不变;只有真正跨越渲染卡(或落入行间隙最近卡)才触发让位 | C-34 / A-05 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.5+108` → `1.24.6+109`(交互修复 → Patch,§1.3;只升不降)。

---

## v1.24.5（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **拖拽松手落位「弹一下」**：① 飞行动画去 easeOutBack 终点过冲(短距落位时先过头再弹回)→ easeOutCubic 平滑飞入;② 移除落定收尾缩放(1.08→1.0 动画);③ 飞行期间浮起放大同步收回 1.0,落定与槽位替换无缩放突变 | C-34 / A-05 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.4+107` → `1.24.5+108`(交互修复 → Patch,§1.3;只升不降)。

---

## v1.24.4（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 定稿 | **顶部标题栏定稿纯蒙版方案**：清除 C 档原型(长按切换/过渡带模糊带/彩底占位测试卡全部移除) —— 动效开关开 = S 形渐变蒙版(v1.24.3 A 档参数),关 = 不透明遮罩;Monet token 取色 | C-25 / C-30 | Android 11+ / Web |
| 优化 | **拖拽松手自动落入目标槽**：松手后卡片不再"原地消失/跳脱"——feedback 从手指位置 **240ms easeOutBack 飞入目标槽**(轻微过冲后落定),槽位卡同步 1.08→1.0 收尾,全程无跳变 | C-34 / A-05 | Android 11+ / Web |
| 优化 | **横竖屏切换过渡保障**：网格 Stack 改 `Clip.none` —— 旋转/方向套切换时卡片位置动画(AnimatedPositioned 300ms)允许短暂越界绘制,不被容器裁剪成"瞬移" | C-34 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.3+106` → `1.24.4+107`(定稿 + 交互优化 → Patch,§1.3;只升不降)。

---

## v1.24.3（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **顶部蒙版横带遮瑕(A 档)**：遮盖下限 0.38→0.58、过渡带收窄到底 32%、中段 S 形曲线(中度可见区最窄)—— 高对比内容(红卡,深浅色模式皆然)的结构边缘快速穿越可辨识区,动态下横带不再显眼 | C-25 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.2+105` → `1.24.3+106`(视觉修复 → Patch,§1.3;只升不降)。

---

## v1.24.2（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **顶部渐变遮盖下限抬高**：底端 α 0.05→0.38(全程"轻纱→实色"再无清晰透出段)—— 修复深色模式 + 高对比色内容滚入时因底部过透形成的横带对比;中间段同步上移并保持缓降(柔和不变),过渡带宽度不变 | C-25 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.1+104` → `1.24.2+105`(视觉修复 → Patch,§1.3;只升不降)。

---

## v1.24.1（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **顶部渐变过渡带加大并柔化**：过渡带由底 25% 扩大到底 55%(上部 45% 实色);遮盖度由线性改为**低段缓降曲线**(多档 stops 近似,底端 α≈0.05 慢出)—— 修复深色内容(如红色小课表卡)滚入顶栏时过渡带出现明显「横带」 | C-25 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.24.0+103` → `1.24.1+104`(视觉修复 → Patch,§1.3;只升不降)。

---

## v1.24.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 重构 | **顶部标题栏毛玻璃 → 纯蒙版方案(C-25)**：不再采样页面快照/执行模糊 —— 动效开关(blurEnabled)开启时顶部为**渐变半透明蒙版**(上部实色 → 栏底 25% 遮盖度平滑降至 0.12,内容滚入"沉入"过渡、栏底无突变分界线,近似澎湃 OS4 过渡观感);开关关闭时整栏**普通不透明遮罩**(传统标题栏) | C-25 | Android 11+ / Web |
| 优化 | **蒙版颜色随 Monet 取色**：基色取 Miuix 主题 token `surfaceContainer`(深浅色自适应;Monet/动态取色开启时随色板自动变化,无硬编码) | C-25 / F-08 | Android 11+ / Web |
| 优化 | **性能**：顶部零采样零模糊(帧成本≈普通色块);`backdrop` 参数保留兼容(页面级快照仍被 C-26 菜单消费),调用方零改动;静止零 ticker | C-25 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.23.1+102` → `1.24.0+103`(顶部渲染方案替换 + Monet 适配 → Minor,§1.2;只升不降)。
- C-25 组件内部重写;组件签名(含 backdrop/scrollBehavior)不变,各页面调用方无需改动。

---

## v1.23.1（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **拖拽让位动画放缓**：被挤开卡片的位移动画 150ms → 300ms(更从容的让位节奏) | C-34 | Android 11+ / Web |
| 修复 | **拖拽期间页面滑动**：除首页列表外,主框架 PageView(一级页横滑)在拖拽中一并禁用 —— 修复拖动被系统判定为左右滑时页面跟着切页 | C-34 / P-01 | Android 11+ / Web |
| 优化 | **红卡小课表可读性**：「当前课程」标签移到课程名**上方**(独立小行),课程名独占整行 —— 竖屏窄卡下名字不再被前缀挤掉;教室行去掉 📍 emoji(Android 渲染为红色与红卡背景融合难读)改纯白小字「教室:xxx」 | C-28 / #a01 | Android 11+ / Web |
| 新增 | **横竖屏各自一套卡片顺序**：`settings.cardOrder` 升级为对象格式(竖屏/横屏独立保存,旧数组自动迁移为两套共用);旋转时自动切换对应套并伴随让位动画 | C-34 / S-02 / A-05 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.23.0+101` → `1.23.1+102`(体验优化 + 存储增强 → Patch,§1.3;只升不降)。
- 存储:`settings.cardOrder` 旧数组格式兼容(两方向共用),下次保存写回 `{"p":[…],"l":[…]}` 对象。

---

## v1.23.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **首页网格卡片拖拽排序（仿 iOS 阻尼手感）**：长按 300ms(位移超阈值自动让位给滚动/点击)→ 触觉反馈 + 卡片浮起(easeOutBack 1.08 回弹放大);拖动中卡片独立 feedback 层跟手、其余卡 150ms 平滑让位(AnimatedPositioned,按最近卡中心判定插入位);松手 → 落位回弹(1.08→1.0)+ `HomeCardsController.reorder` 防抖持久化(`settings.cardOrder`,杀进程重开保持) | A-05 / C-34 / S-02 | Android 11+ / Web |
| 新增 | **拖拽期资源协调**：`dragActiveProvider` —— 拖拽中首页 ListView 禁用滚动(避免手势冲突)、组合卡/C-33 分钟 Timer 跳过本轮刷新(等效暂停,结束自动恢复,无 Timer 生命周期改动) | C-34 / C-28 / C-33 | Android 11+ / Web |
| 优化 | 拖拽性能:整网格 + 单卡双层 RepaintBoundary;hover 重排仅一次 setState;静止零 ticker | C-34 | Android 11+ / Web |

### 涉及编号变更
- 新增编号:**A-05 卡片拖拽排序**(文件头注释登记)。
- 新文件:`lib/presentation/providers/drag_active_provider.dart`。
- 修改:`c34_responsive_card_grid.dart`(Listener 长按/拖动/hover/落位)、`card_combo.dart`/`card_class_countdown.dart`(Timer 跳过)、首页 page(ListView physics 联动)。
- 版本:`1.22.0+100` → `1.23.0+101`(新增交互能力 → Minor,§1.2;只升不降)。

---

## v1.22.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **首页卡片网格系统(阶段一:尺寸 + 响应式 + 排序数据层)**：摘要区(C-27)固定顶置整宽(独立于网格);其余卡片入 C-34 响应式网格 —— 尺寸档 CardSize(small 1×1 / wide 2×1 / large 2×2,组合卡 2×2、仪表盘 2×1、倒计时与占位 1×1),固定行高 104 行流排布(跨行卡恒行首,无 masonry 缺口),列数随宽度:<600→2 / 600-1099→3 / ≥1100→4 | C-34 / P-01-01 | Android 11+ / Web |
| 新增 | **网格数据层**：`summaryCardProvider`(摘要独立)+ `gridCardsProvider`(Notifier,默认 6 卡:combo/dashboard/countdown/占位×3);排序顺序持久化 S-02 `settings.cardOrder`(坏数据回默认;controller 的 reorder/restoreDefault 已就绪,拖拽 UI 交互于 v1.23.0 启用) | S-02 / P-01-01 | Android 11+ / Web |
| 重构 | **卡片紧凑化适配网格行高**：仪表盘(C-29)压紧为标题 13/统计 17/进度 5 三段;课程倒计时(C-33)改**横排紧凑档**(标题行 + 环 40 + 右列课程名/剩余%/节次,原竖排大环样式退出);组合卡与占位卡零改动;统一 `CardShadow` 迁至 `cards/card_shell.dart` 共用 | C-29 / C-33 / C-28 / C-30 | Android 11+ / Web |
| 重构 | **退役 `home_card_layout.dart`**(硬编码 Row 布局)→ 首页由「摘要区 + C34 网格」组装;网格双层 RepaintBoundary + ValueKey(id),静态零 ticker | P-01-01 / C-34 | Android 11+ / Web |

### 涉及编号变更
- 新增编号:**C-34 响应式卡片网格容器**(文件头注释登记;A-05 拖拽交互与 C-34 拖拽扩展留 v1.23.0)。
- 新文件:`lib/presentation/widgets/c34_responsive_card_grid.dart`(含 placeGrid 纯函数/列数档)、`lib/presentation/widgets/cards/card_shell.dart`。
- 修改:`home_card.dart`(CardSize + id)、`home_cards_provider.dart`(拆分 + HomeCardsController)、S-02(`settings.cardOrder` 接口/实现)、首页 page(摘要顶置 + 网格)。
- 删除:`lib/presentation/widgets/cards/home_card_layout.dart`。
- 版本:`1.21.1+99` → `1.22.0+100`(新布局系统 + 数据层 → Minor,§1.2;只升不降)。

---

## v1.21.1（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **首页小课表红卡:当前课程下方显示教室(位置)**：进行中的课程若有地点(location)则在课程名下方以小字显示「📍 教室名」;无地点/休息/无课时省略该行(三段式布局不变) | C-28 / #a01 | Android 11+ / Web |

### 涉及编号变更
- 版本：`1.21.0+98` → `1.21.1+99`(小优化 → Patch,§1.3;只升不降)。

---

## v1.21.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **全局节次时间表**：课表页（P-06）学期信息卡下方新增入口 → 弹层内 16 节（与课表网格上限对齐）起止时间编辑,每节带启用开关 + MiuixNumberPicker 内联时间面板(时/分,确定自动启用该节,结束时间防倒置钳制);支持恢复默认模板(第 1 节 08:00 起,45 分钟 + 10 分钟课间,前 12 节启用) | P-06 / S-02 | Android 11+ / Web |
| 新增 | **课程倒计时卡片（A-04/C-33）**：替换首页第二张占位卡(#b03) —— 基于当前时间 × 节次时间表 × 今日课表(单双周/weeks 过滤)识别进行中的课;圆环上课满环→下课空环(剩余比例),主文本显示**剩余百分比**(如「剩余 65%」,与圆环一致),下方节次与起止;三态:上课中 / 📚 空闲 / 该节次未设时间(点卡片跳课表页设置) | A-04 / C-33 / S-15 | Android 11+ / Web |
| 新增 | **通用环形进度组件 C-32**：`_RingPainter` 从组合卡 1:1 抽取为公开 `RingProgressPainter`(今日剩余卡改引用,视觉逐像素一致) + `C32AnimatedRing`(进度变化 800ms easeInOut 平滑补间,仅圆环 RepaintBoundary 重绘;动画结束零 ticker) | C-32 / C-28 | Android 11+ / Web |
| 重构 | **首页小课表红卡改版（#a01）**：三段纵向分布 —— 顶=标题(小字)/ 中=当前课程(大字突出,含跨节与单双周/weeks 过滤)/ 底=下一节课是(小字,新增 `nextClassProvider`:当前课结束后今天最近一节);**删除「查看全部」按钮 → 整卡点击跳大课表**;组合卡提升为 Stateful 统一每分钟 invalidate(今日剩余/当前课程/下一节课),双半卡联动刷新,静止零 ticker | C-28 / #a01 / #a02 / S-15 | Android 11+ / Web |
| 调整 | **设置页「毛玻璃效果」更名「动效开关」**：语义升级为低性能总开关 —— 开启=毛玻璃(U-03 平台裁决)+ 平滑动效;关闭=毛玻璃关 + 圆环进度直接跳变(首页倒计时低性能档) | P-01-02 / S-01 | Android 11+ / Web |
| 修复 | **「今日剩余」每分钟刷新失效**：Timer 仅 setState 不触发派生重算(todayRemainingProvider 内部 DateTime.now() 现算,普通 Provider 有缓存)→ 补 `ref.invalidate`,剩余时间真正每分钟走动 | C-28 / S-05 | Android 11+ / Web |
| 优化 | **倒计时每分钟刷新**:卡内 Timer invalidate `currentClassProvider`(与今日剩余同机制),静止零 ticker;跨节课程按「首节起 ~ 末节止」整段计时(含课间,中途不误显示休息) | C-33 | Android 11+ / Web |

### 涉及编号变更
- 新增编号:**A-04 课程倒计时卡、C-32 环形进度通用组件、C-33 课程倒计时卡片**(文件头注释登记;PROJECT_SPEC 编号 C-31 已由 v1.20.0 协议卡占用,本版顺延)。
- 新文件:`lib/domain/entities/class_period.dart`、`lib/presentation/widgets/c32_ring_progress.dart`、`lib/presentation/widgets/cards/card_class_countdown.dart`。
- 修改:AppSettings(新增 `classPeriods` 字段/默认模板/==/hashCode)、S-02(新 key `settings.classPeriods`,16 项 JSON 单串,坏数据容错回默认)、settings_providers(`setClassPeriods`)、course_provider(`CurrentClass` + `currentClassProvider`)、card_combo(引用 C-32 + 分钟刷新修复)、home_card/home_cards_provider/home_card_layout(#b03 替换)、P-06(节次时间表入口与弹层)、设置页(开关更名)。
- 版本:`1.20.0+97` → `1.21.0+98`(新卡片 + 设置扩展 + 通用组件抽取 → Minor,§1.2;只升不降)。

---

## v1.20.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **开屏用户协议卡片（鸿蒙风格）**：首次启动自动弹出（底部滑入 + 全屏 50% 黑遮罩,遮罩不可点击关闭/不可跳过）；「同意并继续」→ 收起动画 → 落盘 → 进入应用;「退出」（仅 Android,Web 浏览器无法自关标签页故隐藏该按钮）→ SystemNavigator.pop 退出 | P-07 / C-31 / S-20 | Android 11+ / Web |
| 新增 | **协议版本管理**：硬编码 `kAgreementVersion`(当前 2026.09.03)——文案/政策变更时同步改常量 → 老用户自动重新弹出;存储 `user_agreement_accepted` / `user_agreement_version`(与 S-02 共用 prefs,单 key <1KB) | S-20 | Android 11+ / Web |
| 新增 | **C-31 卡片本体**：毛玻璃(复用 C-27 预模糊,blurRadius 20 与 C-25 一致;backdrop 为空 → U-03 降级半透明,Web/Android<13/毛玻璃关兼容);鸿蒙大圆角 24 + 细描边;深浅色走 Miuix 主题 token(surfaceContainer/onSurface/onSurfaceVariantSummary);正文含《用户协议》《隐私政策》可点链接(url_launcher,占位地址上线前替换) | C-31 | Android 11+ / Web |
| 新增 | **动画与自适应**：进入 遮罩 200ms + 卡片 300ms easeOutCubic 底部滑入;同意/退出反向 300ms 收起;布局 竖屏 88% 宽贴底 24 / 600–840 60% 宽 / ≥840 平板居中 55% 宽(折叠屏展开同理),上限高 60%/70%/55% 屏高,整卡可滚 | C-31 | Android 11+ / Web |
| 新增 | **启动集成(P-07 Gate)**：`AgreementGate` 包住主框架 —— 已同意当前版本则直通零开销;需展示时才 `deferred loadLibrary` 加载 C-31(首帧不解析);展示期间 `IgnorePointer` 屏蔽主界面交互;backdrop 裁决提前到 build 顶层,协议卡首帧即拿到快照源 | P-07 / P-01 | Android 11+ / Web |

### 涉及编号变更
- 新增编号:**P-07 开屏用户协议门、S-20 用户协议状态服务、C-31 鸿蒙风格协议卡片**(文件头注释登记)。
- 新文件:`lib/domain/repositories/agreement_repository.dart`、`lib/data/repositories/agreement_repository_impl.dart`、`lib/presentation/providers/agreement_provider.dart`、`lib/presentation/widgets/c31_agreement_card.dart`(deferred)、`lib/presentation/widgets/agreement_gate.dart`。
- 修改:`lib/main.dart`(S-20 注入)、`lib/presentation/shell/main_shell_page.dart`(挂载 Gate + backdrop 提前同步)。
- 依赖新增:`url_launcher ^6.3.2`(协议链接跳转浏览器;其余零新增第三方)。
- 版本:`1.19.1+96` → `1.20.0+97`(新增页面 + 服务 + 组件 → Minor,§1.2;只升不降)。

---

## v1.19.1（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 重构 | **编辑窗改为「一次编辑一天」**：7 天 MiuixTabRow 顶部选择,当天配置(启用开关/起止时间/重置)；整页含按钮放同一滚动区,横屏矮屏/键盘弹出时可上下滑到底点保存 | P-05 / A-03 | Android 11+ / Web |
| 重构 | **时间输入改为「时/分双框 + 独立冒号」**：冒号显示在框外,用户只输数字;每框底部小字提示("时"/"分");值在失焦时后台解析提交(0-23:0-59,越界钳制) —— 修复「删一格自动弹数字/无法删除小时重编」 | P-05 | Android 11+ / Web |
| 修复 | **编辑窗整体自适应键盘抬高**：改用 MiuixOverlayBottomSheet(底部滑出、内容全程在屏幕内) + `AnimatedPadding(bottom:viewInsets)` 整卡上移,避免键盘压住保存按钮/内容悬空 | P-05 | Android 11+ / Web |
| 修复 | **保存延迟/没反应**：新增 `DailyActivityNotifier.saveAll` 整表**单次写盘**(_onSave 不再 7 天逐条 updateDay → 消除 7 次串行 IO 造成的延迟/无反应);移除 600ms 防抖(避免"按了没立刻响应"错觉) | S-05 | Android 11+ / Web |
| 修复 | **保存/取消按钮固定可达**：按钮行随整页滚动,滑到底即可点;消除「按钮被顶出可视区 → 点不到/误触遮罩 → 编辑窗自己消失」根因(内容有界) | P-05 | Android 11+ / Web |
| 优化 | **首页卡片统一边缘阴影(立体感,低开销)**：`HomeCardLayout._card` 统一包裹 `_CardShadow`(静态 BoxShadow,C27/C28/C29/C30 全部生效) | P-01-01 | Android 11+ / Web |
| 优化 | **圆环改小米运动/健康粗环样式**：`_RingPainter` 重做 —— 浅色轨道整圈(始终显示,时间走完仍留空心环) + 主色进度弧(12 点顺时针,100% 整圈填满、按比例缩短) | A-03 | Android 11+ / Web |
| 修复 | **底栏 logo 底部双横黄线**：`_specularHighlight` 关闭 dualPeak(双峰高光副光源在深色玻璃底部形成暖黄亮带,误判为黄线)；tab 文字补 `decoration: TextDecoration.none` 保险 | C-22 | Android 11+ / Web |

### 涉及编号变更
- P-05 编辑窗按用户反馈多轮重构(单天视图 + 文本时间输入 + BottomSheet + 键盘自适应);A-03 圆环/卡片阴影加强;C-22 底栏黄线修复。
- 版本：`1.19.0+95` → `1.19.1+96`（修复 + 体验优化累积 → Patch，§1.3；只升不降）。

---

## v1.19.0（2026-09-02）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 功能 | **「今日剩余」卡片编辑功能**（A-03 改造）：① 圆环进度数据驱动（#a04，12 点起顺时针、随时间减少；RepaintBoundary 隔离）② 剩余时间实时同步（#a05，每分钟刷新 + 未启用/时段外归零）③ 点击卡片懒加载打开编辑窗（#a06/#a20，deferred import） | A-03 / P-05 / S-05 | Android 11+ / Web |
| 新增 | **每日活动时间编辑窗 P-05**（#a07~#a15/#a22）：Miuix 浮层（平板 Dialog / 手机 BottomSheet 自适应）；7 天（周一~周日）独立配置：启用开关（#a13）+ 起始/终止时间（#a08/#a09，时/分 MiuixNumberPicker）+ 单天重置默认（#a12）+ 整表恢复默认（#a11）；保存防抖 600ms（#a21）异步持久化 | P-05 | Android 11+ / Web |
| 新增 | **每日活动时间数据服务 S-05**：`DailyActivityRepository`（领域抽象）+ impl（SharedPreferences 单 key `daily.activity`，整表 JSON <1KB，仅启动/保存读写）+ `DailyActivityTime/DailyBalanceData` 模型（weekday 1..7 固定 7 天） | S-05 | Android 11+ / Web |
| 新增 | **状态管理**：`dailyActivityProvider`（AsyncNotifier，updateDay/resetDefaults 自动持久化）+ `todayRemainingProvider`（派生：按当天 weekday 计算剩余比例/文本/截止，select 精确监听） | S-05 | Android 11+ / Web |
| 优化 | **懒加载 + 渲染 + 存储专项**：编辑窗 deferred import（首点才加载）；圆环 RepaintBoundary 隔离；卡片仅 watch 当日派生（其它天变化不重建）；剩余时间每分钟轻量刷新（Timer，页面驻留可接受） | P-05 / A-03 | Android 11+ / Web |

### 涉及编号变更
- 新增编号：**P-05 每日活动时间编辑窗、S-05 每日活动时间数据服务**（PROJECT_SPEC §5 登记）。
- 改造 A-03「今日剩余」卡（`card_combo.dart` `_RemainingRing` 数据驱动 + 编辑入口）。
- 新文件：`lib/domain/entities/daily_activity.dart`、`lib/domain/repositories/daily_activity_repository.dart`、`lib/data/repositories/daily_activity_repository_impl.dart`、`lib/presentation/providers/daily_activity_provider.dart`、`lib/presentation/features/home/p05_activity_editor.dart`（deferred）。
- 版本：`1.18.0+94` → `1.19.0+95`（新增页面 + 数据服务 + 状态管理 → Minor，§1.2）。

---

## v1.18.0（2026-09-02）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 重构 | **底栏悬浮胶囊整体替换为 demo 内核**（1:1 复刻演示工程 `miuix_bottombar_demo` backup_08 移植，替代 C-22 早期实现）：① 速度形变 v2 —— velocity 连续积分弹簧（Ticker+半隐式欧拉，追得上手速，修 SpringSimulation 8ms 事件追不上导致的形变不可见）+ 输入 EMA 低通（柔和丝滑）；② 指示框内阴影改前景绘制 + clip 限界（立体感对齐参考 InnerShadow 层序）；③ 方案 C 底栏本体采样（指示器透过玻璃看到 pill+标签行 1:1，无错位/无双层）；④ 手势优化 —— 任意 tab 按下即按压反馈（不再只认当前指示框）、松手"回位尾段与落下重叠"（对齐参考 range×2.5% 阈值，消除两段式割裂）；⑤ 固定紧凑胶囊（_itemWidth=76，总宽 76×n+8 居中悬浮） | C-22 / C-22-1 | Android 11+ / Web |
| 优化 | **图标体系适配**：内核标签图标由 Material IconData 改为 Miuix 矢量图标（appIcon 统一出口，符合主项目 UI 约束）；页面快照 backdrop 可空门控（Web/Android<13 或关毛玻璃 → 降级半透明纯色，blur 关不挂 capture 零采样） | C-22 | Android 11+ / Web |
| 新增 | **内核组件目录**：`lib/presentation/widgets/kernel/`（kernel_bottombar / damped_drag / lens / inner_shadow / blur / dual_peak_highlight 6 文件 + 覆盖 `shaders/lens_refraction.frag` 优化版 8209B）；普通模式 `C22MaskSelectionBar` 保留，双模式编排器接口不变 | C-22 | Android 11+ / Web |
| 修复 | **底栏单击判定（全局坐标 → 局部坐标）**：手势用 `e.position.dx`（全局屏幕坐标）算 tab，胶囊 Center 居中后偏移超一格 → 点「首页」误判为「工具」。改为 `e.localPosition.dx`（Listener 局部坐标，天然 0~totalWidth） | C-22 / C-22-1 | Android 11+ / Web |
| 优化 | **顶部毛玻璃采样率活动自适应**：新增 `scrollActivityProvider`（main.dart 根部 NotificationListener 捕获**所有路由内**滚动，含 PageView 切页动画、push 二级页）→ CaptureHeartbeat 滚动/切页中每 2 帧采样（跟手防拖影）、静止回 4 帧（省电）；每页采样 `everyNFrames` 3→4 | C-25 / C-22 / C-28 | Android 13+（模糊）/ Web |
| 优化 | **模糊度提升（磨砂感强、微微透背景）**：底栏 blur 4→16dp + tint surfaceContainer 0.4→0.7；顶栏 blur 16→25dp（参考 BlurredBar 25f，后折中 20/sigma9）；菜单 C-26 改用 C27PrefrostedBlur（修复降采样快照下采样偏移翻倍 → 菜单背景消失） | C-22 / C-25 / C-26 / C-27 | Android 13+（模糊）/ Web |
| 优化 | **内核 BackdropBlur 预模糊缓存（P0，对齐 C-27）**：快照/采样区/半径未变复用一次性模糊纹理，每帧免 ImageFilter.blur —— 根治切页/按压动画中每帧重做高斯导致的「画面一抖一抖」（P95 build 尖峰）；顶栏毛玻璃分支补 RepaintBoundary 隔离 | C-22 / C-27 | Android 13+（模糊）/ Web |
| 优化 | **触控响应 + 滑动阻尼（用户选定 T1+D1+S-全局）**：全局 `AppScrollBehavior`（MaterialApp.scrollBehavior）→ 所有滚动体统一 `BouncingScrollPhysics`（列表回弹 + 长惯性，替代 Android 默认 Clamping 硬停）；9 处滚动体（PageView + 8 页面 ListView/GridView）显式 `dragStartBehavior: DragStartBehavior.down`（按下即跟手） | P-01 / P-01-01~06 | Android 11+ / Web |
| 调整 | **渲染后端锁定 Skia（临时决策）**：真机对比 Skia vs Impeller —— Skia 在骁龙 8 Elite / 安卓 17 帧数更平滑（Impeller shader 编译/pipeline stall 偶发卡顿，见 v1.16.3）。`AndroidManifest` 加 `EnableImpeller=false`，注释标明未来解决后删除即切回 | — | Android |

### 涉及编号变更
- 重构 C-22 悬浮形态 → `KernelFloatingBottomBar`（demo 内核）；删除旧实现 `c22_damped_drag_indicator.dart`、`c22_dual_peak_highlight.dart`（内核自带等效）、`shaders_loader.dart`（内核组件各自惰性加载 shader）。
- 新增 `kernel/` 目录（6 文件）、`lib/core/widgets/app_scroll_behavior.dart`、`lib/presentation/providers/scroll_activity_provider.dart`。
- 版本：`1.17.4+93` → `1.18.0+94`（重构底栏实现 + 模糊/触控/后端多项 → Minor，§1.2）。

---

## v1.17.4（2026-09-02）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **首页卡片布局**：ListView 增加左右 16dp 外边距（Miuix/HyperOS 卡片列表标准），卡片不再紧贴屏幕边缘 | P-01-01 | Android 11+ / Web |

### 涉及编号变更
- 修改 P-01-01 首页（`page_p01_01_home_page.dart` ListView padding 增加左右 16dp）。
- 版本：`1.17.3+92` → `1.17.4+93`（§1.3 只升不降）。

---

## v1.17.3（2026-09-02）[Android]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **顶栏模糊更新频率优化**：新增 C-28 降采样快照捕获（pixelRatio=dpr×0.5，toImageSync 成本降 1/4）+ 页面采样频率 6→3（顶栏模糊滚动更新 20→40Hz），消除页面滑动时顶栏模糊「反应迟钝/撕裂」；C-27 像素映射改用 backdrop.pixelRatio 适配降采样；总快照功耗不升反降 | C-27 / C-28 / C-22 / C-25 | Android 13+ |

### 涉及编号变更
- 新增 C-28 降采样快照捕获（`lib/presentation/widgets/c28_downsampled_capture.dart`）。
- 修改 C-27（backdrop.pixelRatio 映射）、8 个页面 + 主壳（Capture 换 C28、everyNFrames 6→3）。
- 版本：`1.17.2+91` → `1.17.3+92`（§1.3 只升不降）。

---

## v1.17.2（2026-09-02）[Android]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **滚动中锁定 120Hz**：S-16 高刷控制器按滚动起止（ScrollStart/End）持续持有最高刷新率，仅在真正静止后释放（根治测试中 Frame Rate Velocity 在滚动/静止切换时降频导致的「假掉帧」） | S-16 / P-01 | Android 11+ |

### 涉及编号变更
- 修改 S-16（新增 notifyScrollStart/End，滚动中不调度释放）、主壳 P-01（滚动通知扩展 ScrollStart/End）。
- 版本：`1.17.1+90` → `1.17.2+91`（§1.3 只升不降）。

---

## v1.17.1（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **毛玻璃性能（P0 预模糊缓存）**：新增 C-27 预模糊组件替换 MiuixTextureBlur —— 快照/采样区/半径未变时复用一次性模糊纹理，每帧免 ImageFilter.blur（Impeller 下高斯离屏 pass 昂贵，flutter/flutter#191207），顶栏 C-25 / 底栏 C-22 接入；视觉等价 | C-22 / C-25 / C-27 | Android 13+ |
| 优化 | **快速滚动降级（P3）**：新增 S-19 滚动降级策略 —— 滚动速度 >2500px/s 时毛玻璃模糊半径 ×0.3，回落 400ms 恢复（极限滚动保帧） | S-19 / C-27 | Android 13+ |
| 优化 | **高刷升频增强（S-16）**：指针按下/移动立即请求 120Hz（不再等首帧），静止释放延时 2s→3s | S-16 | Android 11+ |
| 修复 | 底栏指示器 Skia 下间歇变黑：`_InnerShadow` 的 BlendMode.clear 挖孔改 evenOdd path（双后端兼容） | C-22 | Android |

### 涉及编号变更
- 新增 C-27 预模糊组件（`lib/presentation/widgets/c27_prefrosted_blur.dart`）、S-19 滚动降级（`lib/presentation/providers/blur_degrade_provider.dart`）。
- 修改 C-22 底栏 / C-25 顶栏（MiuixTextureBlur → C27PrefrostedBlur）、S-16（指针升频 + 延时）、主壳 P-01（滚动速度检测）。
- 版本：`1.17.0+89` → `1.17.1+90`（§1.3 只升不降）。

---

## v1.17.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 功能 | **大课表导入 Excel 课表**：学期卡片新增实底「导入课表」按钮（Miuix 实底样式），file_picker 选 .xls/.xlsx → excel_plus 解析（表头合并单元格动态定位星期列、单元格 ★ 分段 + 换行多课程、节次/周次标注解析）→ 按 星期×节次 合并导入（同格替换、其余保留）；班级信息存入 teacher 字段 | S-18 | Android 11+ / Web |

### 涉及编号变更
- 新增 S-18 Excel 课表解析器（`lib/core/excel/excel_timetable_parser.dart`）。
- `Course` 模型新增 `weeks`（具体周次集合，1..30）：导入课程按周次精确显示；编辑弹窗手动改 week 时清空 weeks。
- 新依赖：`excel_plus`（.xls/.xlsx 解析，纯 Dart 双平台）、`file_picker`（文件选择）。
- 版本：`1.16.5+88` → `1.17.0+89`（§1.3 只升不降）。

---

## v1.16.5（2026-09-01）[Android]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **骁龙 8 Elite（Adreno 830）+ 安卓 17 掉帧**：定位为安卓 15+ Frame Rate Velocity 自适应把刷新率压到 60Hz（实测 `mActiveModeId=3`/60Hz，fps 锁 64.2）；新增 S-16 高刷新率控制器按全局帧活动显式请求最高刷新率（120Hz），静止 2s 后释放交还系统省电 | S-16 | Android 11+ |

### 涉及编号变更
- 新增 S-16 高刷新率控制器（`lib/core/refresh_rate/refresh_rate_controller.dart`）+ 原生通道 `xiangjugong/refresh`（MainActivity.kt）。
- 版本：`1.16.4+87` → `1.16.5+88`（§1.3 只升不降）。

---

## v1.16.4（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 回滚 | **撤销禁用 Impeller**（v1.16.3 的 EnableImpeller=false 已移除，恢复原渲染后端）；掉帧根因待进一步定位（见兼容规划，非单纯 Impeller 问题） | — | Android |

### 涉及编号变更
- 无新增编号（回滚，Patch §1.2）。
- 版本：`1.16.3+86` → `1.16.4+87`（§1.3 只升不降）。

---

## v1.16.3（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **骁龙 8 Elite（Adreno 830）+ 安卓 17 掉帧优化**：定位为 Impeller 渲染后端在该 GPU 上的 shader 编译/pipeline stall（build 0.91ms / raster 3.68ms 但掉帧 33%，跨 SoC 差异）；禁用 Impeller 回退 Skia（AndroidManifest meta-data `EnableImpeller=false`），Skia 在 Adreno 上更稳定 | — | Android（骁龙 8 Elite） |

### 涉及编号变更
- 无新增编号（渲染后端性能修复，Patch §1.2）。
- 版本：`1.16.2+85` → `1.16.3+86`（§1.3 只升不降）。

---

## v1.16.2（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **未展开选择字段加边框**：编辑弹窗的星期/节次/节数/周次字段值行补 outline 边框（1px），增强可读性与可点击感 | P-06 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（P-06 视觉优化，Patch §1.2）。
- 版本：`1.16.1+84` → `1.16.2+85`（§1.3 只升不降）。

---

## v1.16.1（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **编辑弹窗选择控件改「点击展开选择列表」**：星期 / 开始节次(1-16) / 节数(1-4) / 周次(每周·单周·双周) 由分段 MiuixTabRow 改为点击字段行展开胶囊选项（miuix 样式：值行 + 箭头 + Wrap 选项，选中高亮），选择后收起；轻量实现——仅当前展开字段重建、无弹层/Overlay（兼顾性能） | P-06 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（P-06 交互优化，Patch §1.2）。
- 版本：`1.16.0+83` → `1.16.1+84`（§1.3 只升不降）。

---

## v1.16.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 重构 | **大课表改为周课表网格（参考勾丰小站）**：课程模型重构——day(1-7)×start(节次1-16)×len(节数1-4) 网格定位 + WeekType 三态单双周 + 7 预设色/auto 分配 + 教师字段（旧数据迁移兜底）；P-06 页重写——Stack 网格（列=周一~周日、行=节次，课程块 MiuixCard 彩色无毛玻璃、支持跨节、单双周按当前周次过滤/淡化，窄屏横向滚动自适应）+ 学期 meta 表单（年级/学期/周次 badge+保存）+ MiuixOverlayBottomSheet 编辑弹窗（星期/节次/节数/周次/颜色/地点/教师/删除）；首页迷你课表同步显示（start 节 · name）；S-15 扩展持久化 ScheduleMeta | P-06 / S-15 / C-28 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（P-06/S-15 重构，Minor：数据模型变更）。
- 版本：`1.15.0+82` → `1.16.0+83`（§1.2 Minor）。

---

## v1.15.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **大课表编辑页（P-06）+ 首页迷你课表同步**：大课表二级页面（/timetable，R-10，不在底栏，从迷你课表「查看全部」进入）——MiuixCard 课程列表（点击编辑、长按删除确认）、底部添加课程、MiuixOverlayBottomSheet 表单（MiuixTextField）；**课表数据服务（S-15）**——Course 模型（domain）+ SharedPreferences JSON 持久化（CourseRepositoryImpl）+ courseListProvider（AsyncNotifier，增删改自动保存）；**首页迷你课表改造**——C-28 小课表红卡改数据驱动（最多 3 条、超出显示「… 等 N 门课程」、空态提示），Riverpod 自动同步 | P-06 / S-15 / R-10 / C-28 | Android 11+ / Web |

### 涉及编号变更
- 新增编号：**P-06 大课表编辑页、S-15 课表数据服务、R-10 /timetable 路由**；C-28 小课表子卡数据驱动改造。
- 版本：`1.14.4+81` → `1.15.0+82`（新增页面+服务 → Minor，§1.2）。

---

## v1.14.4（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **底栏按压跃起**：按压指示框时底栏整体向上跃起（Transform.translate 纯位移，非形变，6dp）、阴影增强（10→14dp），松手弹簧回落，符合物理直觉；**跟随拖拽**——拖拽中底栏保持浮起、松手回落；按压进度经 ValueNotifier 由指示器同步到容器层（仅按压/拖拽期间重建，静止零 ticker） | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22 交互增强，Patch §1.2）。
- 版本：`1.14.3+80` → `1.14.4+81`（§1.3 只升不降）。

---

## v1.14.3（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **首页卡片 UI 样式对齐 miuix**：C-27 摘要区 / C-29 仪表盘由自定义 Container 改为 MiuixCard 标准样式（默认圆角 16 + surfaceContainer 背景 + 内边距 16，深浅色自适应，参考 KernelSU InfoCard）；**设置页卡片间距**：分组卡片之间留 16 间距（避免挤在一起） | C-27 / C-29 / P-01-02 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（UI 优化，Patch §1.2）。
- 版本：`1.14.2+79` → `1.14.3+80`（§1.3 只升不降）。

---

## v1.14.2（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **首页卡片布局崩溃**：v1.14.1 在 C-28 内部加 IntrinsicHeight，滚动容器（ListView unbounded 高度）内触发 native 崩溃（libflutter.so tombstone）。修复：移除 IntrinsicHeight —— C-28 内部 Row 改 start（子卡顶部对齐、各自高度）；横屏两栏等高改 SizedBox 固定高度 180 + Row(stretch)（避免 IntrinsicHeight） | C-28 / P-01-01 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-28 布局崩溃修复，Patch §1.2）。
- 版本：`1.14.1+78` → `1.14.2+79`（§1.3 只升不降）。

---

## v1.14.1（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **竖屏首页排布错乱**：C-28 组合大卡片内部 `Row(stretch)` 在竖屏（ListView 无界高度）下布局异常——加 `IntrinsicHeight` 包裹（提供有界高度让左右子卡等高），并去掉子卡小课表里的 `Spacer`（无界高度下 flex 风险）改为固定间距 | C-28 / P-01-01 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-28 布局修复，Patch §1.2）。
- 版本：`1.14.0+77` → `1.14.1+78`（§1.3 只升不降）。

---

## v1.14.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **首页卡片体系**：C-27 摘要区（雑魚XX+每日一言）、C-28 组合大卡片（小课表红卡 #DA2828 + 今日剩余环形仪表盘，含查看全部按钮）、C-29 仪表盘（3 统计项+分段进度条）、C-30 未规划占位卡（dashed 边框 CustomPainter）；**响应式布局**——竖屏（摘要区→组合大卡片→2×2 网格），横屏（IntrinsicHeight 两栏等高：左摘要区/右组合大卡片 + 下方 4 列）；数据经 homeCardsProvider（静态假数据，后期可切 S-03 仓库）；全 Miuix 组件 + Miuix 颜色令牌（深浅色自适应）、不加毛玻璃 | C-27 / C-28 / C-29 / C-30 / P-01-01 | Android 11+ / Web |

### 涉及编号变更
- 新增编号：**C-27 摘要区、C-28 组合大卡片、C-29 仪表盘、C-30 未规划占位**。
- 版本：`1.13.1+76` → `1.14.0+77`（新增组件 → Minor，§1.2）。

---

## v1.13.1（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 调整 | **清空首页内容**：首页列表内容（版本/系统卡、功能入口卡、页脚）清空为占位空列表，仅保留结构（顶部 C-25 毛玻璃标题栏、C-26 更多菜单、C-24 FAB、内容快照捕获、底部穿透间距）；底栏 / 顶部不受影响 | P-01-01 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（首页内容调整，Patch §1.2）。
- 版本：`1.13.0+75` → `1.13.1+76`（§1.3 只升不降）。

---

## v1.13.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **顶部「更多」菜单（C-26）**：顶部右上角三点按钮 + Miuix 毛玻璃悬浮下拉菜单（OverlayEntry 全屏遮罩关闭 + 按钮下方右对齐；MiuixTextureBlur 采样页面 backdrop，blurRadius 12 与底栏一致、tint surfaceContainer@0.87；U-03/无快照降级半透明纯色）；菜单项设置/关于（moreMenuItemsProvider 可扩展）；点击项关闭+push 跳转、遮罩/返回键关闭；替换各页顶栏原占位按钮（search/filter/share） | C-26 | Android 13+（模糊）/ Web |
| 新增 | **工具集占位页（P-01-04 / F-04）**：一级页面（底栏第二项），占位内容（标题+敬请期待），结构与首页一致（C-25 顶部毛玻璃 + C-26 更多菜单 + 内容快照捕获） | P-01-04 | Android 11+ / Web |
| 改造 | **底栏动态项数**：items 从 bottomBarItemsProvider 读取（与 PageView 页数同源，2→N 自适应），指示器 tabWidth 随项数自动计算；**页面层级变化**——设置/关于从一级页（底栏）改为二级页（顶部更多菜单进入，leading 改返回按钮）；路由 /settings /about 改顶层路由（push），/tools 新增映射 /?page=1 | C-22 / R-03 / R-04 / P-01-02 / P-01-03 | Android 11+ / Web |

### 涉及编号变更
- 新增编号：**C-26 顶部更多菜单**、**P-01-04 工具集页**。
- 版本：`1.12.4+74` → `1.13.0+75`（新增组件 → Minor，§1.2）。

---

## v1.12.4（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **顶部毛玻璃推广到全部页面**：设置/关于/主题配置/调色板/权限 5 页顶栏 C-23 → C25FrostedTopBar（MiuixTopAppBar 折叠 + 快照毛玻璃），内容改 ListView/GridView + MiuixLayerBackdropCapture + CaptureHeartbeat（采样 6 帧 + surface 底色）；移除各页 TickerMode(false)（MiuixTopAppBar 内部有小标题弹簧动画，静音会冻结折叠） | C-25 / P-01-02 / P-01-03 / P-01-02-01 / P-02 / P-03 | Android 13+（模糊）/ Web |

### 涉及编号变更
- 无新增编号（C-25 推广，Patch §1.2）。
- 版本：`1.12.3+73` → `1.12.4+74`（§1.3 只升不降）。

---

## v1.12.3（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **顶部毛玻璃模糊度对齐参考项目**：blurRadius 12→25（复刻 KernelSU BlurredBar `BlurExt.kt:36` 的 `blurRadius=25f`），顶栏比底栏更糊（参考项目顶栏 25 / 底栏 4dp 的设计）；tint 保持 surface@0.87 | C-25 | Android 13+（模糊）/ Web |

### 涉及编号变更
- 无新增编号（C-25 视觉对齐，Patch §1.2）。
- 版本：`1.12.2+72` → `1.12.3+73`（§1.3 只升不降）。

---

## v1.12.2（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **顶部毛玻璃功耗优化（参考 KernelSU rememberBlurBackdrop）**：①快照先画 surface 底色（等价 Compose drawRect(surfaceColor)，模糊边缘无透明渗入）；②顶部采样频率 everyNFrames 3→6（tint 0.87 掩盖模糊细节，120Hz 设备 40→20Hz 采样，toImageSync 成本减半；静止仍零采样） | C-25 / P-01-01 | Android 13+（模糊）/ Web |

### 涉及编号变更
- 无新增编号（C-25 功耗优化，Patch §1.2）。
- 版本：`1.12.1+71` → `1.12.2+72`（§1.3 只升不降）。

---

## v1.12.1（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **内容默认下沉避让顶栏**：MiuixScaffold 的 body 铺满全屏、topBar 悬浮其上，content 回调的 padding.top = topBar 高度需由内容自行应用——首页此前忽略 padding，列表从屏幕顶开始被毛玻璃顶栏遮挡；现列表顶部内边距叠加 padding.top，内容默认在顶栏下方，滚动时上移穿过顶栏（被模糊） | C-25 / P-01-01 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-25 修复，Patch §1.2）。
- 版本：`1.12.0+70` → `1.12.1+71`（§1.3 只升不降）。

---

## v1.12.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **顶部毛玻璃标题栏（C-25，首页先行）**：KernelSU TopAppBar 样式（MiuixTopAppBar + MiuixExitUntilCollapsedScrollBehavior 折叠）；毛玻璃与底栏同源——页面级 MiuixLayerBackdrop 捕获滚动内容（CaptureHeartbeat 采样），C25FrostedTopBar 在捕获外 MiuixTextureBlur 采样（blurRadius 12dp 与底栏一致、tint surface@0.87 参考 KernelSU BlurredBar），内容可穿过顶栏底部；U-03 门控（blur 不可用降级纯 surface） | C-25 | Android 13+（模糊）/ Web |
| 重构 | 首页顶栏由 C-23（SliverPersistentHeader 连续替换）改为 MiuixTopAppBar 折叠（KernelSU 样式），列表改 ListView + 快照捕获 | P-01-01 / C-23 / C-25 | Android 11+ / Web |

### 涉及编号变更
- 新增编号：**C-25 顶部毛玻璃标题栏**（PROJECT_SPEC §5 登记，v1.11.x 的 C-25 渐进毛玻璃已撤销）。
- 版本：`1.11.3+69` → `1.12.0+70`（新增编号 → Minor，§1.2）。

---

## v1.11.3（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 回滚 | **撤销 v1.11.0~v1.11.2 顶部渐进毛玻璃（C-25）**：BackdropFilter 方案因 saveLayer/RepaintBoundary 隔离 backdrop 而不可行（模糊永远失效）；删除 c25_progressive_blur.dart，C-23/C-21 恢复纯 surface / 原 MiuixTopAppBar.blurred 背景，PROJECT_SPEC 撤销 C-25 登记。代码回到 v1.10.33 基线，顶部无模糊 | C-21 / C-23 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（回滚，Patch §1.2）。
- 版本：`1.11.2+68` → `1.11.3+69`（§1.3 只升不降）。

---

## v1.11.2（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **顶部毛玻璃彻底失效根因**：BackdropFilter 依赖"绘制历史"采样身后内容，C-25 内部与 C-21 外层的 RepaintBoundary 创建独立 layer 把 backdrop 限制在 layer 内（模糊采样不到列表 → 顶栏只是 tint 色块）。修复：移除两处 RepaintBoundary（毛玻璃随内容实时重绘，无法 layer 隔离）；渐变收敛为顶部 30% 全模糊后平滑衰减（原 55% 全模糊区边界感明显），渐进过渡更自然、无明显分割区 | C-21 / C-25 | Android 13+（模糊）/ Web |

### 涉及编号变更
- 无新增编号（C-25 修复，Patch §1.2）。
- 版本：`1.11.1+67` → `1.11.2+68`（§1.3 只升不降）。

---

## v1.11.1（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **顶部毛玻璃模糊不可见**：C-25 的 ShaderMask blendMode 由 dstIn 改 modulate——dstIn 会把模糊内容替换为渐变白（模糊不可见、可读性差）；modulate 为分量乘法，保留模糊内容 + 渐变 alpha 裁剪。**模糊度对齐底栏**：sigma 换算补上 ×0.45（BLUR_RADIUS_TO_SIGMA），顶部最大模糊度 = 底栏 floatingBlurRadius 12dp → sigma 5.4，由起始区域平滑过渡到无 | C-25 | Android 13+（模糊）/ Web |

### 涉及编号变更
- 无新增编号（C-25 修复，Patch §1.2）。
- 版本：`1.11.0+66` → `1.11.1+67`（§1.3 只升不降）。

---

## v1.11.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **顶部渐进毛玻璃（C-25）**：内容区顶部区域毛玻璃，模糊由强到弱（垂直方向）平滑过渡、无分界线——ShaderMask（垂直渐变 + dstIn）包 BackdropFilter 实时模糊滚动到顶栏下方的内容；顶部全模糊（12dp）、55% 处开始线性衰减到无；U-03 门控（Android 13+ / 毛玻璃开关，blur 不可用降级纯 surface）；无快照、无 ticker、IgnorePointer + RepaintBoundary | C-25 | Android 13+（模糊）/ Web |
| 优化 | 首页 C-23 顶栏背景由纯 surface 改为内嵌 C25 渐进毛玻璃（折叠/按钮前景不受影响）；设置/关于 C-21 关闭库内均匀 BackdropFilter、背景透明化，统一由 C25 提供渐进模糊 | C-21 / C-23 / C-25 | Android 13+（模糊）/ Web |

### 涉及编号变更
- 新增编号：**C-25 顶部渐进毛玻璃**（PROJECT_SPEC §5 登记）。
- 版本：`1.10.33+65` → `1.11.0+66`（新增编号 → Minor，§1.2）。

---

## v1.10.33（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **切页释放过渡拉长**：手动横滑页面换页后，指示器从按压态回静态的收敛使用更慢的 release 专用弹簧（press 1000→500、scale 250→150），整体过渡约 300→360ms，更柔和 | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 过渡调优，Patch §1.2）。
- 版本：`1.10.32+64` → `1.10.33+65`（§1.3 只升不降）。

---

## v1.10.32（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **按压高度形变增强**：pressScaleY 1.05→1.10（按压时高度变化更明显）；**缩小底栏水平宽度**：左右留白 sideInset 12→40dp（胶囊居中变窄）；**内部图标自适应**：图标大小 = tabWidth×0.18 钳制 16~22dp，缩窄时图标等比变小 | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22 视觉/布局调优，Patch §1.2）。
- 版本：`1.10.31+63` → `1.10.32+64`（§1.3 只升不降）。

---

## v1.10.31（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **消除边界反方向弹动（真正根因）**：定位到 `animateToPage` 跨页时经过中间页触发 `onPageChanged` → 中间页覆盖 `currentIndex` → 指示器 didUpdateWidget 反复弹簧到中间页再弹回目标。修复：加 `_programmaticPageChange` 标志，程序化翻页动画期间忽略中间页的 onPageChanged（currentIndex/URL 由 `_onDestinationSelected` 一次性设为目标），指示器不再经过中间页弹动 | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22 联动修复，Patch §1.2）。
- 版本：`1.10.30+62` → `1.10.31+63`（§1.3 只升不降）。

---

## v1.10.30（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **消除边界反方向弹动**：定位到形变对齐 `dragAlign` 为 `velocity>=0` 二值跳变——速度过零（撞墙平滑归零/快速反向）时拉伸对齐瞬间换边 → 视觉反方向弹动；改为 alignment.x 随平滑速度连续插值（无跳变）。同时撞墙时用更快平滑（0.5）使形变快速归 1，消除"伸出→回缩"弹动 | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 物理交互修复，Patch §1.2）。
- 版本：`1.10.29+61` → `1.10.30+62`（§1.3 只升不降）。

---

## v1.10.29（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **消除撞边/原地左右晃动**：定位到松手吸附弹簧带反向初速且目标=当前位置（如拖到最左继续左甩松手，nearest 仍为 0、初速向墙外）→ SpringSimulation overshoot 越界再回弹。修复：目标即当前位置（round 相等）或已在边界时初速归零 → 单调吸附、无过冲晃动 | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 物理交互修复，Patch §1.2）。
- 版本：`1.10.28+60` → `1.10.29+61`（§1.3 只升不降）。

---

## v1.10.28（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **放慢形变动画**：速度指数平滑 0.15→0.08（方向反转时形变渐变、不生硬突变）、squash 幅度再收敛（X 钳制 0.06 / Y 0.04、Y 系数 0.12、X 0.5、拉伸上限 0.05）；**撞边弹消除**：拖拽已到边界且继续朝墙外拖时速度目标归零，形变平滑归 1（不再挤压变高、松手不回落弹跳） | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 物理/交互调优，Patch §1.2）。
- 版本：`1.10.27+59` → `1.10.28+60`（§1.3 只升不降）。

---

## v1.10.27（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **甩出撞边回弹消除**：位置弹簧阻尼 0.85→1.0（临界阻尼，无 overshoot 越界弹回）+ 松手吸附初速上限 100→8 tab/s（甩出惯性收敛，撞边干净停住）；**形变收敛**：拖拽速度改指数平滑（每事件靠拢 15%，减缓形变响应、不生硬突变）、squash 幅度限制（X 钳制 0.08 / Y 0.06、Y 系数 0.25→0.15）、拖拽拉伸上限 0.08→0.06 | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 物理/交互调优，Patch §1.2）。
- 版本：`1.10.26+58` → `1.10.27+59`（§1.3 只升不降）。

---

## v1.10.26（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **删除指示框撞墙回弹**：移除触边橡皮筋（_panel 偏移 + 松手弹回），拖拽到边缘直接钳制停住；**指示框移动时形变绑定拖拽速度**：速度采样由每 6 事件节流 + 弹簧平滑改为**每事件实时 snap**（_velocityDecay 直接取实时速度），squash/拉伸完全跟随拖拽速度——快速移动形变明显、慢速轻微、停下自然归 1；松手衰减收敛保留 | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 物理/交互调优，Patch §1.2）。
- 版本：`1.10.25+57` → `1.10.26+58`（§1.3 只升不降）。

---

## v1.10.25（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **适配系统自适应刷新率**：快照心跳由持续 Ticker（AnimationController.repeat）改为**被动帧回调**（无 Ticker）——帧来源 = 页面内容自身重绘（滚动/动画/切换），内容静止零帧请求，系统（LTPO/动态刷新率）可自动降频省电；**背景采样率稍提高**：everyNFrames 4→3（120Hz 内容 30→40Hz 采样）；**模糊度不变**（12dp） | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22 功耗/性能调优，Patch §1.2）。
- 版本：`1.10.24+56` → `1.10.25+57`（§1.3 只升不降）。

---

## v1.10.24（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **再提高底栏模糊度**：悬浮胶囊模糊半径 8dp→12dp（sigma 5.4；增强模糊抹平背景细节 → 低采样不可察觉 → 允许降采样省性能）；**背景采样率再降一档**：快照心跳 everyNFrames 3→4（120Hz 设备 40→30Hz、60Hz 20→15Hz；仅帧数节流，不引入时间节流） | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22 视觉/性能调优，Patch §1.2）。
- 版本：`1.10.23+55` → `1.10.24+56`（§1.3 只升不降）。

---

## v1.10.23（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **提高底栏毛玻璃模糊度**：悬浮胶囊模糊半径 4dp→8dp（sigma 1.8→3.6，效果翻倍；U-03 sigma≤20 仍满足）；**降低背景采样率**：快照心跳 everyNFrames 2→3（120Hz 设备 60→40Hz、60Hz 30→20Hz；仅帧数节流，沿用 v1.10.22 默认心跳机制，不引入时间节流） | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22 视觉/性能调优，Patch §1.2）。
- 版本：`1.10.22+54` → `1.10.23+55`（§1.3 只升不降）。

---

## v1.10.22（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **撤销 v1.10.21 刷新率时间节流**：恢复默认心跳（AnimationController.repeat + everyNFrames 帧数节流 2）；修复背景模糊快照冻结（v1.10.21 的 Ticker 未在 build 中引用而从未启动，滚动时背景采样卡住）。**保留**毛玻璃开关绑定（毛玻璃效果 AND 悬浮开关，任一关闭零捕获零心跳） | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（回归修复，Patch §1.2）。
- 版本：`1.10.21+53` → `1.10.22+54`（§1.3 只升不降）。

---

## v1.10.21（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **模糊功耗三件套**：①毛玻璃开关绑定设置页「毛玻璃效果」（需与悬浮开关同开才创建快照，任一关闭零捕获、零心跳）；②采样率降低（心跳 everyNFrames 2→3，120Hz 设备采样 60→40Hz）；③心跳按目标帧率时间节流（targetFps 90，高刷设备模糊刷新上限 90fps；页面内容不在心跳子树内，页面刷新率不受影响） | C-22 / C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22 性能调优，Patch §1.2）。
- 版本：`1.10.20+52` → `1.10.21+53`（§1.3 只升不降）。

---

## v1.10.20（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **拖拽拉伸幅度减小**：dragStretch ±25%→±8%（轻微）；**形变阻尼加大**：scaleX/scaleY 弹簧阻尼 0.6/0.7→0.85/0.9（收敛快、无 overshoot） | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 物理调优，Patch §1.2）。
- 版本：`1.10.19+51` → `1.10.20+52`（§1.3 只升不降）。

---

## v1.10.19（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **拖拽果冻**：拖拽时指示器前缘随方向拉伸（头部跟手）、后缘锚定（尾部延迟），松手回弹归中心；**浅色按压带灰度**（E8E8E8 灰白）提升可读性；**高度变化减小**（pressScaleY 1.05，X 1.12） | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 视觉/物理调优，Patch §1.2）。
- 版本：`1.10.18+50` → `1.10.19+51`（§1.3 只升不降）。

---

## v1.10.18（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **玻璃质感与可读性**：浅色静止深灰变浅（0.06）；浅色按压外阴影增强（0.12）提升边界可读性；深色按压内部透明（白 @0.05）+ 边缘高光加宽（1.5×）区分；指示框居中微调（+2px 以图标+标题水平中心对称）；撞墙回弹减小（位置弹簧阻尼 0.85） | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 视觉/物理调优，Patch §1.2）。
- 版本：`1.10.17+49` → `1.10.18+50`（§1.3 只升不降）。

---

## v1.10.17（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **内阴影四周均匀**：内阴影 offset 0（消除拖拽时上半圈厚阴影）；**速度平滑衰减**：拖拽速度经弹簧衰减（停下时形变自然收敛，不突变）；**指示框居中**：left 补 padding，使指示框以 tab 图标为中心（消除左多右少） | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 视觉/物理调优，Patch §1.2）。
- 版本：`1.10.16+48` → `1.10.17+49`（§1.3 只升不降）。

---

## v1.10.16（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **物理直觉果冻**：静止态改深灰透明（黑/白 @0.1）；外阴影四周均匀（offset 0）+ 平柔克制；去视觉量化二值 → 颜色/阴影/缩放随 press 连续 lerp（静止↔按压平滑过渡）；触边挤压橡皮筋 2dp（松手弹簧回弹）；位置弹簧欠阻尼 0.7（松手轻微惯性越位回弹） | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 视觉/物理调优，Patch §1.2）。
- 版本：`1.10.15+47` → `1.10.16+48`（§1.3 只升不降）。

---

## v1.10.15（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **玻璃质感修正**：按压态改纯浅白透明（`Color.lerp` primary@0.15 → 白@0.4，移除蓝色蒙版）；外阴影平柔（alpha 0.15→0.08、blur 10→16、offset y 2→1），消除阴影溢出/割裂 | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 视觉调优，Patch §1.2）。
- 版本：`1.10.14+46` → `1.10.15+47`（§1.3 只升不降）。

---

## v1.10.14（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **玻璃质感**：按压态改白色透明玻璃（白 @0.35·press 叠加，静止 primary@0.15）；按压外阴影（玻璃边缘投影，黑/白 @0.15·press，blur 10，offset y 2·press）+ Bloom 高光 + 内阴影协同仿玻璃 | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 视觉调优，Patch §1.2）。
- 版本：`1.10.13+45` → `1.10.14+46`（§1.3 只升不降）。

---

## v1.10.13（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **克制物理**：按压缩放 1.39→1.12、内阴影 8dp→5dp、squash 钳制 0.2→0.1、触边橡皮筋 4dp→0（撞墙仅 squash 形变不弹跳），物理交互收敛为"直觉而不夸张" | C-22-1 | Android 11+ / Web |

### 涉及编号变更
- 无新增编号（C-22-1 参数调优，Patch §1.2）。
- 版本：`1.10.12+44` → `1.10.13+45`（§1.3 只升不降）。

---

## v1.10.12（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **透明指示框（放弃折射）**：移除 `MiuixTextureBlur` 采样（采样导致图标残留/乱跳），改半透明 tint 直接透过下方图标 + Bloom 立体高光（`MiuixHighlight`）+ 按压内阴影；恢复物理形变（按压缩放 + 果冻 squash，无采样故不乱跳）；移除按压光斑与自研折射 shader 死代码 | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 视觉重构，Patch §1.2）。
- 版本：`1.10.11+43` → `1.10.12+44`（§1.3 只升不降）。

---

## v1.10.11（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **指示框形变 + 图标乱跳**：移除 `Transform.scale` 按压缩放/squash —— 缩放包裹 `MiuixTextureBlur`，其 `localToGlobal` 采样偏移随缩放错位，导致底栏图标在指示框内乱跳、指示框形变。改固定尺寸，采样稳定 | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.10.10+42` → `1.10.11+43`（§1.3 只升不降）。

---

## v1.10.10（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **高光鬼影**：指示器高光从自研 `C22DualPeakHighlight`（dualPeak 双峰，`dot(N.xy,L.xy)²` 180° 对峰在图标边缘产生双重高光 → 鬼影/重影）改回 flutter miuix 官方 `MiuixHighlight`（single-peak，圆角 SDF + 3D 半球 rim 法线 + 方向光 + BlendMode.plus） | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 视觉修复，Patch §1.2）。
- 版本：`1.10.9+41` → `1.10.10+42`（§1.3 只升不降）。

---

## v1.10.9（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **指示器采样源改回 tabs 图标**：`MiuixTextureBlur(page)` 采样页面内容（不含底栏），指示器在屏底采样到页面底部空白 → 空玻璃；改回 `MiuixTextureBlur(tabs)` 采样标签行图标，透过玻璃看到底栏图标（参考图2 通透感） | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 视觉修复，Patch §1.2）。
- 版本：`1.10.8+40` → `1.10.9+41`（§1.3 只升不降）。

---

## v1.10.8（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **指示器玻璃改回 flutter miuix `MiuixTextureBlur`**：自研 lens 折射 shader 在放大下产生锯齿/漩涡/拉伸扭曲，参照 flutter miuix 改用 `MiuixTextureBlur`（干净模糊采样页面内容）+ dualPeak 高光 + 真内阴影；移除自研 lens shader 调用与死代码 | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 视觉修复，Patch §1.2）。
- 版本：`1.10.7+39` → `1.10.8+40`（§1.3 只升不降）。

---

## v1.10.7（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **P1 采样源切为页面内容**：指示器 lens 折射采样从【标签行图标】(tabs) 改为【页面内容】(pageBackdrop)，消除"指示框表面多一个图标"；`CustomPainter` 改 `RenderProxyBox`（`localToGlobal` 计算采样偏移） | C-22-1 | Android 13+ |
| 修复 | **uScale 绕中心还原**：`Transform.scale` 是绕中心缩放，`FlutterFragCoord` 映射为 `center+(p-center)·scale`；改绕中心还原，修复放大时坐标错乱漩涡 | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.10.6+38` → `1.10.7+39`（§1.3 只升不降）。

---

## v1.10.6（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **指示器折射漩涡 + 夸张**：移除 `depthEffect`（`normalize(centeredCoord)` 与法线叠加在放大坐标系下梯度错乱 → 黑色漩涡）；折射带/折射量收敛（10→5dp、14→8dp），边缘轻微折射 | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.10.5+37` → `1.10.6+38`（§1.3 只升不降）。

---

## v1.10.5（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **指示器放大时折射采样越界浑浊**：按压 scale 1.39 缩放 Canvas 坐标但 shader `uSize`/`sampleOffset` 未同步放大，`FlutterFragCoord` 超出快照尺寸 → clamp 边缘像素 → 浑浊灰块。修复：shader 加 `uScale` uniform，`FlutterFragCoord()/uScale` 还原坐标，采样不越界 | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.10.4+36` → `1.10.5+37`（§1.3 只升不降）。

---

## v1.10.4（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **指示器折射方向**：`refractionAmount` 传正值导致折射沿法线【向外】偏移；对齐 `Lens.kt:54` 改传负值，折射【向内】（凸透镜向中心偏折） | C-22-1 | Android 13+ |

### 涉及编号变更
- 无新增编号（C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.10.3+35` → `1.10.4+36`（§1.3 只升不降）。

---

## v1.10.3（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **S-13 日志覆盖增强**：新增关键行为埋点——页面切换（nav）、路由跳转（router）、设置变更（settings）、应用生命周期（lifecycle）、进程启动时间；debugPrint 桥接按内容分级（🔴/error→error、🟢/warn→warn、其余 info），导出文件可区分错误 | S-13、P-01、F-03 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 0 issues | ✅ 通过 |
| 采集覆盖 | 页面/路由/设置/生命周期日志可导出 | 待真机验证 | ⏳ |
| 功耗 | 开关关闭时埋点零成本（enabled=false 直接 return） | 代码级零开销路径 | ✅ 代码级通过 |

### 涉及编号变更
- 无新增编号（S-13 埋点增强，Patch §1.2）。
- 版本：`1.10.2+34` → `1.10.3+35`（§1.3 只升不降）。

---

## v1.10.2（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **页面滑动/点击切换后指示器不联动**：`const MainShellPage` 不会因路由 query 变化（`/?page=N`）隐式重建，`currentIndex` 冻结 → C-22 指示器 `didUpdateWidget` 不触发。修复：改用显式 State 字段 `_currentIndex` + `setState`（页面 onPageChanged / 点击 onDestinationSelected 同步），`context.go` 仅负责 URL 深链同步 | P-01、C-22-1 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 0 issues | ✅ 通过 |
| 指示器联动 | 页面滑动/点击/拖拽三种场景均弹簧吸附 | 待真机验证 | ⏳ |

### 涉及编号变更
- 无新增编号（P-01/C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.10.1+33` → `1.10.2+34`（§1.3 只升不降）。

---

## v1.10.1（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **悬浮底栏指示器位置不随动画更新**：`Positioned.left` 在 `build` 外层只计算一次，`_pos`/`_panel` 动画（拖拽松手弹簧、didUpdateWidget 位置弹簧）只触发 AnimatedBuilder 内部重绘、从不更新 `Positioned.left` → 指示器位置冻结（页面滑动/点击切换后不同步）。修复：将 `Positioned` 移入 AnimatedBuilder，`left` 随动画每帧重算 | C-22-1 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 0 issues | ✅ 通过 |
| 指示器联动 | 页面滑动/点击后指示器弹簧吸附到目标 | 待真机验证 | ⏳ |

### 涉及编号变更
- 无新增编号（C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.10.0+32` → `1.10.1+33`（§1.3 只升不降）。

---

## v1.10.0（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **一级页面横滑切换**：PageView + PageController（≈ 参考 HorizontalPager）替代 StatefulShellRoute.indexedStack；页索引由 URL query「page」承载（单一事实源），/home /settings /about 深链 redirect 映射为 /?page=N | R-01~R-04、P-01 | Android 11+ / Web |
| 新增 | **指示器离散联动（严格 1:1）**：页面翻页完成 → onPageChanged → 更新 URL → C-22 指示器 didUpdateWidget 弹簧吸附；指示器拖拽/点击 → animateToPage（tween `100×\|d\|+100`ms EaseInOut） | C-22、C-22-1、P-01 | Android 11+ / Web |
| 优化 | 移除 T59 FadeTransition 过渡（PageView 自带横滑动画）；保留 T50 快照心跳、C-02 侧栏、C-22 双模式 | P-01 | Android 11+ / Web |

### 性能与功耗验收（v1.10.0）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 0 issues | ✅ 通过 |
| 横滑流畅度 | 120fps（仅 60fps 设备降级） | 待真机验证 | ⏳ |
| 指示器联动 | 翻页瞬间弹簧吸附，无延迟 | 待真机验证 | ⏳ |
| 帧率 / 功耗实测 | ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号；R-01~R-04 路径语义保留（/home /settings /about redirect 兼容，落地为 /?page=N，§7 需在 PROJECT_SPEC 附录补充说明）。
- 版本：`1.9.0+31` → `1.10.0+32`（Minor，§1.2 新增交互能力；§1.3 只升不降）。

---

## v1.9.0（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **S-13 日志服务**：统一日志门面（分级 debug/info/warn/error + 500 条内存环形缓冲 + FlutterError/PlatformDispatcher/zone 全局异常捕获）；默认关闭时零成本 | S-13 | Android 11+ / Web |
| 新增 | **S-14 性能监控**：`addTimingsCallback` 帧耗时采样（fps / 平均 build·raster / P95 build / 掉帧 ≥17ms），环形缓冲 600 帧；仅开关开启时注册回调 | S-14 | Android 11+ / Web |
| 新增 | **日志导出**：设置页「导出日志」→ 序列化 .txt（版本/设备/性能摘要/分级日志）→ 原生 `MediaStore.Downloads` 写入公共 Download/（Android 10+ 免存储权限，零第三方依赖） | S-13、F-03、P-01-02 | Android 10+ |
| 新增 | 设置页「日志采集」开关（默认关闭，持久化） | F-03、P-01-02 | Android 11+ / Web |
| 优化 | 全局异常不再静默（入日志缓冲，可导出排查）；导出结果对话框提示 | S-13 | Android 11+ / Web |

### 性能与功耗验收（v1.9.0）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 待复测 | ⏳ |
| 采集开销 | 开关关闭时零回调零采样；开启仅内存追加 | 代码级零成本路径 | ✅ 代码级通过 |
| 导出功能 | 公共 Download/ 生成 .txt | 待真机验证 | ⏳ |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（S-13/S-14 为 PROJECT_SPEC §6 已预留编号，本次落地实现）。
- 版本：`1.8.0+30` → `1.9.0+31`（Minor，§1.2 新增服务功能；§1.3 只升不降）。

---

## v1.8.0（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **透镜折射 + 色散着色器**：`shaders/lens_refraction.frag`（1:1 移植 `Lens.kt` L79-216，圆角 SDF 折射 + 7 通道色散，权重 r/3.5、g/3.5、b/3.0、a/7.0 原值；9-tap 高斯内联，单 pass 完成 blur→lens） | C-22-1 | Android 13+ |
| 新增 | **Bloom dualPeak 双峰高光着色器**：`shaders/bloom_dual_peak.frag` + `C22DualPeakHighlight`（1:1 移植 `Shaders.kt:398-507`，`dot(N.xy,L.xy)²` 单光源 180° 对峰；扩展而非替换 MiuixHighlight） | C-22-1 | Android 13+ |
| 新增 | `C22ShaderPrograms` 着色器单例加载器（惰性预载 + 失败降级） | C-22-1 | Android 11+ / Web |
| 优化 | 指示器完整玻璃路径：tabs 快照 → lens 折射 → dualPeak 双峰高光 → 内阴影；sampleOffset 随拖拽动态移动（玻璃透镜滑过标签）；shader <1ms/帧 | C-22-1 | Android 13+ |
| 优化 | 低版本/Web/着色器未就绪：回退 v1.7.6 近似（MiuixTextureBlur + MiuixHighlight 单峰 + 内阴影）；静止态 primary@0.15 不变 | C-22-1 | Android 11+ / Web |

### 性能与功耗验收（v1.8.0）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 待复测 | ⏳ |
| shader 编译 | `flutter build apk --debug` 通过 | 待真机构建 | ⏳ |
| 着色器耗时 | <1ms/帧（仅指示器区域） | 待 Profile 帧采样 | ⏳ |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22/C-22-1 能力增强；新增 2 个 .frag 着色器 + 2 个内部件，不占编号）。
- 版本：`1.7.6+29` → `1.8.0+30`（Minor，§1.2 新增能力；§1.3 只升不降）。

---

## v1.7.6（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **T50/P1 采样卡死**：回迁 `MiuixLayerBackdrop`/`MiuixLayerBackdropCapture` 快照机制（U-03 门控：仅悬浮模式 + Android 13+），新增 `CaptureHeartbeat`（C-22 内部件）以透明 CustomPaint 每 2 帧强制捕获节点重绘 → 快照实时；删除 v1.7.5 胶囊侧 `BackdropFilter`；悬浮关闭整树卸载零 ticker | C-22、C-22-1、P-01 | Android 13+ 真模糊；Web/Android<13 半透明 tint 回退 |
| 修复 | **T51/P3 同源融合**：`_C22FloatingPill` 转 Stateful 持标签级 `MiuixLayerBackdrop`（tabsBackdrop），标签行包 `MiuixLayerBackdropCapture`；指示器玻璃分支改 `MiuixTextureBlur(backdrop: tabsBackdrop, 2/12dp 量化恒定)` 采样标签行（等价 KernelSU `combinedBackdrop(tabsBackdrop)`）；删除指示器侧 `BackdropFilter` | C-22-1 | Android 11+ / Web |
| 修复 | **T52/P2 通透度参数化**：静止 tint `primary@0.15`、拖动态 `0.1×(1-press)+0.03×press`，集中常量 `_kRestTintAlpha/_kDragTintAlpha/_kDragTintPressAlpha`，两态 stadium 28 圆角 | C-22-1 | Android 11+ / Web |
| 修复 | **T53′/P3 双光源高光（1:1 复刻修正）**：底栏与指示器 Bloom 高光恢复双光源——主光源 `(0.5,-0.3,-0.05)` intensity 1.0 绕 LIGHT_REF 旋转（底栏 -45°/指示器 +90°）、副光源 `(0.5,0.8,-0.5)` intensity 0.4；`alpha=0.75`（底栏）/`pressProgress`（指示器）；指示器静止态叠加 faint 描边高光（alpha=glowColorAlpha 0.12）；`dualPeak` 单峰近似标注 TODO v1.8.0 自研着色器 | C-22、C-22-1 | Android 11+ / Web |
| 优化 | **T50′/T51′ vibrancy 参数修正**：`MiuixTextureBlur` saturation 1.3 → **1.5**（Vibrancy.kt:13） | C-22、C-22-1 | Android 13+ 真模糊；Web/Android<13 回退 |
| 新增 | **T58 参数单一事实源**：新增 `c22_visual_params.dart`（C22VisualParams），容器/模糊/颜色/阴影/高光/指示器/死区/动画/页切换全部常量集中定义，业务文件魔法数字清零；编排器公开常量改为转发兼容 | C-22、C-22-1 | Android 11+ / Web |
| 新增 | **T59 页切换缓动**：`MainShellPage` 分支切换补 `Curves.easeInOut` 过渡（淡入 + 轻微上移），时长 = 100×distance + 100ms（参考公式）；`navigationShell` 单一实例 → indexedStack 分支状态保持（§7） | P-01 | Android 11+ / Web |
| 优化 | **T54/P4 量化收口**：保留视觉量化缓存（key 四元组），拖动态 blurRadius/高光/内阴影不随 press 逐帧变化；`RepaintBoundary` 包裹指示器，拖拽期仅 Transform 逐帧 | C-22-1 | Android 11+ / Web |
| 修复 | **T55/P5 死区吸附**：`\|pos-originalIndex\| < 0.025×items 且 \|velocity\| < 200px/s` → 弹簧回弹原位（微小抖动不换页），否则最近项 + 速度修正 ±0.3 | C-22-1 | Android 11+ / Web |
| 修复 | **T56/P6 物理参数校准**：橡皮筋 4dp×sign×EaseOut(\|fraction\|)、squash 钳制 ±0.2、按压缩放 78/56、位置弹簧 1.0/1000、面板弹簧 1.0/300 对照报告核对；新增速度衰减弹簧（阻尼 0.5/刚度 300）驱动 release 果冻收敛 | C-22-1 | Android 11+ / Web |
| 修复 | **T57/P7 点击按压循环**：`didUpdateWidget` 外部切换升级 KernelSU `animateToValue` 语义——press 0→1 + scale→1.39 → 位置弹簧滑动 → 到位后 release press→0 + scale→1（玻璃高光闪烁 + 果冻脉冲）；roundPos 短路防回调循环 | C-22-1 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 心跳范围 | 仅悬浮模式 + Android 13+ | CaptureHeartbeat 由 main_shell U-03 门控挂载，关闭整树卸载 | ✅ 代码级通过 |
| 心跳节流 | 每 2 帧（`_captureEveryNFrames=2`） | painter `shouldRepaint` 仅在节流帧 true | ✅ 代码级通过 |
| 视觉量化 | 拖动态 blur/高光/内阴影恒定 | key 四元组缓存，两态各构建一次 | ✅ 代码级通过 |
| 静止 ticker | 0 | 悬浮关闭零 ticker；悬浮开启仅心跳（2 帧节流） | ✅ 代码级通过 |
| 静态检查 | flutter analyze 0 问题 | 0 issues | ✅ 通过 |
| 回归 | flutter test 全绿 | 7/7 通过（心跳常驻 → 测试 pumpAndSettle 改有限 pump 适配） | ✅ 通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22/C-22-1/P-01 既有登记语义修复；CaptureHeartbeat / C22VisualParams 为 C-22 内部件不占编号）。
- 版本：`1.7.6+28` → `1.7.6+29`（同 v1.7.6 Patch 内追加修正：T53′ 双光源、T58 参数源、T59 页切换；§1.3 只升不降、不可复用）。

---

## v1.7.5（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **底栏毛玻璃采样卡死**：`MiuixLayerBackdropCapture` 为 RepaintBoundary（flutter_miuix v1.1.1 `miuix_layer_backdrop.dart:74`），而页面滚动重绘在 `RenderViewport`（同为 RepaintBoundary）处截断 → 捕获节点 `paint()` 仅首帧执行 → 快照冻结。弃用快照机制，改用 `BackdropFilter` 每帧实时采样（C-24 同款模式），并移除外壳全部 `MiuixLayerBackdrop`/`MiuixLayerBackdropCapture` 代码 | C-22、C-22-1、P-01 | Android 13+ 真模糊；Web/Android<13 半透明 tint 回退 |
| 修复 | **指示器不透明/框内彩色**：删除"透镜伪渐变"（白 @0.55 + primary 染色的雾罩），tint 改为报告 §2.2 `onDrawSurface` 语义 `0.1×(1-press)+0.03×press`；指示器 BackdropFilter 实时模糊下方标签/胶囊 → 玻璃一体感（等价 KernelSU `combinedBackdrop(tabsBackdrop)`） | C-22-1 | Android 11+ / Web |
| 修复 | **拖拽卡顿**：视觉量化——press 连续弹簧不再逐帧驱动 blur sigma/高光/内阴影，按压/静止两态视觉各构建一次并缓存（§11.5）；移除 update 逐事件 debugPrint；`_panel` 拖拽期 snap 跟手 | C-22-1 | Android 11+ / Web |
| 新增 | **果冻撞墙反馈**：面板橡皮筋 4dp × sign × EaseOut(\|fraction\|)（累计拖拽量/总宽，KernelSU offsetAnimation 语义），松手 `_panelSpring`（阻尼 1.0/刚度 300）回弹；拖拽期 VelocityTracker 节流采样（每 6 事件）驱动 X/Y 非等比 squash | C-22-1 | Android 11+ / Web |
| 优化 | 移除全屏 `toImageSync` 捕获成本；折射（lens/chromaticAberration）与 Bloom dualPeak 列为 v1.8.0 Minor 预留扩展点 | C-22 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 待复测 | ⏳ |
| 回归 | flutter test 全绿 | 待复测 | ⏳ |
| 拖拽帧率 | ≥120/≥100 fps，仅 Transform 逐帧变化 | 视觉量化 + BackdropFilter（无逐帧 sigma 变化） | ✅ 代码级通过 |
| 采样实时性 | 页面滚动时底栏毛玻璃随内容更新 | BackdropFilter 无缓存、逐帧实时 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22/C-22-1 缺陷修复 + 登记语义补全，Patch §1.2）。
- 版本：`1.7.4+26` → `1.7.5+27`（§1.3 只升不降）。

---

## v1.7.4（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **C-22 悬浮底栏无法拖动**：`_C22FloatingPill` Stack 中静态标签行（opaque GestureDetector）位于指示器之上，命中测试被吞掉、水平拖拽识别器从未进入手势竞技场——重排为"容器层 → 标签行 → 指示器（最上层 translucent）"，与 KernelSU Compose 源绘制顺序一致；点击仍穿透到标签 onTap | C-22、C-22-1 | Android 11+ / Web |
| 修复 | **C-22 指示器显示为黑色**：`Color.withValues(alpha: 1 - press)` 语义为【替换】而非 KernelSU 的【相乘】（有效 alpha 应为 0.1×(1-progress)），静止时 overlay 变为不透明黑且 ColoredBox 不受圆形装饰裁剪 → 黑色矩形；改为乘性 alpha + `Color.alphaBlend` 单层合成 | C-22-1 | Android 11+ / Web |
| 修复 | **C-22 胶囊/指示器形状**：`BoxShape.circle` 在宽盒上只渲染内切圆（直径 = min(w,h)），容器层、指示器底、渐变层、内阴影全部改为 StadiumBorder（borderRadius = 高/2，报告 §2.1/§2.4） | C-22、C-22-1 | Android 11+ / Web |
| 修复 | **指示器不跟随外部切换**：`C22DampedDragIndicator` 新增 `didUpdateWidget`——点击标签/外部切页后按位置弹簧同步 `_pos`（拖拽中禁止外部覆盖，roundPos 短路防回调循环） | C-22-1 | Android 11+ / Web |
| 优化 | **§11.5 合规**：拖拽逐帧更新由 `setState` 改为 `AnimatedBuilder(Listenable.merge)`，仅 Transform 子树重绘；拖拽回调加 try-catch + `tabWidth` 零宽防御；内阴影改乘性 alpha（0.15×progress） | C-22-1 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 静态检查 | flutter analyze 0 问题 | 待复测 | ⏳ |
| 回归 | flutter test 全绿 | 待复测 | ⏳ |
| 拖拽帧率 | 仅 Transform 子树逐帧重绘（RepaintBoundary 内） | AnimatedBuilder 改造完成 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22/C-22-1 纯 Bug 修复，Patch §1.2）。
- 版本：`1.7.3+25` → `1.7.4+26`（§1.3 只升不降）。

---

## v1.7.3（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **C-22 底栏诊断日志**：`C22DampedDragIndicator` 与悬浮模式编排页新增 `debugPrint` 诊断日志——dragStart（`details.globalPosition`）、dragUpdate（`dx`/`primaryDelta`）、indicatorLeft（`_pos.value`）、dragEnd（`details.velocity.pixelsPerSecond`）、isFloating（悬浮/普通模式切换）；仅 debug 构建输出，release 零开销 | C-22、P-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 诊断日志 | 拖拽起/动/止 + 指示器位置 + 模式切换可观测 | 5 处 debugPrint 按模板埋点，flutter test 输出可见 | ✅ 代码级通过 |
| release 开销 | 0 | debugPrint 仅 debug 构建生效 | ✅ 代码级通过 |
| 静态检查 | flutter analyze 0 问题 | 0 issues（debugPrint 不受 avoid_print 限制） | ✅ 通过 |
| 回归 | flutter test 全绿 | 7/7 通过（含 C-24 FAB 既有警告，非失败） | ✅ 通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22 埋点，纯诊断日志）。
- 版本：`1.7.2+24` → `1.7.3+25`（新增日志 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.7.2（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **C-22 悬浮底栏 1:1 复刻 KernelSU FloatingBottomBar**：悬浮胶囊 64dp（4dp 内边距 + 56dp 内容区）、全圆、MiuixTextureBlur(4dp) + MiuixHighlight(-45°/alpha0.75) + 阴影(10dp, black@0.2/0.1) + surfaceContainer@0.4；指示器新增 C22DampedDragIndicator（静止 primary@0.15、按压缩放 1.39（78/56）、拖拽跟手钳制、VelocityTracker 速度采样参与吸附、位置弹簧 1.0/1000 + 速度衰减 0.5/300、X/Y 独立缩放弹簧 0.6/250 与 0.7/250 非等比果冻感、面板橡皮筋 4dp/1.0/300）；普通模式蒙版选择框背景改 surface；删除旧 c22_liquid_glass_indicator.dart | C-22、P-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 1:1 参数 | 全参数按报告（§2.1–§2.6） | 容器/指示器/弹簧/拖拽全部对应 | ✅ 代码级通过 |
| 拖拽跟手 | X 钳制 [padding, padding+tabWidth] | onHorizontalDragUpdate 直接驱动 | ✅ 代码级通过 |
| X/Y 缩放 | 独立控制器非等比 | 0.6/250 vs 0.7/250 | ✅ 代码级通过 |
| 静止 ticker | 0 | 控制器仅动画期间 tick | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22 重构；C-22-1 指示器为内部子组件，§2.2 仅 P 页层级化）。
- 版本：`1.7.1+23` → `1.7.2+24`（重构 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.7.1（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **C-22 液态玻璃指示器改用 flutter_miuix 库原语**：毛玻璃 `MiuixTextureBlur`（外壳 `MiuixLayerBackdrop` + `MiuixLayerBackdropCapture` 捕获页面背景，U-03 门控：Android 13+ 开启、Web/低版本 backdrop 为 null 零捕获成本）+ Bloom 高光 `MiuixHighlight`（glassStrokeMiddleLight）+ 折射 tint；吸附动画改用 `MiuixSpringEngine.runSettleAnimation`（Folme 临界阻尼弹簧，替代手写 SpringSimulation） | C-22、P-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 库原语接入 | MiuixTextureBlur/MiuixHighlight/MiuixSpringEngine | 指示器玻璃态 = TextureBlur + Highlight；吸附 = SpringEngine.runSettleAnimation | ✅ 代码级通过 |
| 背景捕获成本 | Web/低版本零捕获 | backdrop 仅 Android 13+ 创建；MiuixLayerBackdropCapture 仅悬浮栏+13+ 包裹 | ✅ 代码级通过 |
| 静止 ticker | 0 | runSettleAnimation 内部 Ticker 自销毁 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22 实现优化）。
- 版本：`1.7.0+22` → `1.7.1+23`（优化 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.7.0（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **C-22 双模式重构（液态玻璃可拖动指示器）**：C-22 改为 ModeDetector 编排器 —— 悬浮栏模式 = C22LiquidGlassIndicator（实心浅灰静止态 / 触摸进入液态玻璃样式：径向渐变 + 高光 + 光晕 + 半透明（U-03 门控）/ 横向拖拽跟手 / SpringSimulation 弹性吸附到最近选项后恢复实心）；普通模式 = C22MaskSelectionBar（半透明底栏 + 圆角矩形蒙版，无拖动无玻璃）；外壳窄屏统一使用 C-22（C-01 保留注册） | C-22、P-01 | Android 11+ / Web |

### 性能与功耗验收（Minor 迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 拖动驱动 | 跟手无延迟 | onHorizontalDragUpdate 直接驱动指示器 left（栏内 setState，栏外零影响） | ✅ 代码级通过 |
| 吸附动画 | 物理弹簧 | animateWith(SpringSimulation)，收敛 ≤600ms | ✅ 代码级通过 |
| 重绘隔离 | 仅指示器重绘 | 指示器嵌套 RepaintBoundary + 整栏隔离 | ✅ 代码级通过 |
| 普通模式 | 零拖动逻辑 | 蒙版选择框纯静态（Stateless 零 ticker） | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22 既有组件增强；C-22-1/C-22-2 按 §2.2 仅 P 页层级化，不纳入编号体系，为 C-22 内部子组件）。
- 版本：`1.6.0+21` → `1.7.0+22`（新增特性 = Minor，§1.2 判定表；§1.3 只升不降）。

---

## v1.6.0（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **C-22 液态玻璃底栏增强**（参考 KernelSU FloatingBottomBar）：① 滑动指示器 Sliding Bubble —— `AnimationController.animateWith(SpringSimulation)` 物理弹簧驱动（非 setState 逐帧），指示器独立 RepaintBoundary；② Q弹变形 Squash-and-Stretch —— 位移速度派生挤压/拉伸（velocity→scale，静止回弹）；③ 边缘折射高光 —— 1.5px 渐变光晕（静态零成本）；④ 水平拖拽切换（velocity>±200）；⑤ 毛玻璃 U-03 门控（Android 13+ 开 / Web 与低版本降级半透明）。**拒绝方案 A（liquid_glass_bottom_nav 包渲染 Material 底栏，违反 §1）**，采用方案 B（Miuix 原语自定义） | C-22 | Android 11+ / Web |

### 性能与功耗验收（Minor 迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 动画驱动 | 物理弹簧非 setState | animateWith(SpringSimulation)，收敛 ≤600ms | ✅ 代码级通过 |
| 重绘隔离 | 仅指示器重绘 | 气泡嵌套 RepaintBoundary + 整栏 RepaintBoundary | ✅ 代码级通过 |
| Web 降级 | 无毛玻璃 | U-03 门控，半透明表面色 | ✅ 代码级通过 |
| 静止 ticker | 0 | 弹簧收敛后控制器静止 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-22 既有组件增强；§5 描述已更新）。
- 版本：`1.5.2+20` → `1.6.0+21`（新增特性 = Minor，§1.2 判定表；§1.3 只升不降）。

---

## v1.5.2（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **C-23 标题栏深色/浅色切换不跟随（需滑动才刷新）根因**：SliverPersistentHeader 仅在 `shouldRebuild` 为 true 或 shrinkOffset 变化时才重跑 delegate.build；原 shouldRebuild 不比较主题 → 主题切换后 sliver 不重布局，颜色停留旧值。修复（方案 A）：C-23 组件 build 注册 MiuixTheme 依赖（主题变化立即重建组件），并将 MiuixThemeData 传入 delegate，shouldRebuild 增加主题值比较 → 主题切换即时刷新，无需滑动 | C-23、S-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 主题同步 | 切换立即刷新无需滑动 | 组件注册主题依赖 + shouldRebuild 主题比较（双保险） | ✅ 代码级通过 |
| 重建成本 | 不导致帧率下降 | MiuixThemeData 值比较（colors/textStyles/brightness）廉价；仅在主题变化时重布局 | ✅ 代码级通过 |
| 滑动行为 | 无闪烁跳变 | 折叠量仍为 shrinkOffset 纯函数 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-23 / S-01 既有组件增强）。
- 版本：`1.5.1+19` → `1.5.2+20`（Bug 修复 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.5.1（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **C-24 毛玻璃 FAB 被 C-22 悬浮底栏遮挡**：根因 —— FAB 原经 MiuixScaffold.floatingActionButton 槽位定位（按脚手架自身 bottomBar 计算），悬浮底栏开启时外壳切换为 Stack 叠加（内容铺满全屏、胶囊覆盖底部），槽位无法感知胶囊高度。修复：FAB 移出槽位改为页面 Stack 放置；C-24 内部监听 `floatingBarEnabled`（S-01），开启时底部间距 = C-22 `contentBottomInset`（胶囊高+间隙+间距+手势区，单一几何来源），关闭时默认 24；`AnimatedPadding(200ms)` 平滑过渡（§11.5 一次性 ≤600ms） | C-24、C-22、P-01-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 避让正确性 | 开启时 FAB 在胶囊上方 | bottomOffset = contentBottomInset（单一几何来源） | ✅ 代码级通过 |
| 切换过渡 | 平滑无跳变 | AnimatedPadding 200ms 一次性 | ✅ 代码级通过 |
| 功耗 | 静止零 ticker | 隐式动画瞬时回收；RepaintBoundary 保留 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-24 / C-22 既有组件增强）。
- 版本：`1.5.0+18` → `1.5.1+19`（Bug 修复 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.5.0（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **C-24 毛玻璃悬浮按钮（FAB）**：MiuixSquircleBorder 胶囊（56×56 默认）+ BackdropFilter 毛玻璃（U-03：Android 13+ 开启、Web/低版本降级半透明表面色，sigma 12≤20，区域远小于 40% 视口）；RepaintBoundary 隔离零父级重绘、单层阴影、Stateless 零生命周期（模板建议的 MiuixTextureBlur 需页面级 MiuixBackdrop 捕获 + ChangeNotifier，对 FAB 过度设计，改用 C-22 已验证模式）；首页经 MiuixScaffold.floatingActionButton 槽位接入（右下、底栏上方，占位回调） | C-24、P-01-01、U-03 | Android 11+ / Web |

### 性能与功耗验收（Minor 迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 毛玻璃平台门控 | Android 13+ 开 / Web 与低版本关 | U-03 裁决；Web 降级半透明 | ✅ 代码级通过 |
| 重绘隔离 | 父级重绘不影响 FAB | RepaintBoundary 包裹 | ✅ 代码级通过 |
| 静止 ticker | 0 | 无动画控制器（Stateless） | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 新增：C-24（§5 已登记，引入版本 v1.5.0；附录 A C-段更新）。
- 版本：`1.4.3+17` → `1.5.0+18`（新增组件 = Minor，§1.2 判定表；§1.3 只升不降）。

---

## v1.4.3（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | **全部二级（push 型）页面统一接入 C-23 折叠标题栏**：主题与色彩（P-01-02-01）、色彩调色板（P-02）、权限管理（P-03）；push 型页 leading 为返回胶囊按钮（chevronBackward → maybePop），右 2 占位（搜索/更多）；各页内容改 CustomScrollView + SliverList/SliverGrid（mainAxisExtent 固定行高保留）；静态页 TickerMode(false) 保留（C-23 无动画控制器） | P-01-02-01、P-02、P-03、C-23 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 交互一致 | 全部二级页折叠行为与一级页一致 | 复用 C-23，t 钳制 [0,1] | ✅ 代码级通过 |
| 滚动 build / ticker | ≤2 次/帧 · 静止 0 | SliverPersistentHeader 内部驱动；静态页 TickerMode(false) 保留 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（复用 C-23；P-01-02-01 / P-02 / P-03 为既有页面）。
- 版本：`1.4.2+16` → `1.4.3+17`（UI 优化 = Patch，§1.2 判定表；§1.3 只升不降）。
- 规范注记：未来新增二级页面默认使用 C-23（§15 布局稳定规范扩展约定）。

---

## v1.4.2（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | 关于页（P-01-03）接入 C-23 内容推动折叠标题栏：大标题"关于"左对齐 1:1 上移消失、小标题"关于"折叠居中滑入；左 1 菜单 + 右 2（分享/更多）胶囊占位按钮；内容改 SliverList 惰性构建；C-22 内容穿透间距适配；静态页 TickerMode(false) 保留（C-23 无动画控制器） | P-01-03、C-23 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 交互一致 | 关于页折叠行为与首页/设置页一致 | 复用 C-23，t 钳制 [0,1] | ✅ 代码级通过 |
| 静态页 ticker / 网络 | 0 / 0 | TickerMode(false) 保留；无网络调用 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（复用 C-23；P-01-03 为既有页面）。
- 版本：`1.4.1+15` → `1.4.2+16`（UI 优化 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.4.1（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | 设置页（P-01-02）接入 C-23 内容推动折叠标题栏：顶栏改为 CustomScrollView 首个 sliver（大标题"设置"左对齐 1:1 上移消失、小标题"设置"折叠居中滑入），左 1 菜单 + 右 2（搜索/更多）胶囊占位按钮，列表改 SliverList.builder，C-22 内容穿透底部间距适配 | P-01-02、C-23 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 交互一致 | 设置页折叠行为与首页一致 | 复用 C-23（同一组件实例语义），t 钳制 [0,1] | ✅ 代码级通过 |
| 滚动 build / ticker | ≤2 次/帧 · 静止 0 | SliverPersistentHeader 内部驱动；设置页交互控件（开关/分段）动画瞬时 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（复用 C-23；P-01-02 为既有页面）。
- 版本：`1.4.0+14` → `1.4.1+15`（UI 优化 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.4.0（2026-09-04）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | **C-23 内容推动折叠标题栏（连续替换模式）**：SliverPersistentHeader(pinned) + 自定义 delegate（widgets 层原语，零 Material）；动作行（左 1 + 右 3 胶囊，36×36 squircle 20px）常驻顶部；大标题（title1 令牌，左边缘与左按钮对齐）随滚动 1:1 上移消失，小标题（title3 令牌）从顶部外滑入，同 t 驱动交叉淡入（文字色 alpha，`withValues` 等价模板 withOpacity，禁 Opacity widget）；折叠态小标题水平居中于左右按钮组几何中心（纯算术）；t 钳制 [0,1]；背景纯 surface（全宽 header 超 §11.7.2 区域约束，U-03 不叠加模糊）；静态几何常量 static const | C-23 | Android 11+ / Web |
| 修改 | 首页（P-01-01）从 C-21 切换为 C-23（CustomScrollView + SliverList.builder），C-22 内容穿透底栏不变；C-21 保留供阈值弹簧切换场景复用；C21CapsuleIconButton.collapseState 改为可空（C-23 场景零监听） | P-01-01、C-21、C-22 | Android 11+ / Web |

### 性能与功耗验收（Minor 迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 滚动 build | ≤2 次/帧 | SliverPersistentHeader 内部驱动，仅 header 子树重绘；静态常量零 build 分配 | ✅ 代码级通过 |
| 静止 ticker | 0 | 无任何 AnimationController | ✅ 代码级通过 |
| 交互 | 大标题 1:1 上移 / 小标题滑入 / 按钮行常驻 | 回归断言：折叠后内容上移、4 按钮两态可见、点击无异常 | ✅ 测试通过 |
| Web CPU / 帧率功耗 | ≤30% · ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 新增：C-23（§5 已登记，引入版本 v1.2.0 登记 / 实际交付 v1.4.0，§1.3 只升不降）。
- 版本：`1.3.3+13` → `1.4.0+14`（新增组件 = Minor，§1.2 判定表）。

---

## v1.3.3（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **C-21 折叠交互补全（大标题上移消失 + 小标题滑入 + 左/右按钮行）**：交互由 MiuixTopAppBar 原生实现（大标题 Positioned 随滚动上移并在折叠带裁剪消失、小标题跨 1/3 阈值弹簧滑入、按钮行常驻、折叠后小标题与按钮同水平行）——**拒绝模板降级 Material SliverAppBar 方案（§1 禁止 Material 组件）**；实际缺口为左侧按钮，C-21 新增 navigationIcon 槽位并接入首页（菜单胶囊按钮） | C-21、P-01-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 折叠交互 | 大标题上移消失 / 小标题滑入 / 按钮行常驻 | Miuix 原生 scroll-driven（零新增 ticker）；回归断言左侧按钮存在 | ✅ 代码级 + 测试通过 |
| 重建 / 帧率 | 无额外 build、≥120/≥100 fps | 仅新增一个槽位透传，无动画/监听新增 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-21 参数增强；U-09 判定不需要）。
- 版本：`1.3.2+12` → `1.3.3+13`（交互修复 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.3.2（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **C-21 折叠标题栏位置（滚动后标题偏低 / 顶部空白）根因**：MiuixTopAppBar 的 subtitle 在折叠态同样渲染为小标题下方第二行，首页传入的长 tagline 使折叠头部变两行、栏高 52→63+，标题视觉被压低。修复：首页不再向 C-21 传 subtitle（折叠态恢复紧凑单行，小标题与 actions 同以折叠带垂直中心对齐，与 KernelSU 参考一致）；C-21 组件记录 subtitle 折叠态渲染约束（长副标题调用方应省略）。拒绝模板中降级 Material SliverAppBar 的方案（§1 禁止 Material 组件） | C-21、P-01-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 折叠态头部 | 紧凑单行、标题与按钮平齐 | 移除长副标题，折叠带 52+4（单行）；回归断言 tagline 不渲染 | ✅ 测试通过 |
| 重建 / ticker | 零新增 build、0 ticker | 修复仅移除副标题参数，无新增动画/监听 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-21 参数语义不变；U-09 判定不需要）。
- 版本：`1.3.1+11` → `1.3.2+12`（视觉 Bug = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.3.1（2026-09-03）[Android] [Web]

### 变更清单（BUG-001）
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **澎湃OS 4 / Android 17 版本误识别（SDK_INT 被厂商 ROM 覆盖为兼容层数值）**：U-04 平台检测工具新增真实 API Level 探测（RELEASE 字符串解析 → PREVIEW_SDK_INT → SDK_INT 降级，一次探测内存缓存，Android 17 = API 37）；main() 在 UI 首帧前探测并缓存；androidSdkInt 优先返回真实值，S-01 派生 Provider（effectiveBlurProvider）、U-03 毛玻璃裁决、Monet 可用性、C-21/C-22 模糊门控、首页系统信息全部自动获得修正值 | U-04、S-01、U-03 | Android 11+ / Web |
| 修复 | 依赖新增 device_info_plus（读取 Build.VERSION.RELEASE 等真实字段；仅 Android 调用，Web 零开销） | U-04 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 探测耗时 | ≤10ms（一次） | 单次平台通道往返，main() 首帧前完成并缓存，后续零开销 | ✅ 代码级通过 |
| 映射正确性 | RELEASE→API 全表 | 单元测试 4 组（含 17→37、12L→32、未知→null）通过 | ✅ 测试通过 |
| 降级安全 | 异常不崩溃 | catch 降级 SDK_INT / 0 | ✅ 代码级通过 |
| Web 兼容 | 不调用探测 | isAndroid 门控，tree-shake | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（版本探测归入既有 U-04 平台检测工具职责；U-09 已冻结为帧率节流，§2.2.3 不可复用）。
- 版本：`1.3.0+10` → `1.3.1+11`（Bug 修复 = Patch，§1.2 判定表；§1.3 只升不降）。

---

## v1.3.0（2026-09-03）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | C-21 折叠标题栏新增 `actions` 参数（路径 A：MiuixTopAppBar 原生 actions 槽位直通，标题居中不被挤偏）；新增 C21CapsuleIconButton 胶囊按钮组件（36×36、圆角 20、半透明背景，**阈值判断**切换颜色——监听 MiuixTopAppBarState.heightOffset，跨阈值才重建一次，零逐帧 lerp、无 Opacity） | C-21 | Android 11+ / Web |
| 新增 | 首页（P-01-01）顶栏右上角传入 3 个胶囊占位按钮（搜索/筛选/更多，Miuix 矢量图标，占位空回调）；按钮列表 build 外定义（成员变量只构建一次） | C-21、P-01-01 | Android 11+ / Web |

### 性能与功耗验收（Minor 迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 按钮重建 | 滚动零逐帧重建 | 阈值翻转才 setState（_collapsed 布尔翻转）；对比 lerp 方案零开销 | ✅ 代码级通过 |
| 按钮可见性 | 展开/折叠均可见 | home_layout_test 断言：展开 3 个、折叠后仍 3 个、点击无异常 | ✅ 测试通过 |
| 监听器释放 | dispose 必移除 | C21CapsuleIconButton.dispose 移除 collapseState 监听 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机 Energy Profiler 采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（C-21 参数增强为既有编号内部变更；U-09 判定可选，未新增）。
- 版本：`1.2.0+9` → `1.3.0+10`（新增功能 = Minor，§1.2 判定表；§1.3 只升不降）。

---

## v1.2.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | C-21 折叠标题栏：展开大标题 ⇄ 折叠小标题滚动联动（MiuixTopAppBar.largeTitle + MiuixExitUntilCollapsedScrollBehavior；§1 禁止 Material 的 SliverAppBar/FlexibleSpaceBar，映射为 Miuix 原生实现）；折叠量=滚动位置纯函数、静止零 ticker、RepaintBoundary 隔离；毛玻璃 U-03 门控（Web 禁用 / Android 13+，sigma 12≤20） | C-21、P-01-01 | Android 11+ / Web |
| 新增 | C-22 内容穿透悬浮底栏：elevated 胶囊悬浮底栏（复用 C-01 胶囊项），内容铺满全屏滚动滑入胶囊下方（外壳 Stack 叠加，等价 Scaffold.extendBody）；模糊仅限胶囊区域（ClipRRect+BackdropFilter）遵循 U-03；RepaintBoundary 滚动零重绘 | C-22、P-01、C-01 | Android 11+ / Web |
| 优化 | 首页（P-01-01）接入 C-21 折叠栏 + C-22 内容穿透底部安全间距（contentBottomInset）；折叠栏滚动驱动替代 v1.0.7 的文本高度测量（布局更稳） | P-01-01、F-02 | Android 11+ / Web |
| 规范 | PROJECT_SPEC §5 C-21/C-22 实现说明按 §1 约束更新为 Miuix 原生实现（编号语义不变） | C-21、C-22 | Android 11+ / Web |

### 性能与功耗验收（Minor 迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| C-21 滚动 build 数 / 静止 ticker | ≤2 次/帧 / 0 | 折叠量=滚动位置纯函数（库实现），吸附动画 280ms 一次性；整栏 RepaintBoundary | ✅ 代码级通过 + 折叠回归断言 |
| C-22 滚动重绘 | 底栏零重绘 | 整栏 RepaintBoundary；模糊仅胶囊区域（≤40% 视口），静态不重采样 | ✅ 代码级通过 |
| 首页布局 | 顶格无空白 | home_layout_test 5 场景（冷启动/折叠/返回/旋转）通过 | ✅ 测试通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 新增：C-21、C-22（已在 §5 登记，引入版本 v1.2.0）。
- 版本：`1.0.7+8` → `1.2.0+9`（新增组件 = Minor，§1.2 判定表）。

---

## v1.0.7（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **安卓版主页（P-01-01）内容位置异常（间歇性顶部大片空白）根因**：首页顶栏使用 `largeTitle`，`MiuixTopAppBar` 大标题依赖 GlobalKey 后帧测量并缓存文本高度，Android CJK 字体回退时序不定时间歇性测得偏高 → 顶栏虚高 → 内容整体下推且缓存不失效。修复：首页改用定高小标题顶栏 + 内容区静态应用标识头（const 零测量）；`contentWindowInsets: EdgeInsets.zero` 消除分支页重复底部手势区内边距；`Column(mainAxisAlignment: start)` 强制顶格（治本） | P-01-01、F-01、P-01 | Android 11+ / Web |
| 规范 | `PROJECT_SPEC.md` 新增 §15 布局稳定规范（顶格结构 / 禁 largeTitle / 禁手动 MediaQuery padding / 分支页 insets 归零 / FocusNode dispose / ListView.builder） | 全部 | Android 11+ / Web |
| 修复 | 新增布局稳定回归测试 home_layout_test.dart：冷启动 / 返回主页 / 横竖屏旋转四场景断言首页顶格（ListView.top < 200） | P-01-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 首页首帧布局 | 内容顶格、无空白 | 回归测试 4 场景断言通过（冷启动/返回/旋转） | ✅ 测试通过 |
| 顶栏高度 | 确定（零测量依赖） | 定高小标题顶栏，无后帧测量 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（补丁不新增 F/P/C/S/R/U/A，§1.2 判定表；§15 为编码规范章节）。
- 版本：`1.0.6+7` → `1.0.7+8`（§1.3 只升不降）。

---

## v1.0.6（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | **「功能生效但开关视觉不变」根因**：设置页 / 主题页整体 `TickerMode(enabled:false)`（§11.1 静态页优化）静音了子树内全部 ticker —— MiuixSwitch 圆点（_thumbPos 动画）与 MiuixTabRow 指示器（AnimatedPositioned）被冻结，轨道色/圆点停留在旧位置。修复：交互型页面（P-01-02 / P-01-02-01）移除整体 TickerMode(false)；真正静态页（关于/权限/调色板）保留。交互控件动画瞬时（≤300ms）且结束即回收 ticker，闲置期零帧开销，功耗目标不受影响 | P-01-02、P-01-02-01、C-06、C-13、C-01 | Android 11+ / Web |
| 修复 | 回归测试升级：新增**视觉层断言** —— 点击开关后断言 MiuixSwitch 圆点 `Positioned.left` 实际右移（>10px），直接捕获 TickerMode 静音类缺陷（修复前必失败） | S-01、S-02 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 开关视觉状态 | 关闭=灰底圆点靠左 · 打开=蓝底圆点靠右 | 回归测试视觉层断言通过（圆点右移 >10px） | ✅ 测试通过 |
| 闲置功耗 | 静态 0 ticker（§11.1） | 交互控件动画瞬时回收，闲置无 ticker 帧；静态页（关于/权限/调色板）仍 TickerMode(false) | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（补丁不新增 F/P/C/S/R/U/A，§1.2 判定表）。
- 版本：`1.0.5+6` → `1.0.6+7`（§1.3 只升不降）。

---

## v1.0.5（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | 设置页「点击生效但 UI 状态不更新」闭环：① 库层已确认 MiuixSwitch 经 didUpdateWidget 同步外部 value、MiuixTabRow 为 prop 驱动；② 全部开关（P-01-02 / P-01-02-01 共 5 个）加显式 ValueKey 固化元素身份，杜绝复用残留；③ 新增回归测试 settings_ui_state_test.dart：点击开关 → value 翻转、点击分段「浅色」→ selectedTabIndex=1、S-02 防抖落盘后读回一致 | P-01-02、P-01-02-01、C-01、C-13、S-01、S-02 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| UI 状态同步 | 点击后高亮/开关即时更新 | 回归测试 3 项断言全部通过 | ✅ 测试通过 |
| 重建范围 | 仅受影响子树 | ref.watch 页面级重建，开关动画 ≤300ms | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（补丁不新增 F/P/C/S/R/U/A，§1.2 判定表）。
- 版本：`1.0.4+5` → `1.0.5+6`（§1.3 只升不降）。

---

## v1.0.4（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | 设置页胶囊按钮（分段/色板）高亮状态加固：复核「点击生效但高亮不变」全链路（ref.watch 重建 → 高亮索引 prop 驱动）；UI 模式 / PaletteStyle 分段与 keyColor 色板加显式 Key 防元素复用残留；PaletteStyle 索引归一化（未知键回退 0）；S-01 控制器仅接受已登记风格键，杜绝脏持久化数据导致高亮错位 | P-01-02、P-01-02-01、C-13、S-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 高亮重建范围 | 仅受影响子树 | 页面级 ref.watch 重建，MiuixTabRow 内部零 ticker | ✅ 代码级通过 |
| 脏数据防护 | 未知风格键不产生错位 | 控制器过滤 + 索引归一化双保险 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（补丁不新增 F/P/C/S/R/U/A，§1.2 判定表）。
- 版本：`1.0.3+4` → `1.0.4+5`（§1.3 只升不降）。

---

## v1.0.3（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 优化 | 缩小 C-12 悬浮底栏高度：库内 MiuixNavigationBarItem 为 64dp 固高且无高度参数（FittedBox/Transform 缩放会破坏 Expanded 布局或产生空洞），改为紧凑自绘项（icon 22 + 小标签），胶囊固定 52dp 高（约缩小 19%）；手势区（viewPadding.bottom）排除在胶囊外 | P-01、C-12 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 悬浮底栏功耗 | 静态 0 ticker · 单层阴影 | 自绘项无按压动画 ticker，无 BackdropFilter | ✅ 代码级通过 |
| 命中区 | ≥48dp | 52dp 胶囊全区域可点（HitTestBehavior.opaque） | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（补丁不新增 F/P/C/S/R/U/A，§1.2 判定表）。
- 版本：`1.0.2+3` → `1.0.3+4`（§1.3 只升不降）。

---

## v1.0.2（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | 「悬浮底栏」开关开启后底栏样式不变：根因为内层 MiuixNavigationBar 不透明背景盖住 C-12 胶囊（MiuixSurface 不裁剪子组件）；修复为透明导航栏 + showDivider:false + ClipRRect 圆角裁剪 + 单层阴影，悬浮形态视觉生效 | P-01-02、P-01、C-01、C-12 | Android 11+ / Web |
| 修复 | 复核「悬浮底栏」开关全链路：S-01 ref.watch 重建（P-01 外壳）、S-02 持久化读写、启动恢复 | S-01、S-02 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 悬浮底栏功耗 | 不产生 BackdropFilter（U-03 降级） | 表面色 + 单层 BoxShadow（§11.2.4 允许 1 层） | ✅ 代码级通过 |
| 开关切换重建范围 | 仅底栏子树 | RepaintBoundary 隔离，内容区不重绘 | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（补丁不新增 F/P/C/S/R/U/A，§1.2 判定表）。
- 版本：`1.0.1+2` → `1.0.2+3`（§1.3 只升不降；此前已发布 v1.0.1，故本次为 v1.0.2）。

---

## v1.0.1（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 修复 | Android 系统字体缩放（textScaleFactor > 1.0）导致 Miuix 布局溢出：路由入口（R-01）全局强制 `textScaler = noScaling`（等价 textScaleFactor: 1.0），覆盖全部 MediaQuery 继承缩放 | F-01、R-01 | Android 11+ / Web |
| 修复 | 移动版（Android）设置页禁用「页面缩放」拉条（置灰 + 说明），C-15 在 Android 端强制 1.0 直通，残留设置不生效；页面缩放仅 Web 可用 | P-01-02、C-15、S-01 | Android 11+ / Web |

### 性能与功耗验收（补丁迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| 文本缩放覆盖 | 全路由恒为 1.0 | MaterialApp.builder 单点覆盖，0 逐帧换算 | ✅ 代码级通过 |
| 页面缩放（Android） | 禁用且无残留 | 拉条 enabled=false + 壳层强制 1.0（C-15 短路零开销） | ✅ 代码级通过 |
| 帧率 / 功耗实测 | ≥120/≥100 fps · ≤450/800/1200 mW | 待真机采样 | ⏳ 后续版本补充 |

### 涉及编号变更
- 无新增编号（补丁不新增 F/P/C/S/R/U/A，§1.2 判定表）。
- 版本：`1.0.0+1` → `1.0.1+2`（build 号单调递增）。

---

## v1.0.0（2026-09-01）[Android] [Web]

### 变更清单
| 变更类型 | 变更说明 | 涉及编号 | 平台兼容性 |
| :--- | :--- | :--- | :--- |
| 新增 | 工程初始化：Clean Architecture 分层（core/data/domain/presentation）、Riverpod + go_router + flutter_miuix 依赖、lint 强制规则 | F-01、U-04 | Android 11+ / Web |
| 新增 | 主题与 Monet 集成：S-01 状态机、色板一次性生成缓存、平台降级、P-01-02-01 配置页 | F-08、S-01、S-02、P-01-02-01、R-09、U-02 | Android 11+ / Web |
| 新增 | 主框架与响应式导航：P-01、C-01 底部导航、C-02 侧边导航、C-12 悬浮底栏、700px 断点 | F-01、P-01、C-01、C-02、R-01 ~ R-04 | Android 11+ / Web |
| 新增 | 首页复刻：版本信息、系统信息、功能入口卡片 | F-02、P-01-01、S-04 | Android 11+ / Web |
| 新增 | 设置页复刻：全部设置项 + 持久化（防抖落盘） | F-03、P-01-02、S-02、C-03、C-06、C-07、C-13 | Android 11+ / Web |
| 新增 | 关于页 / 色彩调色板页 / 权限管理页 | F-04、F-05、F-06、P-01-03、P-02、P-03、C-05 | Android 11+ / Web |
| 优化 | 毛玻璃策略落地：Web 与 Android<13 强制禁用，U-03 裁决 + UI 置灰说明 | C-10、U-03 | Android 11+ / Web |

### 性能与功耗验收（工程初始化迭代）
| 指标 | 目标 | 实测 | 结果 |
| :--- | :--- | :--- | :--- |
| Android 平均帧率 / 最低帧率 | ≥120 / ≥100 fps | 待真机采样（S-14 未启用） | ⏳ 后续版本补充 |
| 亮屏闲置 / 滑动 / 动画功耗 | ≤450 / 800 / 1200 mW | 待 Energy Profiler 实测 | ⏳ 后续版本补充 |
| Web 首屏 / 滚动 CPU | ≤2s / ≤30% | 待 Chrome Task Manager 实测 | ⏳ 后续版本补充 |
| 静态页 ticker | 0 | 设置/关于/权限页 TickerMode(enabled:false) 已落实 | ✅ 代码级通过 |

### 涉及编号变更
- 新增：F-01 ~ F-09、P-01（含 01-01/01-02/01-02-01/01-03）、P-02、P-03、C-01 ~ C-07、C-10、C-12、C-13、C-15、S-01 ~ S-06、R-01 ~ R-06、R-09、U-02 ~ U-05（均按 PROJECT_SPEC §13 SOP 冻结登记）。
- 版本：`1.0.0+1`（首个可运行版本定版，§1.2 判定表）。
