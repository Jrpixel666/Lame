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
    // `android { ... }` syntax. Staying on the newest 8.x release (which
    // still defaults to the classic DSL) until those files are migrated.
    // Gradle is also capped at the 8.x line (see gradle-wrapper.properties):
    // AGP 8.13.2 calls a Gradle-internal API removed in Gradle 9.6. Kotlin
    // 2.4.21 is compatible across this whole range per kotlinlang.org's
    // own matrix.
    id("com.android.application") version "9.5.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
