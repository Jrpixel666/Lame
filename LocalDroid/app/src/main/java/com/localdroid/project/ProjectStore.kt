package com.localdroid.project

import android.os.Environment
import java.io.File

/**
 * Projects live in shared storage (/sdcard/LocalDroid/projects) so both this app
 * and Termux can read and write them.
 */
class ProjectStore {
    val root: File = File(Environment.getExternalStorageDirectory(), "LocalDroid/projects")

    fun ensureRoot(): Boolean = root.exists() || root.mkdirs()

    fun list(): List<File> = root.listFiles { f -> f.isDirectory }?.sortedBy { it.name } ?: emptyList()

    /** Source files worth showing/sending to the model; skips build output. */
    fun sourceFiles(project: File): List<File> =
        project.walkTopDown()
            .onEnter { it.name !in setOf("build", ".gradle", ".idea", ".cxx") }
            .filter { it.isFile && it.extension in SOURCE_EXT }
            .sortedBy { it.relativeTo(project).path }
            .toList()

    fun create(name: String, pkg: String): File {
        val dir = File(root, name)
        require(!dir.exists()) { "Project '$name' already exists" }
        Templates.basicApp(name, pkg).forEach { (path, body) ->
            File(dir, path).apply { parentFile?.mkdirs(); writeText(body) }
        }
        return dir
    }

    /** Writes a file only if it resolves inside the project (blocks ../ escapes). */
    fun writeSafe(project: File, relPath: String, content: String): File {
        val target = File(project, relPath).canonicalFile
        require(target.path.startsWith(project.canonicalPath + File.separator)) { "Path escapes project: $relPath" }
        target.parentFile?.mkdirs()
        target.writeText(content)
        return target
    }

    companion object {
        val SOURCE_EXT = setOf("kt", "kts", "java", "xml", "gradle", "properties", "pro", "json", "md", "toml")
    }
}
