package com.localdroid.project

/**
 * Starter project tuned for building inside Termux: plain Views (no Compose
 * compiler plugin), few dependencies, and aapt2 pointed at Termux's ARM build.
 */
object Templates {
    fun basicApp(name: String, pkg: String): Map<String, String> {
        val pkgPath = pkg.replace('.', '/')
        return mapOf(
            "settings.gradle.kts" to """
                pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
                dependencyResolutionManagement { repositories { google(); mavenCentral() } }
                rootProject.name = "$name"
                include(":app")
            """.trimIndent() + "\n",
            "build.gradle.kts" to """
                plugins {
                    id("com.android.application") version "8.5.2" apply false
                    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
                }
            """.trimIndent() + "\n",
            "gradle.properties" to """
                org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8
                org.gradle.daemon=false
                android.useAndroidX=true
                # Termux ships an ARM aapt2; the one from Maven is x86-only.
                android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2
            """.trimIndent() + "\n",
            "app/build.gradle.kts" to """
                plugins {
                    id("com.android.application")
                    id("org.jetbrains.kotlin.android")
                }
                android {
                    namespace = "$pkg"
                    compileSdk = 34
                    defaultConfig {
                        applicationId = "$pkg"
                        minSdk = 26
                        targetSdk = 34
                        versionCode = 1
                        versionName = "1.0"
                    }
                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
                    }
                    kotlinOptions { jvmTarget = "17" }
                    lint { checkReleaseBuilds = false; abortOnError = false }
                }
                dependencies {
                    implementation("androidx.appcompat:appcompat:1.7.0")
                    implementation("com.google.android.material:material:1.12.0")
                }
            """.trimIndent() + "\n",
            "app/src/main/AndroidManifest.xml" to """
                <?xml version="1.0" encoding="utf-8"?>
                <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                    <application
                        android:label="$name"
                        android:theme="@style/Theme.Material3.DayNight.NoActionBar">
                        <activity android:name=".MainActivity" android:exported="true">
                            <intent-filter>
                                <action android:name="android.intent.action.MAIN" />
                                <category android:name="android.intent.category.LAUNCHER" />
                            </intent-filter>
                        </activity>
                    </application>
                </manifest>
            """.trimIndent() + "\n",
            "app/src/main/java/$pkgPath/MainActivity.kt" to """
                package $pkg

                import android.os.Bundle
                import android.view.Gravity
                import android.widget.TextView
                import androidx.appcompat.app.AppCompatActivity

                class MainActivity : AppCompatActivity() {
                    override fun onCreate(savedInstanceState: Bundle?) {
                        super.onCreate(savedInstanceState)
                        setContentView(TextView(this).apply {
                            text = "Hello from $name"
                            textSize = 24f
                            gravity = Gravity.CENTER
                        })
                    }
                }
            """.trimIndent() + "\n",
            ".gitignore" to "build/\n.gradle/\nlocal.properties\n",
        )
    }
}
