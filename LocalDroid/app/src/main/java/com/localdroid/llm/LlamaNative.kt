package com.localdroid.llm

/** Raw JNI surface. Text crosses the boundary as UTF-8 bytes. */
object LlamaNative {
    init {
        System.loadLibrary("localdroid")
        backendInit()
    }

    fun interface TokenCallback { fun onToken(bytes: ByteArray) }

    external fun backendInit()
    external fun load(path: String, nCtx: Int, nThreads: Int, temp: Float): Long
    external fun applyTemplate(handle: Long, roles: Array<String>, contents: Array<String>): ByteArray
    external fun generate(handle: Long, prompt: ByteArray, maxTokens: Int, cb: TokenCallback): Int
    external fun stop(handle: Long)
    external fun free(handle: Long)
}
