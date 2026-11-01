package com.localdroid.build

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.io.File

/**
 * Runs shell scripts inside Termux through its RUN_COMMAND intent.
 * Output goes to a log file in shared storage, which we tail.
 *
 * One-time Termux setup (the app shows these steps):
 *   1. Install Termux from F-Droid or GitHub (the Play Store build is outdated).
 *   2. In Termux: termux-setup-storage
 *   3. In Termux: echo "allow-external-apps=true" >> ~/.termux/termux.properties
 *   4. Grant LocalDroid the "Run commands in Termux environment" permission.
 */
class TermuxBridge(private val ctx: Context) {

    fun isInstalled(): Boolean = try {
        ctx.packageManager.getPackageInfo(TERMUX_PKG, 0); true
    } catch (_: PackageManager.NameNotFoundException) { false }

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(ctx, PERMISSION) == PackageManager.PERMISSION_GRANTED

    /** Starts [script] in the background and returns the log file it writes to. */
    fun run(script: String, logFile: File, label: String): File {
        logFile.parentFile?.mkdirs()
        logFile.writeText("")
        val doneMarker = File(logFile.path + ".done").apply { delete() }
        // Exit code is written to the marker so we know when (and how) it finished.
        val wrapped = """
            set -o pipefail
            {
            $script
            } > '${logFile.path}' 2>&1
            echo ${'$'}? > '${doneMarker.path}'
        """.trimIndent()

        val intent = Intent().apply {
            setClassName(TERMUX_PKG, "com.termux.app.RunCommandService")
            action = "com.termux.RUN_COMMAND"
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-lc", wrapped))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home")
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", label)
        }
        ctx.startForegroundService(intent)
        return logFile
    }

    /** Emits the growing log, then a final [BuildEvent.Finished] with the exit code. */
    fun tail(logFile: File): Flow<BuildEvent> = flow {
        val done = File(logFile.path + ".done")
        var offset = 0L
        while (true) {
            if (logFile.length() > offset) {
                logFile.inputStream().use { s ->
                    s.skip(offset)
                    val chunk = s.readBytes()
                    offset += chunk.size
                    emit(BuildEvent.Output(String(chunk, Charsets.UTF_8)))
                }
            }
            if (done.exists() && logFile.length() == offset) {
                emit(BuildEvent.Finished(done.readText().trim().toIntOrNull() ?: -1))
                return@flow
            }
            delay(400)
        }
    }.flowOn(Dispatchers.IO)

    companion object {
        const val TERMUX_PKG = "com.termux"
        const val PERMISSION = "com.termux.permission.RUN_COMMAND"
    }
}

sealed interface BuildEvent {
    data class Output(val text: String) : BuildEvent
    data class Finished(val exitCode: Int) : BuildEvent
}
