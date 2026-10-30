pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9.3.1 + Kotlin 2.4.21 + Gradle 9.7.0 (wrapper) is the newest
    // mutually-verified combination per Kotlin's own compatibility matrix
    // (kotlinlang.org/docs/gradle-configure-project.html): KGP 2.4.21
    // supports AGP up to 9.3.1 and Gradle up to 9.7.0. AGP 9.5.0+Kotlin
    // 2.4.21 would likely also work but falls outside that tested matrix.
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
