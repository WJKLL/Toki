// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetRender.kt ===
// 编号：S-26 内部件 · 卡片渲染（v1.51.0）
// 说明：把 Flutter 下发的快照渲染成 RemoteViews。三条兼容红线：
//   1. 只用 @RemotableViewMethod 白名单内的操作（setTextViewText /
//      setTextColor / setViewVisibility / setOnClickPendingIntent）；
//      **不使用** setBackgroundResource —— 它不是 remotable 方法，
//      反射调用会被 RemoteViews 校验拒绝并抛 ActionException。
//   2. 亮/暗两套底色改为「选布局资源」，不做主题引用解析；
//   3. 不做任何 Bitmap / Canvas 绘制，不引入 Adapter 或集合小组件。
package com.xiangjugong.xiangjugong.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar
import java.util.Locale
import com.xiangjugong.xiangjugong.MainActivity
import com.xiangjugong.xiangjugong.R

internal object WidgetRender {
    /** 点击卡片随 Intent 带给 MainActivity 的目标路由 extra 键。 */
    const val EXTRA_WIDGET_ROUTE = "widget_route"

    /** 点击卡片跳转目标（R-10 课表页；见 app_router.dart 的 /timetable）。 */
    private const val ROUTE_TIMETABLE = "/timetable"

    /** 卡面固定行数（与布局中预置的行容器数一致）。 */
    private const val MAX_ROWS = 3

    /** PendingIntent requestCode（固定：同一张卡只保留一个点击目标）。 */
    private const val REQUEST_CODE_CLICK = 1001

    private const val LIGHT_TEXT = 0xFF1A1A1A.toInt()
    private const val LIGHT_DIM = 0x99000000.toInt()
    private const val DARK_TEXT = 0xFFE8E8E8.toInt()
    private const val DARK_DIM = 0x99FFFFFF.toInt()

    /** 一行的四个 view id（容器 + 三列）。 */
    private class RowIds(
        val container: Int,
        val name: Int,
        val time: Int,
        val room: Int,
    )

    private val ROWS: Array<RowIds> = arrayOf(
        RowIds(R.id.widget_row1, R.id.widget_name1, R.id.widget_time1, R.id.widget_room1),
        RowIds(R.id.widget_row2, R.id.widget_name2, R.id.widget_time2, R.id.widget_room2),
        RowIds(R.id.widget_row3, R.id.widget_name3, R.id.widget_time3, R.id.widget_room3),
    )

    /**
     * 渲染卡片。快照为 null（从未写入 / 解析失败 / 版本不兼容）按「今日无课」处理 ——
     * 卡片永远有内容可画，不会出现系统级的空白 provider。
     */
    fun build(context: Context, snapshot: Snapshot?): RemoteViews {
        val dark = snapshot?.isDark == true
        val views = RemoteViews(
            context.packageName,
            // 亮暗切换通过「选布局」实现：两份布局仅底色 drawable 不同。
            if (dark) R.layout.widget_today_courses_dark else R.layout.widget_today_courses,
        )

        val textColor = if (dark) DARK_TEXT else LIGHT_TEXT
        val dimColor = if (dark) DARK_DIM else LIGHT_DIM
        val now = nowMinutes()

        // 标题：今日课程 · 周三
        val dayLabel = snapshot?.dayLabel.orEmpty()
        views.setTextViewText(
            R.id.widget_title,
            if (dayLabel.isEmpty()) "今日课程" else "今日课程 · $dayLabel",
        )
        views.setTextColor(R.id.widget_title, textColor)
        views.setTextColor(R.id.widget_count, dimColor)
        views.setTextColor(R.id.widget_more, dimColor)
        views.setTextColor(R.id.widget_empty, dimColor)

        val rows = snapshot?.courses.orEmpty()
        // 跨天兜底：Flutter 尚未写入今天的数据时，绝不把昨天的课当成今天显示。
        val total = if (snapshot != null && isStale(snapshot)) 0 else snapshot?.total ?: 0

        if (total <= 0 || rows.isEmpty()) {
            views.setTextViewText(R.id.widget_count, "")
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            views.setViewVisibility(R.id.widget_more, View.GONE)
            for (ids in ROWS) views.setViewVisibility(ids.container, View.GONE)
            applyClick(context, views)
            return views
        }

        views.setTextViewText(R.id.widget_count, "共 $total 门")
        views.setViewVisibility(R.id.widget_empty, View.GONE)

        for (i in ROWS.indices) {
            val ids = ROWS[i]
            val row = rows.getOrNull(i)
            if (row == null) {
                views.setViewVisibility(ids.container, View.GONE)
                continue
            }
            views.setViewVisibility(ids.container, View.VISIBLE)
            views.setTextViewText(ids.name, row.name)
            views.setTextViewText(ids.time, row.time)
            // 课室可为空（字段选填）：空串即留白，不写占位符。
            views.setTextViewText(ids.room, row.room)
            // 进行中的课程用课程自身的颜色着色。
            // 状态在渲染时**按当前墙钟重算**：课程闹钟 / 30 分钟周期刷新时 App
            // 可能并未运行，快照里写入时刻的 state 早已过期；节次时间缺失
            // （<0）才回落到 Flutter 侧的判定。
            val ongoing = stateOf(row, now) == WidgetSnapshotParser.STATE_ONGOING
            views.setTextColor(ids.name, if (ongoing) row.color else textColor)
            views.setTextColor(ids.time, dimColor)
            views.setTextColor(ids.room, dimColor)
        }

        val overflow = total - MAX_ROWS
        if (overflow > 0) {
            views.setViewVisibility(R.id.widget_more, View.VISIBLE)
            views.setTextViewText(R.id.widget_more, "… 等 $overflow 门")
        } else {
            views.setViewVisibility(R.id.widget_more, View.GONE)
        }

        applyClick(context, views)
        return views
    }

    /** 按当前墙钟重算某行状态；节次时间缺失时沿用 Flutter 侧写入的判定。 */
    private fun stateOf(row: CourseRow, now: Int): String {
        if (row.startMinutes < 0 || row.endMinutes <= row.startMinutes) return row.state
        return when {
            now >= row.endMinutes -> WidgetSnapshotParser.STATE_PAST
            now >= row.startMinutes -> WidgetSnapshotParser.STATE_ONGOING
            else -> WidgetSnapshotParser.STATE_UPCOMING
        }
    }

    /** 快照的日期键是否为「非今天」（跨天未写入 / 系统时钟回拨）。 */
    private fun isStale(snapshot: Snapshot): Boolean {
        if (snapshot.dateKey.isEmpty()) return false
        val c = Calendar.getInstance()
        val today = String.format(
            Locale.US,
            "%04d-%02d-%02d",
            c.get(Calendar.YEAR),
            c.get(Calendar.MONTH) + 1,
            c.get(Calendar.DAY_OF_MONTH),
        )
        return snapshot.dateKey != today
    }

    /** 当日 0 点起分钟数。 */
    private fun nowMinutes(): Int {
        val c = Calendar.getInstance()
        return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
    }

    /**
     * 整卡点击 → MainActivity，携带目标路由 extra。
     * 冷启动由 MainActivity.configureFlutterEngine 读取，热启动走 onNewIntent。
     */
    private fun applyClick(context: Context, views: RemoteViews) {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra(EXTRA_WIDGET_ROUTE, ROUTE_TIMETABLE)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            REQUEST_CODE_CLICK,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
    }
}
