// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetRender.kt ===
// 编号：S-26 内部件 · 卡片渲染（v1.51.4 焦点卡 · 单布局）
// 说明：把 Flutter 下发的焦点卡快照渲染成 RemoteViews。四条兼容红线：
//   1. 只用 @RemotableViewMethod 白名单内的操作（setTextViewText /
//      setViewVisibility / setOnClickPendingIntent）；
//      **不使用** setBackgroundResource（非 remotable，反射调用会被 RemoteViews
//      校验拒绝），**也不使用 setBackgroundColor / setTextColor** —— 运行时下发的
//      字面量色值会与系统 uiMode 脱钩，导致卡片在系统切换深色后不变色（v1.51.4 教训）；
//   2. 全卡**单一布局**，亮暗由 @color 资源 + values-night 自动解析（不做 ?attr
//      主题属性引用）；
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

    // 配色不再由本文件下发：全部走 res/values/colors.xml 与 values-night 的
    // @color 资源，由资源系统按 uiMode 自动解析。

    /**
     * 渲染卡片。快照为 null（从未写入 / 解析失败 / 版本不兼容）或已跨天时
     * 按「暂无课程」渲染 —— 卡片永远有内容可画，不会出现空白 provider。
     */
    fun build(context: Context, snapshot: Snapshot?): RemoteViews {
        // v1.51.4：全卡**只有一份布局**，亮暗完全由 @color 资源 + values-night
        //   自动切换（见 res/values/colors.xml 的说明），渲染器不再做任何配色判断、
        //   也不再下发 setTextColor。
        //   为什么放弃 v1.51.3 的「按系统 uiMode 选两套布局」：系统切换深色模式时
        //   **不会通知 AppWidgetProvider**，没有任何触发源会来调用本方法 —— 结果
        //   仍表现为「必须打开 App 才变色」。而 @color 资源是 Launcher 重新 inflate
        //   布局时由资源系统解析的，不需要任何触发源。
        val views = RemoteViews(context.packageName, R.layout.widget_today_courses)

        // 跨天兜底：Flutter 尚未写入今天的数据时，绝不把昨天的课当成今天显示。
        val s = if (snapshot != null && !isStale(snapshot)) snapshot else null

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
