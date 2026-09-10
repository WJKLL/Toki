// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetSnapshot.kt ===
// 编号：S-26 内部件 · 快照载荷模型与解析（v1.51.0）
// 说明：Flutter 侧 buildTodaySnapshot() 产出的 JSON 载荷（见
//   lib/core/widget/widget_snapshot.dart）在此解析为原生只读模型。
//   解析失败 / 版本不认识 → 返回 null，渲染层按「今日无课」空态处理，
//   绝不抛异常（桌面卡片崩溃会留下系统级的僵尸 provider）。
package com.xiangjugong.xiangjugong.widget

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** 今日课程单行（课程名 → 时间 → 课室）。 */
internal data class CourseRow(
    val name: String,
    val time: String,
    val room: String,
    /** ongoing / upcoming / past（Flutter 写入时刻的判定，渲染时会按当前时刻重算）。 */
    val state: String,
    /** ARGB 课程色（仅 ongoing 行使用）。 */
    val color: Int,
    /** 该课整段开始分钟（当日 0 点起）；-1 = 节次时间缺失。 */
    val startMinutes: Int,
    /** 该课整段结束分钟；-1 = 节次时间缺失。 */
    val endMinutes: Int,
)

/** 今日课程快照。 */
internal data class Snapshot(
    val dateKey: String,
    val dayLabel: String,
    val total: Int,
    val isDark: Boolean,
    val courses: List<CourseRow>,
)

internal object WidgetSnapshotParser {
    /** 唯一支持的载荷版本；不匹配即判为不兼容（旧版 App 写的新数据等）。 */
    private const val SUPPORTED_VERSION = 1

    fun parse(json: String?): Snapshot? {
        if (json.isNullOrBlank()) return null
        return try {
            val o = JSONObject(json)
            if (o.optInt("v", 0) != SUPPORTED_VERSION) return null
            val arr: JSONArray = o.optJSONArray("courses") ?: JSONArray()
            val rows = ArrayList<CourseRow>(arr.length())
            for (i in 0 until arr.length()) {
                val c: JSONObject = arr.optJSONObject(i) ?: continue
                rows.add(
                    CourseRow(
                        name = c.optString("name"),
                        time = c.optString("time"),
                        room = c.optString("room"),
                        state = c.optString("state", STATE_UPCOMING),
                        color = c.optInt("color", 0),
                        startMinutes = c.optInt("startMinutes", -1),
                        endMinutes = c.optInt("endMinutes", -1),
                    ),
                )
            }
            Snapshot(
                dateKey = o.optString("dateKey"),
                dayLabel = o.optString("dayLabel"),
                total = o.optInt("total", rows.size),
                isDark = o.optBoolean("isDark", false),
                courses = rows,
            )
        } catch (_: JSONException) {
            null
        }
    }

    const val STATE_ONGOING = "ongoing"
    const val STATE_UPCOMING = "upcoming"
    const val STATE_PAST = "past"
}
