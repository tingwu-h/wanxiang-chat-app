plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须放在 Android 插件之后
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.deepseek_chat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.deepseek_chat"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = "1.3.2"
    }

    buildTypes {
        release {
            // 1.1.7 preserves the 1.1.6 signing identity for in-place upgrades.
            // Release tooling verifies the certificate hash before publication.
            // Do not rotate the key without an upgrade/data migration plan.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// 注意（踩过的坑）：
//  - 不要再写 id("kotlin-android")，AGP 9 起内置 Kotlin 支持；
//  - 旧的 android { kotlinOptions { jvmTarget = ... } } 在 AGP 9 已弃用并编译失败，
//    必须改用下面的 kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }；
//  - 也不要写 id("org.jetbrains.kotlin.android") 的 apply，同样会与内置 Kotlin 冲突。
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
