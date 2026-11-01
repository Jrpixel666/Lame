package com.localdroid.build

import java.io.File

/** Shell scripts run inside Termux. */
object BuildScripts {

    /**
     * Installs JDK 17, Gradle, an ARM aapt2 and the Android 34 SDK platform.
     * Takes a while and ~1.5 GB the first time; re-running is safe.
     */
    val SETUP = """
        set -e
        echo '== Installing packages =='
        yes | pkg update -y
        pkg install -y openjdk-17 gradle aapt2 wget unzip which

        SDK=${'$'}HOME/android-sdk
        if [ ! -d "${'$'}SDK/cmdline-tools/latest" ]; then
          echo '== Downloading Android command-line tools =='
          mkdir -p "${'$'}SDK/cmdline-tools"
          cd "${'$'}SDK/cmdline-tools"
          wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O tools.zip
          unzip -q tools.zip && rm tools.zip && mv cmdline-tools latest
        fi

        echo '== Installing SDK platform and build-tools =='
        export ANDROID_HOME=${'$'}SDK
        yes | "${'$'}SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="${'$'}SDK" --licenses > /dev/null || true
        "${'$'}SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="${'$'}SDK" "platforms;android-34" "build-tools;34.0.0"

        # The SDK's aapt2 is x86; swap in Termux's ARM build.
        cp "${'$'}PREFIX/bin/aapt2" "${'$'}SDK/build-tools/34.0.0/aapt2"

        grep -q ANDROID_HOME ~/.bashrc 2>/dev/null || echo "export ANDROID_HOME=${'$'}SDK" >> ~/.bashrc
        echo '== Setup complete =='
        java -version
        gradle --version | head -3
    """.trimIndent()

    /** Builds a debug APK and copies it next to the project as <name>-debug.apk. */
    fun build(project: File): String = """
        export ANDROID_HOME=${'$'}HOME/android-sdk
        cd '${project.path}'
        echo "sdk.dir=${'$'}ANDROID_HOME" > local.properties
        echo '== gradle assembleDebug =='
        gradle --no-daemon --console=plain assembleDebug
        APK=${'$'}(ls app/build/outputs/apk/debug/*.apk | head -1)
        cp "${'$'}APK" '${project.path}/${project.name}-debug.apk'
        echo "== APK ready: ${project.path}/${project.name}-debug.apk =="
    """.trimIndent()

    fun clean(project: File): String = """
        cd '${project.path}'
        rm -rf app/build build .gradle
        echo '== cleaned =='
    """.trimIndent()

    /** Last ~60 lines with errors in them, for handing to the model. */
    fun errorExcerpt(log: String): String {
        val lines = log.lines()
        val hits = lines.indices.filter { i ->
            val l = lines[i]
            l.startsWith("e: ") || "error:" in l || "FAILED" in l || "What went wrong" in l || "Exception" in l
        }
        if (hits.isEmpty()) return lines.takeLast(60).joinToString("\n")
        val keep = hits.flatMap { (it - 2..it + 6) }.filter { it in lines.indices }.distinct().sorted()
        return keep.takeLast(60).joinToString("\n") { lines[it] }
    }
}
