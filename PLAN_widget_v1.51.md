# PLAN_widget_v1.51.md

> 百工箱桌面小组件 **F-10 · 今日课程卡**（澎湃先行版）
> 目标版本：**v1.51.0**（Minor）
> 唯一验证目标：**红米 K90（2510DRK44C）· HyperOS 4.0 · Android 17（SDK 37）**
> 前置版本：v1.50.3+159
> 关联编号：**S-26**（数据桥）/ **F-10**（功能模块）/ R-10（课表路由）
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
│ 今日课程 · 周三                            4 门   │  ← 标题行
│ ──────────────────────────────────────────────── │
│ 高等数学         08:00-09:40        A-301        │  ← 进行中（课程色 + 加粗）
│ 大学英语         10:00-11:40        B-202        │
│ 数据结构         14:00-15:40        C-105        │
│ … 等 1 门                                        │
└──────────────────────────────────────────────────┘
```

| 项 | 值 |
|:---|:---|
| 尺寸 | `minWidth=250dp` / `minHeight=110dp` = **4×2** |
| 依据 | HyperOS 4 实测：`70n-30` 公式成立（n=4→250，n=2→110），Gmail / Chrome / Telegram / WakeUp 均用此值 |
| 行数 | **固定 3 行**（静态 XML 预置，`setViewVisibility` 控制显隐） |
| 列 | 课程名（左，超长省略号）· 时间（中）· 课室（右） |
| 溢出 | 标题右侧显示总门数；第 3 行下方显示「… 等 N 门」 |
| 空态 | `total == 0` → 标题「今日课程 · 周三」+ 居中「今日无课」 |
| 课室为空 | `location` 为可选字段，空则留空不占位 |
| 节次未启用 | 时间列退化为节次文本「第1-2节」 |
| 点击 | 整卡 → `/timetable`（R-10） |
| 高亮 | 进行中课程：课程名用 `Course.colorValue` 着色（其余行常规色） |

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
  "v": 1,
  "updatedAt": 1789000000000,
  "dateKey": "2026-09-10",
  "dayLabel": "周三",
  "total": 4,
  "isDark": false,
  "courses": [
    {
      "name": "高等数学",
      "time": "08:00-09:40",
      "room": "A-301",
      "state": "ongoing",
      "color": 4285098346
    }
  ]
}
```

| 字段 | 说明 |
|:---|:---|
| `v` | 格式版本，原生据此判兼容 |
| `updatedAt` | 写入时间戳（诊断用） |
| `dateKey` | `yyyy-MM-dd`；原生比对当前日期，**不一致视为过期**（跨天兜底） |
| `dayLabel` | 标题用，如「周三」 |
| `total` | 今日课程总数（含未展示的） |
| `isDark` | 亮暗模式 → 原生切换 `widget_bg_light` / `widget_bg_dark` |
| `courses[].state` | `ongoing` / `upcoming` / `past`（Flutter 侧算好） |
| `courses[].color` | `Course.colorValue`（ARGB int），仅 `ongoing` 使用 |

**存储**：SharedPreferences 文件名 `widget_store`，键 `widget.todayCourses`（v1 仅此一个键）。

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
