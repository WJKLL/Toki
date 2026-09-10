// === 文件: android/app/src/main/kotlin/com/xiangjugong/xiangjugong/widget/WidgetBridge.kt ===
// 编号：S-26 内部件 · MethodChannel 处理器（v1.51.0）
// 说明：通道 "xiangjugong/widget" 的原生端（Dart 侧见
//   lib/core/widget/widget_bridge_service.dart）。四个方法：
//     · writeTodayCourses —— 写入快照并立即刷新卡片；
//     · clear             —— 清空快照（卡片转空态）；
//     · getInitialRoute   —— 一次性取走「点击卡片」带来的启动深链；
//     · requestPin        —— 请求添加到桌面（不支持的桌面返回 supported=false）。
//   requestPinAppWidget 会启动系统 Activity，MethodChannel handler 默认运行在
//   主线程，满足其线程要求。
package com.xiangjugong.xiangjugong.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal object WidgetBridge {
    const val CHANNEL = "xiangjugong/widget"

    /** 原生 → Dart 的热启动跳转方法（App 已在运行时点击卡片）。 */
    private const val METHOD_OPEN_ROUTE = "openRoute"

    private var channel: MethodChannel? = null

    /** 注册通道（幂等：重复调用只保留一个 handler）。 */
    fun attach(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "writeTodayCourses" -> {
                        val json = call.argument<String>("json")
                        if (json == null) {
                            result.error("BAD_ARGS", "json 缺失", null)
                            return@setMethodCallHandler
                        }
                        WidgetDataStore.writeTodayCourses(appContext, json)
                        WidgetRefresh.refreshTodayCourses(appContext)
                        result.success(true)
                    }

                    "clear" -> {
                        WidgetDataStore.clear(appContext)
                        WidgetRefresh.refreshTodayCourses(appContext)
                        result.success(true)
                    }

                    "getInitialRoute" -> {
                        // 一次性：取走即清空，重复启动不会重复跳转。
                        result.success(WidgetDataStore.takePendingRoute(appContext))
                    }

                    "requestPin" -> result.success(requestPin(appContext))

                    else -> result.notImplemented()
                }
            }
        }
    }

    /** 热启动：把路由推给已在运行的 Flutter（Dart 侧 go_router 跳转）。 */
    fun pushRoute(route: String) {
        try {
            channel?.invokeMethod(METHOD_OPEN_ROUTE, route)
        } catch (_: Exception) {
            // 通道尚未建立（极早期点击）时忽略：路由已存入 pendingRoute，
            // 下次冷启动仍会生效。
        }
    }

    /** 请求把卡片添加到桌面；返回 {supported, launched} 供 Dart 侧降级提示。 */
    private fun requestPin(context: Context): Map<String, Any> {
        return try {
            val manager = AppWidgetManager.getInstance(context)
            if (manager == null || !manager.isRequestPinAppWidgetSupported) {
                mapOf("supported" to false, "launched" to false)
            } else {
                val provider = ComponentName(context, TodayCoursesWidgetProvider::class.java)
                val launched = manager.requestPinAppWidget(provider, null, null)
                mapOf("supported" to true, "launched" to launched)
            }
        } catch (_: Exception) {
            mapOf("supported" to false, "launched" to false)
        }
    }
}
