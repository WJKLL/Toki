// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetRender.kt ===
// 编号：S-26 内部件 · 卡片渲染（v1.51.1 焦点卡）
// 说明：把 Flutter 下发的焦点卡快照渲染成 RemoteViews。四条兼容红线：
//   1. 只用 @RemotableViewMethod 白名单内的操作（setTextViewText /
//      setTextColor / setViewVisibility / setOnClickPendingIntent）；
//      **不使用** setBackgroundResource（非 remotable，反射调用会被
//      RemoteViews 校验拒绝），本次也不再使用 setBackgroundColor；
//   2. 亮/暗两套底色改为「选布局资源」，不做主题引用解析；
//   3. 不做任何 Bitmap / Canvas 绘制，不引入 Adapter 或集合小组件；
//   4. 空字段用 GONE 塌陷（对齐鸿蒙版 `if (x.length > 0)` 的写法），
//      整块内容靠根的 gravity=center_vertical 居中，不留固定空行。
package com.xiangjugong.xiangjugong.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.xiangjugong.xiangjugong.MainActivity
import com.xiangjugong.xiangjugong.R
import java.util.Calendar
import java.util.Locale

internal object WidgetRender {
    /** 点击卡片随 Intent 带给 MainActivity 的目标路由 extra 键。 */
    const val EXTRA_WIDGET_ROUTE = "widget_route"

    /** 点击卡片跳转目标（R-10 课表页；见 app_router.dart 的 /timetable）。 */
    private const val ROUTE_TIMETABLE = "/timetable"

    /** PendingIntent requestCode（固定：同一张卡只保留一个点击目标）。 */
    private const val REQUEST_CODE_CLICK = 1001

    // 配色取自 docs/notification-mockup.html 的视觉语言（与 Miuix 主题一致）。
    private const val LIGHT_PRIMARY = 0xFF111111.toInt()
    private const val LIGHT_SECONDARY = 0xFF8A8A92.toInt()
    private const val DARK_PRIMARY = 0xFFFFFFFF.toInt()
    private const val DARK_SECONDARY = 0xFF9E9E9E.toInt()

    /** 强调色（Miuix / HyperOS 强调蓝；深浅色共用）。 */
    private const val ACCENT = 0xFF3482FF.toInt()

    /**
     * 渲染卡片。快照为 null（从未写入 / 解析失败 / 版本不兼容）或已跨天时
     * 按「暂无课程」渲染 —— 卡片永远有内容可画，不会出现空白 provider。
     */
    fun build(context: Context, snapshot: Snapshot?): RemoteViews {
        val dark = snapshot?.isDark == true
        val views = RemoteViews(
            context.packageName,
            // 亮暗切换通过「选布局」实现：两份布局仅底色 drawable 与默认文字色不同。
            if (dark) R.layout.widget_today_courses_dark else R.layout.widget_today_courses,
        )

        val primary = if (dark) DARK_PRIMARY else LIGHT_PRIMARY
        val secondary = if (dark) DARK_SECONDARY else LIGHT_SECONDARY

        // 跨天兜底：Flutter 尚未写入今天的数据时，绝不把昨天的课当成今天显示。
        val s = if (snapshot != null && !isStale(snapshot)) snapshot else null

        // ── 固定配色（每帧都要下发；不依赖布局里的默认值）──
        views.setTextColor(R.id.widget_title, primary)
        views.setTextColor(R.id.widget_week, secondary)
        views.setTextColor(R.id.widget_tag, ACCENT)
        views.setTextColor(R.id.widget_remain, secondary)
        views.setTextColor(R.id.widget_name, primary)
        views.setTextColor(R.id.widget_room, secondary)
        views.setTextColor(R.id.widget_next, secondary)

        // ── 标题行：周次副标题（空则塌陷）──
        val weekText = s?.weekText.orEmpty()
        views.setTextViewText(R.id.widget_week, weekText)
        views.setViewVisibility(
            R.id.widget_week,
            if (weekText.isEmpty()) View.GONE else View.VISIBLE,
        )

        // ── 标签行：当前课程 / 下一节课（强调色）+ 右侧剩余分钟 ──
        val tag = s?.curTag.orEmpty()
        views.setTextViewText(R.id.widget_tag, tag)
        views.setViewVisibility(
            R.id.widget_tag,
            if (tag.isEmpty()) View.GONE else View.VISIBLE,
        )
        val remain = s?.remainText.orEmpty()
        views.setTextViewText(R.id.widget_remain, remain)
        views.setViewVisibility(
            R.id.widget_remain,
            if (remain.isEmpty()) View.GONE else View.VISIBLE,
        )

        // ── 课程名（大字焦点）；无数据时给「暂无课程」──
        val name = s?.curName.orEmpty().ifEmpty { "暂无课程" }
        views.setTextViewText(R.id.widget_name, name)

        // ── 教室行（选填，空则塌陷）──
        val room = s?.curRoom.orEmpty()
        views.setTextViewText(R.id.widget_room, room)
        views.setViewVisibility(
            R.id.widget_room,
            if (room.isEmpty()) View.GONE else View.VISIBLE,
        )

        // ── 下一节行（无数据时提示去添加）──
        val nextLine = if (s == null) "点击卡片去添加" else s.nextLine
        views.setTextViewText(R.id.widget_next, nextLine)

        applyClick(context, views)
        return views
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
