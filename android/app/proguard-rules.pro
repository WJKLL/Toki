# v1.52.0（S-31 空间壁纸）：ONNX Runtime 保留规则
#
# 为什么必须加：
#   ONNX Runtime 的 JNI 层（libonnxruntime4j_jni.so）用【硬编码类名】查找 Java 类
#   （convertOrtValueToONNXValue → convertToTensorInfo → GetMethodID）。
#   Flutter 的 release 构建默认开启 R8，而 flutter_onnxruntime 1.8.5 **没有**
#   提供 consumer-rules.pro —— 于是这些类被重命名/裁剪，JNI 找不到 →
#   java_class == null → 整个进程 SIGABRT。
#
# 实测崩溃（2026-09-11 19:21:47，Redmi K90 / Android 17 / arm64）：
#   signal 6 (SIGABRT)
#   Abort message: 'JNI DETECTED ERROR IN APPLICATION: java_class == null
#       in call to GetMethodID
#       from boolean[] ai.onnxruntime.OrtSession.run(...)'
#   backtrace: #06 convertToTensorInfo+628
#              #07 convertOrtValueToONNXValue+436
#              #08 Java_ai_onnxruntime_OrtSession_run+836
#
# 代价：保留 ORT 的 Java 层（几百 KB dex），换取 JNI 能正常找到类。
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# 插件自身的 Kotlin 桥接类同样经 JNI / MethodChannel 反射调用，一并保留。
-keep class com.masicai.flutteronnxruntime.** { *; }
-dontwarn com.masicai.flutteronnxruntime.**
