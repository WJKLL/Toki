package com.xiangjugong.xiangjugong

import android.Manifest
import android.app.AlarmManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.xiangjugong.xiangjugong.reminder.CountdownForegroundService
import com.xiangjugong.xiangjugong.reminder.ReminderScheduler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // v1.9.0（S-13 导出）：与 LogExportService 的 MethodChannel 名一致。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xiangjugong/log")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                        if (sourcePath == null || fileName == null) {
                            result.error("BAD_ARGS", "sourcePath/fileName 缺失", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val saved = saveToDownloads(sourcePath, fileName, mimeType)
                            result.success(saved)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // v1.16.5（S-16 高刷）：与 RefreshRateController 的 MethodChannel 名一致。
        //   按帧活动动态请求/释放最高刷新率，规避安卓 15+ Frame Rate Velocity
        //   把刷新率压到 60Hz 导致的 fps 锁死（骁龙 8 Elite / 安卓 17）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xiangjugong/refresh")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHigh" -> {
                        setPreferredRefreshRate(high = true)
                        result.success(null)
                    }
                    "setNormal" -> {
                        setPreferredRefreshRate(high = false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // v1.36.0（课程提醒）：到点提醒(AlarmManager) + 倒计时常驻圆环(前台服务)。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xiangjugong/reminder")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureChannels" -> {
                        ReminderScheduler.ensureChannels(applicationContext)
                        result.success(null)
                    }
                    "getDiagnostics" -> {
                        val c = applicationContext
                        result.success(
                            mapOf(
                                "lastFireAt" to ReminderScheduler.lastFireAt(c),
                                "lastFireTitle" to ReminderScheduler.lastFireTitle(c),
                                "lastReceiverAt" to ReminderScheduler.lastReceiverAt(c),
                                "lastReceiverAction" to ReminderScheduler.lastReceiverAction(c),
                            ),
                        )
                    }
                    "scheduleAlert" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val at = call.argument<Long>("atMillis") ?: 0L
                        ReminderScheduler.scheduleAlert(
                            applicationContext,
                            at,
                            id,
                            call.argument<String>("title") ?: "课程提醒",
                            call.argument<String>("body") ?: "",
                            // v1.40.1(C 方案):课程闹钟携带常驻参数(到点原生直启
                            // 倒计时);Number 兼容 Integer/Long 解码(小值坑)。
                            endAtMillis = call.argument<Number>("endAtMillis")?.toLong() ?: 0L,
                            totalMinutes = call.argument<Number>("totalMinutes")?.toInt() ?: 0,
                            endText = call.argument<String>("endText"),
                        )
                        result.success(null)
                    }
                    "cancelAlert" -> {
                        ReminderScheduler.cancelAlert(
                            applicationContext,
                            call.argument<Int>("id") ?: 0,
                        )
                        result.success(null)
                    }
                    "cancelAllAlarms" -> {
                        ReminderScheduler.clearAll(applicationContext)
                        result.success(null)
                    }
                    "startCountdown" -> {
                        try {
                            val c = applicationContext
                            CountdownForegroundService.start(
                                c,
                                call.argument<String>("title") ?: "课程进行中",
                                call.argument<String>("endText") ?: "",
                                call.argument<Long>("endAtMillis") ?: 0L,
                                call.argument<Int>("totalMinutes") ?: 1,
                                // Dart int(值 ≤ int32)在 Android 解码为 Integer ——
                                // 必须按 Int 读取再转 Long，否则 ClassCastException。
                                call.argument<Int>("updateIntervalMs")?.toLong() ?: 60_000L,
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("TokiReminder", "startCountdown 失败", e)
                            result.error("FGS_START_FAIL", e.message, null)
                        }
                    }
                    "stopCountdown" -> {
                        try {
                            CountdownForegroundService.stop(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("TokiReminder", "stopCountdown 失败", e)
                            result.error("FGS_STOP_FAIL", e.message, null)
                        }
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(
                                    this,
                                    Manifest.permission.POST_NOTIFICATIONS,
                                ) != PackageManager.PERMISSION_GRANTED
                            ) {
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    1001,
                                )
                            }
                        }
                        result.success(true)
                    }
                    "canScheduleExactAlarm" -> {
                        val am = getSystemService(AlarmManager::class.java)
                        result.success(am.canScheduleExactAlarms())
                    }
                    "openExactAlarmSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                android.net.Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    "openBatteryOptimizationSettings" -> {
                        // 引导「省电策略无限制」：系统不静默允许，须跳设置用户手动开。
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    android.net.Uri.parse("package:$packageName"),
                                ),
                            )
                        } catch (_: Exception) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS,
                                ),
                            )
                        }
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // v1.40.0(图片长按保存):工具图保存到相册(Pictures/Toki,免权限)。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xiangjugong/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                        if (bytes == null || fileName == null) {
                            result.error("BAD_ARGS", "bytes/fileName 缺失", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveImageToGallery(bytes, fileName))
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 请求最高刷新率模式（high=true，取 supportedModes 中 refreshRate 最大者），
     * 或释放（high=false，preferredDisplayModeId=0 → 交还系统 LTPO 自适应省电）。
     * minSdk=30（Android 11），preferredDisplayModeId 与 supportedModes 均可用。
     */
    private fun setPreferredRefreshRate(high: Boolean) {
        val d = display ?: return
        val modeId = if (high) {
            d.supportedModes.maxByOrNull { it.refreshRate }?.modeId ?: return
        } else {
            0
        }
        val params = window.attributes
        params.preferredDisplayModeId = modeId
        window.attributes = params
    }

    /** MediaStore 写入公共 Download/（Android 10+ 免存储权限；RELATIVE_PATH + IS_PENDING）。 */
    private fun saveToDownloads(sourcePath: String, fileName: String, mimeType: String): String {
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore 插入失败")
        resolver.openOutputStream(uri)?.use { out ->
            FileInputStream(File(sourcePath)).use { input -> input.copyTo(out) }
        } ?: throw IllegalStateException("打开输出流失败")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return fileName
    }

    /**
     * 图片字节写入系统相册 Pictures/Toki（Android 10+ 免存储权限：
     * RELATIVE_PATH + IS_PENDING；minSdk 30 恒走 Q+ 分支）。
     * 返回落盘位置描述（Dart 侧 toast 用）。
     */
    private fun saveImageToGallery(bytes: ByteArray, fileName: String): String {
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, imageMimeFor(fileName))
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/Toki",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("相册写入失败")
        resolver.openOutputStream(uri)?.use { out -> out.write(bytes) }
            ?: throw IllegalStateException("打开输出流失败")
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return "Pictures/Toki/$fileName"
    }

    private fun imageMimeFor(fileName: String): String =
        when (fileName.substringAfterLast('.', "").lowercase()) {
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "bmp" -> "image/bmp"
            else -> "image/*"
        }
}
