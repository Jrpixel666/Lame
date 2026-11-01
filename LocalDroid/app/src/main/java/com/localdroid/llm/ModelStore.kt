package com.localdroid.llm

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * GGUF files are copied into app storage once, so llama.cpp can mmap a real path
 * (content:// URIs from the file picker can't be mmapped).
 */
class ModelStore(private val ctx: Context) {
    val dir: File = File(ctx.getExternalFilesDir(null), "models").apply { mkdirs() }

    fun list(): List<File> =
        dir.listFiles { f -> f.extension.equals("gguf", true) }?.sortedBy { it.name } ?: emptyList()

    suspend fun import(uri: Uri, onProgress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        var name = "model.gguf"
        var size = -1L
        ctx.contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }?.let { size = c.getLong(it) }
            }
        }
        require(name.endsWith(".gguf", true)) { "Pick a .gguf model file" }
        val out = File(dir, name)
        val tmp = File(dir, "$name.part")
        ctx.contentResolver.openInputStream(uri)!!.use { input ->
            tmp.outputStream().use { o ->
                val buf = ByteArray(1 shl 20)
                var done = 0L
                while (true) {
                    val n = input.read(buf); if (n < 0) break
                    o.write(buf, 0, n); done += n
                    if (size > 0) onProgress(done.toFloat() / size)
                }
            }
        }
        tmp.renameTo(out)
        out
    }

    fun delete(f: File) = f.delete()
}
