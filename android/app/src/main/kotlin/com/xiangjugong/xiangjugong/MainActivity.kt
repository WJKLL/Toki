package com.xiangjugong.xiangjugong

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
}
