// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/TodayCoursesWidgetProvider.kt ===
// 编号：S-26 内部件 · 今日课程卡 Provider（v1.51.0）
// 说明：AppWidgetProvider —— 系统的 onUpdate 入口。**必须是 public**：
//   Manifest 以类名注册，系统按名反射实例化（Kotlin internal 会改写类名）。
//   onUpdate 只做「读快照 → 渲染」，不含业务计算。
package com.xiangjugong.xiangjugong.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

class TodayCoursesWidgetProvider : AppWidgetProvider() {
    /**
     * 系统在以下时机调用：卡片被添加、updatePeriodMillis 到期（约 30 分钟）、
     * ACTION_APPWIDGET_UPDATE 广播（本应用主动触发）。
     */
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val views = WidgetRender.build(
            context,
            WidgetSnapshotParser.parse(WidgetDataStore.readTodayCourses(context)),
        )
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }
}
