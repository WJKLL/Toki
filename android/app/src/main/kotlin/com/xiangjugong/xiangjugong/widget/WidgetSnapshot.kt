// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetSnapshot.kt ===
// 编号：S-26 内部件 · 快照载荷模型与解析（v1.51.1 焦点卡契约）
// 说明：Flutter 侧 buildTodaySnapshot() 产出的 JSON 载荷（见
//   lib/core/widget/widget_snapshot.dart）在此解析为原生只读模型。
//   契约 v2 与鸿蒙版服务卡片（TodayCourseCard.ets）字段一一对应：
//   weekText / curTag / curName / curRoom / nextLine / remainText。
//   解析失败或版本不匹配 → 返回 null，渲染层按「暂无课程」空态处理，
//   绝不抛异常（桌面卡片崩溃会留下系统级的僵尸 provider）。
package com.xiangjugong.xiangjugong.widget

import org.json.JSONException
import org.json.JSONObject

/** 今日课程焦点卡快照（只读）。 */
internal data class Snapshot(
    val dateKey: String,
    val weekText: String,
    /** 当前课程 / 下一节课 / 全天课程结束（空 = 不显示标签行）。 */
    val curTag: String,
    val curName: String,
    val curRoom: String,
    val nextLine: String,
    /** 剩余 N 分钟（仅上课中；空 = 隐藏）。 */
    val remainText: String,
    /** 写入时的亮暗模式；v1.51.3 起渲染**不再依据它**（见 WidgetRender.isSystemNight）。 */
    val isDark: Boolean,
)

internal object WidgetSnapshotParser {
    /** 唯一支持的载荷版本；不匹配即判为不兼容（旧版 App 写的新数据等）。 */
    private const val SUPPORTED_VERSION = 2

    fun parse(json: String?): Snapshot? {
        if (json.isNullOrBlank()) return null
        return try {
            val o = JSONObject(json)
            if (o.optInt("v", 0) != SUPPORTED_VERSION) return null
            Snapshot(
                dateKey = o.optString("dateKey"),
                weekText = o.optString("weekText"),
                curTag = o.optString("curTag"),
                curName = o.optString("curName"),
                curRoom = o.optString("curRoom"),
                nextLine = o.optString("nextLine"),
                remainText = o.optString("remainText"),
                isDark = o.optBoolean("isDark", false),
            )
        } catch (_: JSONException) {
            null
        }
    }
}
