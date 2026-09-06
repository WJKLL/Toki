// v1.36.0 课程提醒 · 广播接收器（到点弹通知 / 开机重排闹钟 / 触发诊断）
// v1.40.1(C 方案):课程闹钟携带结束参数 → 到点广播**原生直启倒计时前台服务**,
//   常驻通知不再依赖 Dart 进程(App 被杀/后台也出现);下课 endAt 到服务自动停。
package com.xiangjugong.xiangjugong.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 诊断：任何广播到达立即记录（区分「闹钟没触发」vs「系统没拉起进程」）。
        ReminderScheduler.recordReceiverHit(context, intent.action ?: "null")
        ReminderScheduler.ensureChannels(context)
        if (Intent.ACTION_BOOT_COMPLETED == intent.action ||
            "android.intent.action.MY_PACKAGE_REPLACED" == intent.action ||
            "android.intent.action.TIME_SET" == intent.action
        ) {
            // 开机 / 应用更新 / 时间变更：从持久化清单重排（系统重启清空闹钟）。
            ReminderScheduler.restoreAlarms(context)
            return
        }
        val title = intent.getStringExtra(ReminderScheduler.EXTRA_TITLE) ?: "课程提醒"
        val body = intent.getStringExtra(ReminderScheduler.EXTRA_BODY) ?: ""
        val id = intent.getIntExtra(ReminderScheduler.EXTRA_ID, 0)
        ReminderScheduler.showAlertNotification(context, title, body, id)
        // v1.40.1：到点即上课开始 → 原生直启倒计时常驻（App 进程不在也出现）。
        val endAt = intent.getLongExtra(ReminderScheduler.EXTRA_END_AT, 0L)
        if (endAt > System.currentTimeMillis()) {
            try {
                CountdownForegroundService.start(
                    context,
                    title,
                    intent.getStringExtra(ReminderScheduler.EXTRA_END_TEXT) ?: "",
                    endAt,
                    intent.getIntExtra(ReminderScheduler.EXTRA_TOTAL, 45).coerceAtLeast(1),
                )
            } catch (_: Exception) {
                // Android 12+ 后台 FGS 启动限制（精确闹钟/闹钟档豁免之外
                // 的降级链可能被拦）：静默 —— App 打开后常驻由桥按需重建。
            }
        }
    }
}
