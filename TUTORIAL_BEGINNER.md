# Toki 新手实战教程

> 对象:会电脑、会用 VSCode,但没写过 Flutter / Dart 代码的新手。
> 内容:每一步都发生在**这个真实项目**(xiangjugong)里,照着做就能看到效果。
> 配套:看不懂术语时,先翻 `CODE_REFERENCE.md`(文件地图)和 `docs/dev-flow-beginner.html`(开发流程图,浏览器打开)。

---

## 第 0 章 先建立三个观念

1. **改代码 = 改文件里的文字**,点保存,然后让 App "热重载"看你改的效果。没有魔法。
2. **每个文件头部都有几行中文注释**(以 `//` 开头),它是这个文件的"自我介绍",先读它。
3. 本项目界面**不用 Flutter 自带的 Material 样式**,全部用 `flutter_miuix` 组件(小米 HyperOS 风格)。你看到 `Miuix` 开头的都是它家的。

---

## 第 1 章 这个应用是什么

**Toki**(曾用名:箱具工)是你手机上的一个工具 App(代码在 `D:\web dev\flutter miuix project\xiangjugong`)。打开它你能看到:

| 界面 | 干什么 | 数据存在哪 |
|---|---|---|
| 首页(底栏第 1 页) | 问候语 + 每日一言、小课表、**今日剩余**圆环(点击可编辑每天的活动时间) | 课表、每日活动时间 |
| 工具(底栏第 2 页) | 占位页,以后放工具入口 | — |
| 顶部 ⋯ 菜单 | 设置 / 关于(以后可以加更多) | — |
| 设置 | 深色模式、主题色(Monet)、毛玻璃开关、悬浮底栏开关、页面缩放 | 存在 `settings.*` |

App 的数据全存**本机**(SharedPreferences),不联网。改代码不会动到手机数据——除非你改的是"默认值"(见练习 3)。

---

## 第 2 章 认识项目的"零件"(哪里是什么)

在 VSCode 里打开项目文件夹,左边 `lib` 就是全部代码。**主项目入口是 `lib/main.dart`**,构建时也是默认用它(不要加 `-t` 参数)。

```
lib/
├─ main.dart                     应用大门:主题、Provider、路由全部在这装配
├─ core/                         通用零件(颜色工具、毛玻璃策略、滚动设置、日志…)
├─ domain/                       纯业务"模型":实体 + 仓库接口(不碰界面)
│   ├─ entities/                 ★ 数据长什么样(课程、每日活动、设置、首页卡片)
│   └─ repositories/             仓库"说明书"(接口)
├─ data/repositories/            仓库"真身":SharedPreferences 读写(JSON)
└─ presentation/                 所有界面
    ├─ shell/main_shell_page.dart    主框架:<700px 用底栏,≥700px 用侧边栏
    ├─ router/app_router.dart        路由表:每个页面地址(URL)
    ├─ providers/                    全局状态(数据"服务器")
    ├─ features/                     页面本体(按功能分文件夹)
    └─ widgets/                      可复用组件(编号 C-xx)
        ├─ cards/                    首页的卡片们(C-27~C-30)
        ├─ kernel/                   底栏核心(从 KernelSU 一比一移植)
        └─ c21~c28_*.dart            标题栏/毛玻璃/菜单等组件
```

**编号就是地图**(文件头注释里都写着):

| 编号前缀 | 代表 | 例子 |
|---|---|---|
| P-xx | 页面 | P-01-01 首页、P-06 大课表 |
| C-xx | 组件 | C-22 底栏、C-26 更多菜单、C-28 组合大卡 |
| S-xx | 服务(能力) | S-02 设置存储、S-05 每日活动、S-15 课表 |
| R-xx | 路由(页面地址) | R-04 `/settings`、R-10 `/timetable` |
| U-xx | 工具函数 | U-03 毛玻璃策略 |
| #a0x | 卡片内部的小零件 | #a01 小课表、#a04 圆环 |

> 💡 你在 App 上看到"奇怪的东西",先想它是 P(一整页)、C(一个块)还是 S(一个能力),然后去 `CODE_REFERENCE.md` 表格里查文件。

---

## 第 3 章 第一次跑起来(VSCode 全流程)

**准备工作(只需一次):**
1. 装好 Flutter SDK(教程要求你本机 `flutter --version` 能输出版本)。
2. VSCode 装扩展:**Flutter** 和 **Dart**(装 Flutter 会自动带上 Dart)。
3. 手机开 USB 调试插电脑;或启动一个安卓模拟器。

**启动步骤:**
1. VSCode `文件 → 打开文件夹…`,选 `xiangjugong` 文件夹。
2. 底部状态栏会显示设备(如 `2510DRK44C`)。没显示就按 `Ctrl+Shift+P` 输入 `flutter devices` 回车,或点状态栏设备名选择。
3. 打开 `lib/main.dart`,按 **F5**(或点右上 ▶ "Run and Debug")。
4. 第一次会编译 1~3 分钟,然后 App 装进手机自动打开。🎉
5. 以后每次改完代码,**在 VSCode 的"调试控制台"里按 `r`**(热重载,1~3 秒)就能看效果;改的东西"大动干戈"了(改了 main.dart 或新增文件)按 `R`(热重启)。按 `q` 退出。

> 找不到终端焦点?先点一下"调试控制台"再按 `r`。
> 手机锁屏/断开时会提示 `Lost connection to device`,属正常,重新插上再 F5。

---

## 第 4 章 读懂一个页面文件(以设置页为例)

打开 `lib/presentation/features/settings/page_p01_02_settings_page.dart`,从上往下:

```dart
// lib/presentation/features/settings/page_p01_02_settings_page.dart
// 编号:P-01-02 设置页(F-03 设置模块)
// 说明:…           ← 第 1 段:文件自我介绍,必读
import 'package:flutter_riverpod/riverpod.dart';   // 第 2 段:它需要谁(依赖)
import '../widgets/c22_...';                        //   相对路径:../ = 上一层文件夹

class PageP0102SettingsPage extends ConsumerStatefulWidget {  // 第 3 段:定义"页面"
  ...
}
```

**只需要认得这几个词:**
- `class 名字 extends …Widget` —— 声明一个"界面零件"。**改文件名时,里面的 class 名也要一起改**。
- `build(BuildContext context)` —— 每次重画界面就执行这里,你要改的"显示什么"基本都在它 return 的树里。
- `ref.watch(xxxProvider)` —— 用某份全局数据;数据变了它会自动重画。
- `Text('文案')` / `MiuixText('文案')` —— 显示一行字;**改文字 = 改引号里的话**。

**找东西的技巧(整个教程通用的"搜索大法"):**
在 VSCode 里按 `Ctrl+Shift+F` 全局搜,`Ctrl+F` 在当前文件搜。
例:想知道首页"今日剩余"这几个字在哪 → 全局搜 `今日剩余`,你会跳到定义它的文件。

---

## 第 5 章 手把手练习(从易到难)

> 每个练习:做完 → 按 `r` 热重载 → 看效果。没效果就做第 9 章"自救"。

### 练习 1:改首页的问候语和每日一言 🟢 最简单

**目的:** 体会"界面文字不是画上去的,是数据给的"。

1. 打开 `lib/presentation/providers/home_cards_provider.dart`(首页卡片的数据源)。
2. 找到这段:

```dart
SummaryCardData(
  greeting: '雑魚，XX',
  dailyLabel: '每日一言',
  dailyContent: '“生活不是等待风暴过去,而是学会在雨中跳舞。”',
),
```

3. 把 `greeting` 改成你的名字,把 `dailyContent` 换成你的一句话(注意保留引号,中文引号或英文引号都行,但别删逗号)。
4. 按 `r` → 首页顶部卡片立刻变成你写的内容。

**理解:** 首页卡片(C-27 摘要区)只负责"显示",文字内容由这个 provider 提供。**想改显示内容,先找数据源,别去页面里翻。**

### 练习 2:改"今日剩余"卡片的标题 🟢

1. 还是在 `home_cards_provider.dart`,往下找:

```dart
ComboCardData(
  remainingTitle: '今日剩余',
  ...
),
```

2. 把 `'今日剩余'` 改成 `'今天还剩'` 之类,热重载。组合大卡右上角标题变了。
3. 圆环中间的大数字(剩余时长)不是这里控制的——它来自 `daily_activity_provider.dart` 的 `todayRemainingProvider`(按你每天设的活动时间实时算)。**同一个卡片,不同文字来自不同文件**,这就是为什么先搜再改。

### 练习 3:改"每日活动时间"的默认值 🟡

**背景:** App 会为每天预设活动时间(工作日 09:00–18:00,周末 10:00–20:00)。这个默认值定义在 `lib/domain/entities/daily_activity.dart`。

1. 打开它,搜 `defaults`(约在文件中部):

```dart
static DailyActivityTime defaults(int weekday) {
  // 里面写着类似 startMinutes: 540, endMinutes: 1080 的代码
  // 540 = 09:00,1080 = 18:00(从 0 点算起的分钟数)
}
```

2. 想默认 08:30 开始 → `8*60+30 = 510`,把 `startMinutes` 改 510。
3. ⚠️ **重要:** 默认值只在"手机还没有这份数据"时生效。你手机上已经保存过 → 改默认值看不到变化。想看效果:卸载 App 重装,或在编辑窗里点"恢复默认"(会重新用默认值)。

**换算公式:** `小时×60 + 分钟`。比如 22:30 = `22*60+30 = 1350`。

### 练习 4:给顶部 ⋯ 菜单加一项(跳到已有的"调色板"页)🟡

**只改一个文件**,因为"调色板"页面和路由早就存在(在设置页里有入口)。

1. 打开 `lib/presentation/providers/nav_items_providers.dart`,找到:

```dart
final moreMenuItemsProvider = Provider<List<MoreMenuItem>>((ref) => const [
  MoreMenuItem(iconName: 'tune', label: '设置', route: '/settings'),
  MoreMenuItem(iconName: 'info', label: '关于', route: '/about'),
]);
```

2. 在列表里加一行(复制上面格式):

```dart
  MoreMenuItem(iconName: 'info', label: '调色板', route: '/color-palette'),
```

3. 热重载 → 点首页右上角 ⋯ → 出现了"调色板",点它跳到调色板页。
4. 想跳别的已存在页面?看 `app_router.dart` 里 `_knownPaths` 有哪些路径(如 `/permissions`、`/timetable`),照抄即可。
5. **图标名拿不准怎么办:** 复制一个已经存在的(如 `'tune'`、`'info'`);想换别的,去 `core/widgets/app_icons.dart` 看 `appIcon()` 的注释。乱编名字不会报错,只会显示成默认箭头。

### 练习 5:改底栏上的字/图标 🟡

还是在 `nav_items_providers.dart`,上半段:

```dart
final bottomBarItemsProvider = Provider<List<C22BarItemData>>((ref) => const [
  C22BarItemData('home', '首页'),
  C22BarItemData('tools', '工具'),
]);
```

把 `'工具'` 改成 `'工具箱'` → 底栏第二项文字变了。第一个参数(`'home'`/`'tools'`)是图标名,别乱改(改了图标会变),文字随便改。

### 练习 6(挑战):造一个自己的页面并让它能跳过去 🔴

目标:复制"关于页"→ 改名 → 注册路由 → 加入 ⋯ 菜单。全程复制粘贴,不改逻辑。

1. **复制文件:** 在 VSCode 左侧,右键 `lib/presentation/features/about/page_p01_03_about_page.dart` → 复制,粘贴到**同一文件夹**,重命名为 `page_p01_03_about_page.dart` 的副本 `page_p01_05_my_page.dart`(放同目录即可,先不管名字规范)。
2. **改类名(必须,否则冲突):** 打开新文件,把里面的 `PageP0103AboutPage` 全部替换成 `PageP0105MyPage`(选中后 `Ctrl+H` 逐个替换)。文件头部注释也顺手改一行说明。
3. **注册路由:** 打开 `lib/presentation/router/app_router.dart`:
   - 顶部 import 区加:`import '../features/about/page_p01_05_my_page.dart';`(照着它上一行写);
   - `_knownPaths` 集合里加一行 `'/my-page', // 我的新页面`;
   - 底部 `routes:` 列表里照抄一个 `GoRoute`,改成:

```dart
  GoRoute(
    path: '/my-page',
    name: 'R-11',
    builder: (context, state) => const PageP0105MyPage(),
  ),
```

4. **菜单加入口:** 按练习 4 加一项 `route: '/my-page'`。
5. 按 `R`(改了 main 层之外的文件结构,建议热重启),从 ⋯ 菜单进入你的页面。🎉

**理解:** 加一个新页面 = ① 造页面文件 ② 告诉路由表(名字+地址)③ 给一个入口(菜单/按钮)。三步缺一不可。

---

## 第 6 章 "想改 X 去哪改"速查(先搜再改)

所有修改前,先按 `Ctrl+Shift+F` 全局搜关键词,下面给的是"确定会中"的位置:

| 想改什么 | 去哪个文件 | 搜什么 |
|---|---|---|
| 首页问候语/每日一言 | `presentation/providers/home_cards_provider.dart` | `greeting` / `dailyContent` |
| "今日剩余"标题 | 同上 | `remainingTitle` |
| 卡片文字/圆角/颜色 | `presentation/widgets/cards/card_*.dart` | 文字直接搜;圆角搜 `borderRadius` |
| 卡片阴影(全部卡片统一) | `presentation/widgets/cards/home_card_layout.dart` | `_CardShadow` |
| 小课表显示什么课 | 数据来自 `course_provider.dart`(课程在 App 里导入) | `courseListProvider` |
| 剩余时间算法/文案 | `presentation/providers/daily_activity_provider.dart` | `todayRemainingProvider` |
| 每天默认活动时间 | `domain/entities/daily_activity.dart` | `defaults` |
| 底部"更多"菜单项 | `presentation/providers/nav_items_providers.dart` | `moreMenuItemsProvider` |
| 底栏按钮项 | 同上 | `bottomBarItemsProvider` |
| 底栏大小/动画/颜色参数 | `presentation/widgets/c22_visual_params.dart` | **只改这个文件**,别在别处写数字 |
| 底栏按压手感 | `presentation/widgets/kernel/damped_drag.dart` | `spring` |
| 加页面/改地址 | `presentation/router/app_router.dart` | `_knownPaths` |
| 主题色/深色模式 | App 内"设置 → 主题与色彩"就能改;代码在 `main.dart` | `MiuixThemeController` |
| 全局滚动"回弹"手感 | `core/widgets/app_scroll_behavior.dart` | `BouncingScrollPhysics` |
| 图标统一取用 | `core/widgets/app_icons.dart` | `appIcon` |
| 每日活动存哪 | `data/repositories/daily_activity_repository_impl.dart` | key `daily.activity` |
| 课程存哪 | `data/repositories/course_repository_impl.dart` | key `course.list` |
| 设置存哪 | `data/repositories/settings_repository_impl.dart` | key `settings.*` |
| 日志/导出 | `core/logging/` | `AppLogService` |
| 性能监控 | `core/logging/perf_monitor.dart` | `PerfMonitor` |

---

## 第 7 章 数据存手机这件事

所有数据都是 **SharedPreferences**(手机本地"键值对仓库"),App 卸载就没了。全部 key:

| key | 存什么 | 谁在写 |
|---|---|---|
| `daily.activity` | 一周 7 天的活动时间段(约 300 字节 JSON) | 每日活动编辑窗 |
| `course.list` / `course.meta` | 课程列表与元信息 | 课表导入/编辑 |
| `settings.uiMode` 等 8 个 | 主题、毛玻璃、悬浮底栏、页面缩放… | 设置页 |

**新手必知的坑:** 每日活动编辑窗保存时,程序内部用 `saveAll(…)` **一次写完 7 天**(`daily_activity_provider.dart`)。你以后若改保存逻辑,**千万别改成"每天单独保存一次"**——之前就是那样导致保存慢、像没反应,已经修过。

**数据乱了/想重置:** 编辑窗里有"恢复默认"入口(`resetDefaults`);彻底重置 = 卸载重装。

---

## 第 8 章 发布新版本(版本号规则)

只做小改动练习时不用管这章;要"发版"时按这个顺序:

1. `flutter analyze` —— 必须 **0 告警**(红色报错=必须修,黄色警告=最好修)。
2. 打开 `pubspec.yaml`,改 `version:`(规则:**加功能 → 中间号+1;修 bug/优化 → 最后号+1;只升不降**。如 `1.19.1+96` 修了个 bug → `1.19.2+97`)。
3. `CHANGELOG.md` 顶部加一条记录(版本号、日期、改了啥,参考旧条目格式)。
4. 构建:
   ```
   flutter build apk --release     # 安卓正式包
   flutter build web --release     # Web 版(产物在 build/web)
   ```
5. 把 apk 复制到外面的 `发布包/` 文件夹,文件名带上版本号,例如 `xiangjugong_v1.19.2_official-release.apk`。
6. 装到真机验收,通过才算完成。

> 构建命令**不要加 `-t lib/main_kernel.dart`** 那种参数——那是另一个 demo 项目(`miuix_bottombar_demo`)的入口,本项目入口就是默认的 `lib/main.dart`。加错了会报找不到文件。

---

## 第 9 章 报错自救手册(按症状查)

**1. 改完按 r 没反应 / 还是老样子**
→ 你改的文件可能不在运行中的 App 里(搜错地方了);或改了 `main.dart`/`pubspec.yaml` 需要按 `R` 热重启/重新 F5;再不行看调试控制台有没有红字。

**2. 红字一大片,看不懂**
→ 看**第一行**和**最后一个"Error"**。最常见两类:
- 少了个括号/引号/逗号 → 错误会指出文件与行号,回去数括号;
- 名字写错(文件改名忘改 class 名)→ 全局搜旧名字,全部替换。

**3. 界面错位、按钮被挤没**
→ 常见于改了宽度/高度。找对应文件里 `ConstrainedBox`/`SizedBox`/`padding`,先把数值改回原样,一次只改一处验证。

**4. 毛玻璃没效果**
→ 不是 bug:Android 12 及以下、Web 上,程序会**自动降级成半透明**(策略在 `core/utils/u03_blur_policy.dart`)。真机 Android 13+ 才看得到真模糊。

**5. "保存没反应"**
→ 先确认是不是在每日活动编辑窗;点保存后看右上有没有 toast。若真没反应,去看 `daily_activity_provider.dart` 的 `saveAll` 是否被调用(别自己改成循环保存)。

**6. 运行时报 `Lost connection to device`**
→ 手机锁屏/拔线了。重插、解锁,重新 F5。

**7. `flutter build apk` 报错**
→ 先跑 `flutter analyze` 修到 0 告警;确认命令没带 `-t`;磁盘满了也可能报,清一下 `build` 目录(`flutter clean` 后重新 build)。

**8. 完全懵了**
→ 把文件改回原样(`Ctrl+Z`),把报错第一行复制给 AI 问;改之前先备份文件(项目根目录有 `*_backup_*` 文件夹就是干这个的)。

---

## 第 10 章 项目规矩(为什么这么写)

新手照规矩写,老手看了不皱眉:

1. **新 UI 一律用 flutter_miuix 组件**(`MiuixCard`/`MiuixText`/`MiuixButton`…),别用 Material 的 `Card`/`TextButton` 全家桶(仅 `TextField` 输入、`MaterialApp` 壳等少数例外)。
2. **文件头写注释**:第一行路径 + `编号:` + 这段代码干嘛。
3. **数字别写死**:底栏一切参数在 `c22_visual_params.dart`;图标经 `appIcon()` 取;文字能进 provider 就进 provider。
4. **改完先 `flutter analyze`** 再提交/发版。
5. **存储 key 有规律**:`模块.字段`(如 `daily.activity`),新 key 跟着这个风格。
6. 界面文案默认中文;页面/组件编号不重复使用。

---

## 下一步建议

1. 先做练习 1~3 找手感 → 对照 `CODE_REFERENCE.md` 认文件 → 浏览器打开 `docs/dev-flow-beginner.html` 把"完整开发流程"图看一遍。
2. 有具体想改的功能,按第 6 章表定位,先全局搜关键词再动手。
3. 想彻底搞懂某个文件:读它头注释 → 看 import → 找到 `class` → 从 `build` 读起,不认识的组件名回 `CODE_REFERENCE.md` 查编号。

> 最后记住:这个项目有完整备份习惯,大胆改,错了 `Ctrl+Z` 或从备份恢复即可。
