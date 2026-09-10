// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetDataStore.kt ===
// 编号：S-26 内部件 · 桌面小组件数据仓（v1.51.0）
// 说明：Flutter 侧（WidgetBridgeService）把「今日课程」快照 JSON 写入本仓，
//   原生只读不改 —— 业务计算（今日筛选 / 时刻换算 / 状态判定）全部留在
//   Flutter，原生不做重算，刷新即重读快照。这样通知、应用内卡片与桌面卡片
//   共用同一份口径，不会漂移。
//   键空间见 PLAN_widget_v1.51.md §4；v1 仅 todayCourses 一个业务键。
package com.xiangjugong.xiangjugong.widget

import android.content.Context
import android.content.SharedPreferences

internal object WidgetDataStore {
    /** 单独的文件（不与应用设置混写；清数据/调试可整文件删除）。 */
    private const val FILE = "widget_store"

    /** 今日课程快照（JSON 文本；缺失 = 无数据）。 */
    const val KEY_TODAY_COURSES = "widget.todayCourses"

    /** 冷启动深链（小组件点击时原生写入；Flutter 读取一次后清空）。 */
    private const val KEY_PENDING_ROUTE = "widget.pendingRoute"

    fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun writeTodayCourses(context: Context, json: String) {
        prefs(context).edit().putString(KEY_TODAY_COURSES, json).apply()
    }

    fun readTodayCourses(context: Context): String? =
        prefs(context).getString(KEY_TODAY_COURSES, null)

    /** 清空快照（卡片转「今日无课」空态）。 */
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_TODAY_COURSES).apply()
    }

    /**
     * 记录一次「点击卡片」带来的目标路由（覆盖旧值 —— 只认最后一次点击）。
     * apply() 同步更新内存副本，同进程内随后读取即可见，冷启动时序安全。
     */
    fun writePendingRoute(context: Context, route: String) {
        prefs(context).edit().putString(KEY_PENDING_ROUTE, route).apply()
    }

    /** 取走待处理深链（**一次性**：读取后立即清空，避免重复跳转）。 */
    fun takePendingRoute(context: Context): String? {
        val p = prefs(context)
        val route = p.getString(KEY_PENDING_ROUTE, null) ?: return null
        p.edit().remove(KEY_PENDING_ROUTE).apply()
        return route.ifEmpty { null }
    }
}
