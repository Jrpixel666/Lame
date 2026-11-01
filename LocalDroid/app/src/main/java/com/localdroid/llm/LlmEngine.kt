package com.localdroid.llm

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

data class ChatMessage(val role: String, val content: String)

data class EngineSettings(
    val contextSize: Int = 4096,
    val threads: Int = (Runtime.getRuntime().availableProcessors() - 2).coerceIn(2, 8),
    val temperature: Float = 0.2f,
    val maxTokens: Int = 1024,
)

/** Owns one loaded model. All native calls are serialised through [lock]. */
class LlmEngine {
    private var handle = 0L
    private val lock = Mutex()
    var loadedPath: String? = null
        private set

    suspend fun load(path: String, s: EngineSettings): Boolean = withContext(Dispatchers.IO) {
        lock.withLock {
            if (handle != 0L) LlamaNative.free(handle)
            handle = LlamaNative.load(path, s.contextSize, s.threads, s.temperature)
            loadedPath = if (handle != 0L) path else null
            handle != 0L
        }
    }

    val isLoaded get() = handle != 0L

    fun stop() { if (handle != 0L) LlamaNative.stop(handle) }

    /** Streams the reply as text chunks. */
    fun chat(history: List<ChatMessage>, maxTokens: Int): Flow<String> = callbackFlow {
        val job = launch(Dispatchers.Default) {
            lock.withLock {
                check(handle != 0L) { "No model loaded" }
                val prompt = LlamaNative.applyTemplate(
                    handle,
                    history.map { it.role }.toTypedArray(),
                    history.map { it.content }.toTypedArray(),
                )
                LlamaNative.generate(handle, prompt, maxTokens) { bytes ->
                    trySend(String(bytes, Charsets.UTF_8))
                }
            }
            close()
        }
        awaitClose { stop(); job.cancel() }
    }.flowOn(Dispatchers.Default)

    fun release() {
        if (handle != 0L) { LlamaNative.free(handle); handle = 0L; loadedPath = null }
    }
}
