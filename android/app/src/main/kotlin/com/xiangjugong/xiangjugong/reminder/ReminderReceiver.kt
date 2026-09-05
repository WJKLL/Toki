// v1.36.0 课程提醒 · 广播接收器（到点弹通知 / 开机重排闹钟 / 触发诊断）
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
    }
}
