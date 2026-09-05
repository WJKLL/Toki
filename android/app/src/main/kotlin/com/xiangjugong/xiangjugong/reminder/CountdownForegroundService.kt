// v1.36.0 课程提醒 · 倒计时前台服务（常驻通知，**自治更新**）
// 设计：start 记录 endAt(total 分钟) → 服务内部按墙钟每 updateIntervalMs
//   自推算「剩余 N 分钟（P%）」更新自身通知 —— **不依赖 Dart/调用方生命周期**：
//   页面关闭、UI 任务被杀（进程被前台服务保活）都持续更新；endAt 到 → 自动停。
// 折叠/展开均为系统标准纯文字（适配 MIUI 系统通知样式，深浅自动）。
package com.xiangjugong.xiangjugong.reminder

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.xiangjugong.xiangjugong.R
import kotlin.math.ceil
import kotlin.math.roundToInt

class CountdownForegroundService : Service() {
    companion object {
        const val NOTIF_ID = 9001
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"
        const val EXTRA_TITLE = "title"
        const val EXTRA_END = "end" // 「第 3-4 节 · 11:30 结束」
        const val EXTRA_END_AT = "endAt" // epoch ms
        const val EXTRA_TOTAL = "totalMinutes"
        const val EXTRA_INTERVAL = "updateIntervalMs"

        fun start(
            context: Context,
            title: String,
            endText: String,
            endAtMillis: Long,
            totalMinutes: Int,
            updateIntervalMs: Long = 60_000L,
        ) {
            val i = Intent(context, CountdownForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_END, endText)
                putExtra(EXTRA_END_AT, endAtMillis)
                putExtra(EXTRA_TOTAL, totalMinutes.coerceAtLeast(1))
                putExtra(EXTRA_INTERVAL, updateIntervalMs.coerceAtLeast(5_000L))
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            val i = Intent(context, CountdownForegroundService::class.java).apply { action = ACTION_STOP }
            context.startService(i)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            refreshAndSchedule()
        }
    }

    private var title = "课程进行中"
    private var endText = ""
    private var endAt = 0L
    private var totalMinutes = 1
    private var updateIntervalMs = 60_000L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                title = intent.getStringExtra(EXTRA_TITLE) ?: title
                endText = intent.getStringExtra(EXTRA_END) ?: ""
                endAt = intent.getLongExtra(EXTRA_END_AT, System.currentTimeMillis() + 60_000L)
                totalMinutes = intent.getIntExtra(EXTRA_TOTAL, 1).coerceAtLeast(1)
                updateIntervalMs = intent.getLongExtra(EXTRA_INTERVAL, 60_000L).coerceAtLeast(5_000L)
                handler.removeCallbacks(tick)
                val left = leftMinutes()
                // Android 14+（targetSdk 34）必须三参 startForeground 显式类型，
                // 否则抛 MissingForegroundServiceTypeException → 通知不出现。
                startForeground(
                    NOTIF_ID,
                    buildNotif(left, percentOf(left)),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
                scheduleTick()
            }
            ACTION_STOP -> stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun scheduleTick() {
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, updateIntervalMs)
    }

    /** 按墙钟自治推算 + 更新自身通知（endAt 到 → 自动停）。 */
    private fun refreshAndSchedule() {
        val left = leftMinutes()
        if (left <= 0) {
            stopSelf()
            return
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        nm.notify(NOTIF_ID, buildNotif(left, percentOf(left)))
        scheduleTick()
    }

    private fun leftMinutes(): Int {
        val remain = endAt - System.currentTimeMillis()
        return if (remain <= 0) 0 else ceil(remain / 60_000.0).toInt()
    }

    private fun percentOf(left: Int): Int =
        (left * 100.0 / totalMinutes).roundToInt().coerceIn(0, 100)

    /** 正文：剩余 N 分钟（P%）· 结束时间 */
    private fun buildText(left: Int, percent: Int): String = buildString {
        append("剩余 $left 分钟（$percent%）")
        if (endText.isNotEmpty()) append(" · $endText")
    }

    private fun buildNotif(left: Int, percent: Int): Notification {
        ReminderScheduler.ensureChannels(this)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, ReminderScheduler.CHANNEL_COUNTDOWN)
            .setSmallIcon(R.drawable.ic_stat_toki)
            .setContentTitle(title)
            .setContentText(buildText(left, percent))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .build()
    }
}
