// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetRefresh.kt ===
// 编号：S-26 内部件 · 卡片刷新入口（v1.51.0）
// 说明：所有刷新路径（Flutter 写入、课程闹钟到点、开机重排、系统周期）
//   最终都汇聚到这里：读快照 → 渲染 → 推给桌面。
//   没有已添加的实例时直接返回（getAppWidgetIds 为空），零成本。
package com.xiangjugong.xiangjugong.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

internal object WidgetRefresh {
    /** 重读快照并刷新桌面上全部「今日课程」实例。 */
    fun refreshTodayCourses(context: Context) {
        val manager = AppWidgetManager.getInstance(context) ?: return
        val component = ComponentName(context, TodayCoursesWidgetProvider::class.java)
        val ids = manager.getAppWidgetIds(component)
        if (ids == null || ids.isEmpty()) return
        val views = WidgetRender.build(
            context,
            WidgetSnapshotParser.parse(WidgetDataStore.readTodayCourses(context)),
        )
        manager.updateAppWidget(ids, views)
    }
}
