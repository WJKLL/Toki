# PLAN_widget_v1.51.md

> 百工箱桌面小组件 **F-10 · 今日课程卡**（澎湃先行版）
> 目标版本：**v1.51.0**（Minor）
> 唯一验证目标：**红米 K90（2510DRK44C）· HyperOS 4.0 · Android 17（SDK 37）**
> 前置版本：v1.50.3+159
> 关联编号：**S-26**（数据桥）/ **F-10**（功能模块）/ R-10（课表路由）
> **v1.51.1 修订**：卡面由「今日课程三列列表」改为「当前 / 下一节课**焦点卡**」，结构、文案、配色逐条对齐鸿蒙版服务卡片（`harmonyos_port` 的 `TodayCourseCard.ets` 与 `lib/core/cards/course_card_sync.dart`）。**尺寸声明一字未动**（仍是 250×110dp / 4×2）。
> **v1.51.2 修订**：实机 4×2 实际渲染 176dp 而内容原仅约 106dp（居中后上下各空 35dp），故课程名 16 → **22sp**，各行改用 `layout_marginBottom` 分配间距（8 / 4 / 6 / 5dp），各行合计约 119dp、加 padding 后总占用约 141dp。**尺寸声明仍未动**；代价是缩到声明下限 110dp 时底部「下一节行」会被裁。
> **华为 / HarmonyOS 不在本规划内**（走 FormKit，另行规划）

---

## 1. 范围

### 本期做

1. **1 张卡**：今日课程（4×2）
2. **S-26 数据桥**：Flutter 计算 → MethodChannel `xiangjugong/widget` → SharedPreferences `widget_store`
3. **扁平 RemoteViews 渲染**：≤2 层 ViewGroup 嵌套、静态色值、无 Bitmap、不用 `RemoteViewsService`
4. **刷新**：复用现有课程 AlarmManager 闹钟 + 新增静默「下课」闹钟 + `updatePeriodMillis` 兜底
5. **点击深链**：`PendingIntent` → `MainActivity.onNewIntent` → `/timetable`（R-10）

### 本期不做（推迟）

WorkManager 周期刷新 · Jetpack Glance · U-06 厂商适配层 · P-21 管理页 · C-53 / C-54 ·
多卡片 · 宽窄双布局（`onAppWidgetOptionsChanged`）· 课程表卡 / 余额卡 · 卡片内交互

### 与 v1.36.0 失败版的差异

| 维度 | v1.36.0（已移除） | 本期 |
|:---|:---|:---|
| 布局 | RemoteViews 嵌套过深 | **≤2 层**，固定 3 行静态布局 |
| 图形 | 自定义 Bitmap / Canvas | **零 Bitmap**，纯 TextView |
| 颜色 | 动态主题资源（`?attr/`、`@color/` 引用主题） | **字面量色值**经 `setTextColor` 下发 |
| 集合 | 猜测使用了 ListView / Adapter | **不用** `RemoteViewsService` |
| 刷新 | 依赖 `updatePeriodMillis` | 课程闹钟精确补点 + `updatePeriodMillis` 兜底 |

---

## 2. 卡片规格

```
┌──────────────────────────────────────────────────┐
│ 今日课程                       第 12 周 · 第 1 学期│  ← 标题行 12.5sp / 11sp
│ 当前课程                           剩余 40 分钟   │  ← 标签行 11sp 强调蓝 / 11sp 次要
│ 高等数学                                          │  ← 课程名 22sp 粗体（视觉焦点）
│ 教室:A-301                                        │  ← 教室 11sp 次要
│ 下一节课是:大学英语 09:50                         │  ← 下一节 11sp 次要
└──────────────────────────────────────────────────┘
```

| 项 | 值 |
|:---|:---|
| 尺寸 | `minWidth=250dp` / `minHeight=110dp` / `minResizeWidth=250dp` / `minResizeHeight=110dp`；`targetCellWidth=4` / `targetCellHeight=2` = **4×2**（**v1.51.1 起尺寸声明一字未动**） |
| 依据 | HyperOS 4 实测：`70n-30` 公式成立（n=4→250，n=2→110），Gmail / Chrome / Telegram / WakeUp 均用此值 |
| 结构 | **焦点卡**（v1.51.1 起，对齐鸿蒙版 `TodayCourseCard.ets`）：标题行 → 标签行 → 课程名大字 → 教室行 → 下一节行；**已不再是三列列表** |
| 标签三态 | `当前课程` / `下一节课` / `全天课程结束`（强调蓝 `#3482FF`）；无课表时标签行隐藏 |
| 大字 | 课程名 **22sp** 粗体（v1.51.2 由 16sp 放大，利用实机多余高度）；无课表 → `暂无课程`，全天结束 → `休息中` |
| 倒计时 | 上课中在标签行右侧显示「剩余 N 分钟」（鸿蒙版是 36×36 圆环 + 数字，RemoteViews 画不出环形进度，降级为等义文本） |
| 空字段 | 周次 / 标签 / 剩余 / 教室为空时 `GONE` 塌陷（对齐鸿蒙版 `if (x.length > 0)` 写法），行间距用 `layout_marginBottom`（8 / 4 / 6 / 5dp）而非固定行高，GONE 时 margin 一并塌陷；整块靠根 `gravity="center_vertical"` 居中 |
| 点击 | 整卡 → `/timetable`（R-10） |
| 配色 | 亮 `#111111` / `#8A8A92`、暗 `#FFFFFF` / `#9E9E9E`、强调 `#3482FF`（取自 `docs/notification-mockup.html`） |

---

## 3. 数据桥协议（S-26）

通道名：**`xiangjugong/widget`**

| 方法 | 参数 | 返回 | 说明 |
|:---|:---|:---|:---|
| `writeTodayCourses` | `{json: String}` | `bool` | 写入快照并触发刷新（写入后立即 `AppWidgetManager.updateAppWidget`） |
| `clear` | `{}` | `bool` | 清空快照（用户关闭开关时） |
| `getInitialRoute` | `{}` | `String?` | 取小组件点击带来的启动深链（如 `/timetable`），**读取后清空**（一次性） |
| `requestPin` | `{}` | `{supported: bool, launched: bool}` | 请求添加到桌面；不支持时返回 `supported=false` 供降级提示 |

---

## 4. 数据格式（`widget.todayCourses`）

```json
{
  "v": 2,
  "updatedAt": 1789000000000,
  "dateKey": "2026-09-10",
  "weekText": "第 12 周 · 第 1 学期",
  "curTag": "当前课程",
  "curName": "高等数学",
  "curRoom": "教室:A-301",
  "nextLine": "下一节课是:大学英语 09:50",
  "remainText": "剩余 40 分钟",
  "isDark": false
}
```

| 字段 | 说明 |
|:---|:---|
| `v` | 格式版本（**v2 = 焦点卡契约**；v1 为已废弃的三列列表契约），原生据此判兼容 |
| `updatedAt` | 写入时间戳（诊断用） |
| `dateKey` | `yyyy-MM-dd`；原生比对当前日期，**不一致视为过期**（跨天兜底 → 按空态渲染） |
| `weekText` | 标题行副标题，如 `第 12 周 · 第 1 学期`（与鸿蒙版同文案） |
| `curTag` | 标签三态：`当前课程` / `下一节课` / `全天课程结束`；空串 = 隐藏标签行 |
| `curName` | 课程名（大字焦点）；无课表时 `暂无课程`、全天结束时 `休息中` |
| `curRoom` | `教室:xxx`；无教室信息 → 空串（原生隐藏该行） |
| `nextLine` | 末行提示：`下一节课是:…` / `再下一节:…` / `今天没有更多课了` / `明天也要好好上课 ✨` / `点击卡片去添加` |
| `remainText` | `剩余 N 分钟`，仅上课中出现；空串 = 隐藏 |
| `isDark` | 亮暗模式 → 原生据此选择 `widget_today_courses` / `_dark` 布局 |

**存储**：SharedPreferences 文件名 `widget_store`，键 `widget.todayCourses`（仅此一个键）。
**计算口径**：逐条移植鸿蒙版 `lib/core/cards/course_card_sync.dart`（周次过滤 / 进行中与下一节判定 / 全部文案），使两端卡片判定与文案完全一致。

---

## 5. 原生文件结构

```
android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/
├─ WidgetDataStore.kt            // SharedPreferences 读写
├─ WidgetBridge.kt               // MethodChannel "xiangjugong/widget" 处理器
├─ WidgetRefresh.kt              // 统一刷新入口（读快照 → 渲染 → 广播）
├─ TodayCoursesWidgetProvider.kt // AppWidgetProvider
└─ WidgetClickReceiver.kt        // 点击 → PendingIntent → MainActivity

android/app/src/main/res/
├─ layout/widget_today_courses.xml
├─ drawable/widget_bg_light.xml
├─ drawable/widget_bg_dark.xml
└─ xml/widget_today_courses_info.xml
```

**Manifest 注册**：一个 `<receiver>`，`android:exported="true"`，intent-filter 含
`android.appwidget.action.APPWIDGET_UPDATE`。

---

## 6. 刷新链路

| 触发源 | 时机 | 载体 |
|:---|:---|:---|
| App 内数据变更 | 课表 / 周次 / 节次设置变更，去抖 500ms | Flutter S-26 → `writeTodayCourses` |
| 课程开始 | 每节课开始时刻 | 现有 `_scheduleCourseAlarms()` 闹钟 → `ReminderReceiver` 顺带刷新 |
| 课程结束 | 每节课结束时刻 | **不排独立闹钟**：同一次刷新里由原生按当前墙钟重算，故「下一节开始」的闹钟即会修正上一节的「已结束」 |
| 兜底 | 约 30 分钟 | `updatePeriodMillis=1800000` —— 覆盖「当天最后一节课结束」这一无后续闹钟的场景 |
| 开机 / 应用更新 / 改时间 | 系统广播 | `ReminderReceiver` 已监听，顺带刷新 |
| 亮暗切换 | App 主题变化 | `WidgetBridge.didChangeDependencies` |

**新增依赖：0**（不需要 WorkManager）。

**已知限制（v1.51.0 接受）**：当天最后一节课下课后，卡片最多 30 分钟内仍显示「上课中」
（下一次 `updatePeriodMillis` 兜底刷新，或用户打开 App 时立即修正）。
若实测体验不可接受，v1.51.x 再补一个「静默结束闹钟」（需给 `ReminderScheduler`
的 `alarmIntent` / `alarmJson` / `restoreAlarms` 三处加 `silent` 字段）。

---

## 7. 深链

```
RemoteViews 点击 → PendingIntent.getActivity(MainActivity, extra "widget_route"="/timetable")
  → MainActivity.onNewIntent 读取 extra → WidgetBridge 暂存
  → Flutter 启动时 getInitialRoute() 取走（一次性）
  → appRouterProvider 的 initialLocation
```

冷启动与热启动（`singleTop` + `onNewIntent`）两条路径都要覆盖。

---

## 8. 验收

- [ ] 红米 K90 桌面上可添加 4×2 卡片，渲染正常（无空白 / 塌陷 / 透明）
- [ ] 今日课程按「课程名 → 时间 → 课室」三列显示；进行中课程高亮
- [ ] 无课时显示「今日无课」；课室为空时该列留空
- [ ] 课程开始 / 结束 ±1 分钟内刷新
- [ ] 点击卡片跳转课表页（冷启动 + 热启动）
- [ ] App 被杀死后仍按时刷新；重启手机后恢复
- [ ] `flutter analyze lib test` = 0 issues；全量测试通过（基线 138/138 + 新增）
- [ ] APK 增量可忽略（基线 `_release\app-release.apk` = 78,302,468 B）

---

## 9. 文档同步

| 文档 | 内容 |
|:---|:---|
| `CHANGELOG.md` | v1.51.0 条目（F-10 / S-26） |
| `CODE_REFERENCE.md` | §1.9 基础设施加 S-26；§2.2 存储 key 加 `widget.todayCourses` |
| `pubspec.yaml` | 版本 1.50.3+159 → **1.51.0+161** |
