import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// v1.35.2：正式发布签名 —— 读 android/key.properties（gitignore，不入库）。
// 开源镜像（无 key.properties）自动回退 debug 签名，仍可构建。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.xiangjugong.xiangjugong"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.xiangjugong.xiangjugong"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 目标平台 Android 11–17（API 30–35，PROJECT_SPEC §1）。
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // v1.52.0（S-31 空间壁纸）：限制 ABI —— flutter_onnxruntime 默认会把
        // 全部 ABI 的 ONNX Runtime 原生库打进 APK（4 个 ABI 合计约 50 MB），
        // 实测体积从 74.7 → 138.3 MB。只保留 arm64-v8a 后回落。
        // 本项目 minSdk=30，arm64 已是绝对主流；若日后要兼顾 32 位设备，
        // 应改用 flutter build apk --split-per-abi 出多包，而不是解开本限制。
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // v1.35.2：正式签名（key.properties 存在时），否则回退 debug。
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    // v1.52.0（S-31 空间壁纸）：flutter_onnxruntime 会把【全部 ABI】的 ONNX Runtime
    // 原生库打进 APK —— 实测 arm64-v8a 19.2 MB + armeabi-v7a 13.9 MB +
    // x86_64 23.0 MB ≈ 56 MB，导致体积 74.7 → 138.3 MB。
    // defaultConfig.ndk.abiFilters 会被 Flutter Gradle Plugin 覆盖（实测无效），
    // 故在 packaging 层剔除；Flutter 自身的库由 --target-platform 控制。
    packaging {
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
