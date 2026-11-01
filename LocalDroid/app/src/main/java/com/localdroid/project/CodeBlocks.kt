package com.localdroid.project

/**
 * Pulls file edits out of a model reply. The system prompt asks the model to
 * write each file as a fenced block whose first line is `// FILE: path/to/File.kt`
 * (or `<!-- FILE: ... -->` for XML, `# FILE:` for properties).
 */
data class FileEdit(val path: String, val content: String)

object CodeBlocks {
    private val fence = Regex("```[\\w.+-]*\\s*\\n(.*?)```", RegexOption.DOT_MATCHES_ALL)
    private val header = Regex("^\\s*(?://|#|<!--)\\s*FILE:\\s*([^\\s>]+?)\\s*(?:-->)?\\s*$")

    fun extract(reply: String): List<FileEdit> = fence.findAll(reply).mapNotNull { m ->
        val body = m.groupValues[1]
        val first = body.lineSequence().firstOrNull() ?: return@mapNotNull null
        val path = header.find(first)?.groupValues?.get(1) ?: return@mapNotNull null
        FileEdit(path.trimStart('/'), body.substringAfter('\n').trimEnd() + "\n")
    }.toList()
}
