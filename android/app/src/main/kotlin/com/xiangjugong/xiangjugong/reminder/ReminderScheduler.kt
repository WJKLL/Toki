// v1.36.0 课程提醒 · 调度器（AlarmManager 精确闹钟 + 通知 + 闹钟清单持久化）
// 说明：
//   - 到点提醒 = setExactAndAllowWhileIdle（系统到点唤醒，进程不在也弹）；
//   - **闹钟清单持久化**：每次排/取消同步写入 SharedPreferences ——
//     开机(BOOT_COMPLETED)/每日兜底 时 [restoreAlarms] 原样重排（系统重启会
//     清空全部闹钟，必须重建）；用户手动 force-stop 是系统冻结、不可恢复
//     （任何 App 同理，引导用户勿用「停止运行」）。
//   - 通知渠道：course_alert(到点) / course_countdown(常驻静默)。
package com.xiangjugong.xiangjugong.reminder

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import androidx.core.app.NotificationCompat
import com.xiangjugong.xiangjugong.R
import org.json.JSONArray
import org.json.JSONObject

object ReminderScheduler {
    const val CHANNEL_ALERT = "course_alert"
    const val CHANNEL_COUNTDOWN = "course_countdown"
    const val EXTRA_TITLE = "xtitle"
    const val EXTRA_BODY = "xbody"
    const val EXTRA_ID = "xid"
    // v1.40.1(C 方案):闹钟携带常驻参数 —— 到点广播直接原生启动倒计时前台
    // 服务(不依赖 Dart 进程),App 被杀也能出现常驻通知。
    const val EXTRA_END_AT = "endAtMillis"
    const val EXTRA_TOTAL = "totalMinutes"
    const val EXTRA_END_TEXT = "endText"
    const val ACTION_REMINDER = "com.xiangjugong.xiangjugong.REMINDER"

    /** 诊断：Receiver 最近一次被系统广播唤醒的时间（任何广播到达即记）。 */
    fun recordReceiverHit(context: Context, action: String) {
        prefs(context).edit()
            .putLong(KEY_LAST_RECEIVER_AT, System.currentTimeMillis())
            .putString(KEY_LAST_RECEIVER_ACTION, action)
            .apply()
    }

    fun lastReceiverAt(context: Context): Long =
        prefs(context).getLong(KEY_LAST_RECEIVER_AT, 0L)

    fun lastReceiverAction(context: Context): String =
        prefs(context).getString(KEY_LAST_RECEIVER_ACTION, "") ?: ""

    private const val PREFS = "course_reminder"
    private const val KEY_ALARMS = "alarms"
    private const val KEY_LAST_FIRE_AT = "last_fire_at"
    private const val KEY_LAST_FIRE_TITLE = "last_fire_title"
    private const val KEY_LAST_RECEIVER_AT = "last_receiver_at"
    private const val KEY_LAST_RECEIVER_ACTION = "last_receiver_action"

    /** 诊断：最近一次到点通知实际触发时间（Receiver 弹通知时写入）。 */
    fun lastFireAt(context: Context): Long =
        prefs(context).getLong(KEY_LAST_FIRE_AT, 0L)

    /** 诊断：最近一次到点通知标题。 */
    fun lastFireTitle(context: Context): String =
        prefs(context).getString(KEY_LAST_FIRE_TITLE, "") ?: ""

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 幂等建通知渠道（重复调用安全）。
     * 到点 DEFAULT；常驻 DEFAULT + 仅首次提醒（保证可见——部分 ROM 会把
     * LOW 渠道默认折叠/隐藏，导致常驻通知「彻底不出现」）。 */
    fun ensureChannels(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ALERT, "课程提醒", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "到点课程开始提醒"
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_COUNTDOWN, "课程倒计时", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "课程进行中常驻通知"
                setShowBadge(false)
            },
        )
    }

    /** 到点广播 PendingIntent（id 稳定 → 重复排同 id = 覆盖去重）。
     * extra 不参与 PendingIntent 匹配(cancel 可只按 id 命中)。 */
    private fun alarmIntent(
        context: Context,
        id: Int,
        title: String?,
        body: String?,
        endAtMillis: Long = 0L,
        totalMinutes: Int = 0,
        endText: String? = null,
    ): PendingIntent {
        val i = Intent(context, ReminderReceiver::class.java).apply {
            action = "$ACTION_REMINDER.$id"
            if (title != null) putExtra(EXTRA_TITLE, title)
            if (body != null) putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_ID, id)
            if (endAtMillis > 0L) {
                putExtra(EXTRA_END_AT, endAtMillis)
                putExtra(EXTRA_TOTAL, totalMinutes.coerceAtLeast(1))
                if (endText != null) putExtra(EXTRA_END_TEXT, endText)
            }
        }
        return PendingIntent.getBroadcast(
            context, id, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * 排一个「到点提醒」精确闹钟，并把条目写入持久化清单（供开机/兜底重排）。
     * 精确闹钟权限不可用（部分系统/Android 14 默认拒绝且豁免失效）→ 降级
     * 普通 set（仍会触发，只是不保证精确到秒/Doze 内可能延迟）。
     * [endAtMillis]/[totalMinutes]/[endText] 仅课程闹钟携带（v1.40.1：到点
     * 后原生直启倒计时常驻，App 不在也出现）。
     */
    fun scheduleAlert(
        context: Context,
        atMillis: Long,
        id: Int,
        title: String,
        body: String,
        endAtMillis: Long = 0L,
        totalMinutes: Int = 0,
        endText: String? = null,
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        setExactSafe(
            am,
            atMillis,
            alarmIntent(context, id, title, body, endAtMillis, totalMinutes, endText),
        )
        // 持久化条目（upsert）。
        val list = readAlarmList(context)
        val next = JSONArray()
        var found = false
        for (i in 0 until list.length()) {
            val o = list.optJSONObject(i) ?: continue
            if (o.optInt("id") == id) {
                next.put(alarmJson(id, atMillis, title, body, endAtMillis, totalMinutes, endText))
                found = true
            } else {
                next.put(o)
            }
        }
        if (!found) {
            next.put(alarmJson(id, atMillis, title, body, endAtMillis, totalMinutes, endText))
        }
        prefs(context).edit().putString(KEY_ALARMS, next.toString()).apply()
    }

    private fun alarmJson(
        id: Int,
        at: Long,
        title: String,
        body: String,
        endAtMillis: Long,
        totalMinutes: Int,
        endText: String?,
    ): JSONObject = JSONObject().apply {
        put("id", id)
        put("at", at)
        put("title", title)
        put("body", body)
        if (endAtMillis > 0L) {
            put("endAtMillis", endAtMillis)
            put("totalMinutes", totalMinutes.coerceAtLeast(1))
            if (endText != null) put("endText", endText)
        }
    }

    /**
     * 闹钟调度链（逐级降级，尽量精确）：
     * 1) setAlarmClock —— 系统「闹钟」级调度，MIUI/各 ROM 对它的清理策略最宽松
     *    （与系统闹钟同待遇，杀后台后最可能保留）；
     * 2) setExactAndAllowWhileIdle —— 精确且 Doze 可用；
     * 3) set —— 普通（权限全失时兜底，仍会触发但可能延迟）。
     */
    private fun setExactSafe(am: AlarmManager, atMillis: Long, pi: PendingIntent) {
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(atMillis, null), pi)
            return
        } catch (_: SecurityException) {
            // 无精确闹钟权限 → 降级。
        }
        try {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
        } catch (_: SecurityException) {
            am.set(AlarmManager.RTC_WAKEUP, atMillis, pi)
        }
    }

    /** 取消一个到点闹钟（并移出持久化清单）。 */
    fun cancelAlert(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(alarmIntent(context, id, null, null))
        val list = readAlarmList(context)
        val next = JSONArray()
        for (i in 0 until list.length()) {
            val o = list.optJSONObject(i) ?: continue
            if (o.optInt("id") != id) next.put(o)
        }
        prefs(context).edit().putString(KEY_ALARMS, next.toString()).apply()
    }

    private fun readAlarmList(context: Context): JSONArray {
        val raw = prefs(context).getString(KEY_ALARMS, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    /** 清空全部课程闹钟与持久化清单（课程提醒总开关关闭时调用）。 */
    fun clearAll(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val list = readAlarmList(context)
        for (i in 0 until list.length()) {
            val o = list.optJSONObject(i) ?: continue
            am.cancel(alarmIntent(context, o.optInt("id"), null, null))
        }
        prefs(context).edit().remove(KEY_ALARMS).apply()
    }

    /** 开机/每日兜底：从持久化清单原样重排全部闹钟（系统重启清空后重建）。 */
    fun restoreAlarms(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val list = readAlarmList(context)
        for (i in 0 until list.length()) {
            val o = list.optJSONObject(i) ?: continue
            val at = o.optLong("at")
            if (at <= System.currentTimeMillis()) continue // 已过期忽略。
            setExactSafe(
                am,
                at,
                alarmIntent(
                    context,
                    o.optInt("id"),
                    o.optString("title"),
                    o.optString("body"),
                    o.optLong("endAtMillis", 0L),
                    o.optInt("totalMinutes", 0),
                    if (o.has("endText")) o.optString("endText") else null,
                ),
            )
        }
    }

    /** 到点（ReminderReceiver 调）：弹提醒通知，点击回应用；并记录触发诊断。 */
    fun showAlertNotification(
        context: Context,
        title: String,
        body: String,
        id: Int,
    ) {
        ensureChannels(context)
        prefs(context).edit()
            .putLong(KEY_LAST_FIRE_AT, System.currentTimeMillis())
            .putString(KEY_LAST_FIRE_TITLE, title)
            .apply()
        val contentIntent = PendingIntent.getActivity(
            context,
            id,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ALERT)
            .setSmallIcon(R.drawable.ic_stat_toki)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, notification)
    }
}
