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
    // AGP 9.x defaults to a new `android {}` DSL (android.newDsl=true) that
    // this project's build.gradle.kts files don't use yet — AGP 9.3.1
    // failed a real CI build with "Script compilation errors" on the old
    // `android { ... kotlinOptions { ... } }` syntax. Staying on the
    // newest 8.x release (which still defaults to the classic DSL) until
    // those files are migrated. Kotlin 2.4.21 + Gradle 9.7.0 (wrapper)
    // are unaffected and stay as the newest mutually-compatible versions.
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
