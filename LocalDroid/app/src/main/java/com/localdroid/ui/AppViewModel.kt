package com.localdroid.ui

import android.app.Application
import android.net.Uri
import android.os.Environment
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.localdroid.build.BuildEvent
import com.localdroid.build.BuildScripts
import com.localdroid.build.TermuxBridge
import com.localdroid.llm.ChatMessage
import com.localdroid.llm.EngineSettings
import com.localdroid.llm.LlmEngine
import com.localdroid.llm.ModelStore
import com.localdroid.project.CodeBlocks
import com.localdroid.project.FileEdit
import com.localdroid.project.ProjectStore
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.io.File

class AppViewModel(app: Application) : AndroidViewModel(app) {
    val engine = LlmEngine()
    val models = ModelStore(app)
    val projects = ProjectStore()
    val termux = TermuxBridge(app)

    // ---- model state
    var settings by mutableStateOf(EngineSettings())
    var modelFiles by mutableStateOf(models.list())
    var loadedModel by mutableStateOf<String?>(null)
    var status by mutableStateOf("No model loaded")
    var busy by mutableStateOf(false)

    // ---- chat state
    val chat = mutableStateListOf<ChatMessage>()
    var streaming by mutableStateOf(false)
    var includeContext by mutableStateOf(true)
    private var genJob: Job? = null

    // ---- project state
    var projectList by mutableStateOf<List<File>>(emptyList())
    var currentProject by mutableStateOf<File?>(null)
    var openFile by mutableStateOf<File?>(null)
    var editorText by mutableStateOf("")

    // ---- build state
    var buildLog by mutableStateOf("")
    var building by mutableStateOf(false)
    var lastApk by mutableStateOf<File?>(null)
    var lastBuildFailed by mutableStateOf(false)

    fun hasStorageAccess() = Environment.isExternalStorageManager()

    fun refresh() {
        modelFiles = models.list()
        if (hasStorageAccess()) { projects.ensureRoot(); projectList = projects.list() }
    }

    // ================= models
    fun importModel(uri: Uri) = viewModelScope.launch {
        busy = true
        try {
            models.import(uri) { p -> status = "Copying model… ${(p * 100).toInt()}%" }
            status = "Model imported"; refresh()
        } catch (e: Exception) { status = "Import failed: ${e.message}" }
        busy = false
    }

    fun loadModel(f: File) = viewModelScope.launch {
        busy = true; status = "Loading ${f.name}…"
        val ok = engine.load(f.path, settings)
        loadedModel = if (ok) f.name else null
        status = if (ok) "Loaded ${f.name}" else "Failed to load ${f.name} (not enough RAM or unsupported model)"
        busy = false
    }

    fun deleteModel(f: File) {
        if (engine.loadedPath == f.path) { engine.release(); loadedModel = null; status = "No model loaded" }
        models.delete(f); refresh()
    }

    // ================= chat
    private fun systemPrompt(): String = buildString {
        appendLine("You are LocalDroid, an expert Android engineer working on a phone, offline.")
        appendLine("Write modern Kotlin. Prefer AndroidX, Material 3 and View-based UI unless asked otherwise.")
        appendLine("When you create or change a file, output the COMPLETE file in a fenced code block whose first line is a path header:")
        appendLine("  // FILE: app/src/main/java/com/example/MainActivity.kt   (Kotlin/Java/Gradle)")
        appendLine("  <!-- FILE: app/src/main/res/layout/activity_main.xml -->   (XML)")
        appendLine("  # FILE: gradle.properties   (properties)")
        appendLine("Paths are relative to the project root. Never output partial files in FILE blocks. Be concise.")
        val p = currentProject
        if (includeContext && p != null) {
            appendLine()
            appendLine("Current project: ${p.name}. Files:")
            projects.sourceFiles(p).forEach { appendLine("- ${it.relativeTo(p).path}") }
            openFile?.let { f ->
                appendLine()
                appendLine("Currently open file ${f.relativeTo(p).path}:")
                appendLine("```")
                appendLine(editorText.take(12_000))
                appendLine("```")
            }
        }
    }

    fun send(text: String) {
        if (text.isBlank() || streaming) return
        if (!engine.isLoaded) { status = "Load a model first"; return }
        chat += ChatMessage("user", text.trim())
        val history = listOf(ChatMessage("system", systemPrompt())) + chat.toList()
        chat += ChatMessage("assistant", "")
        streaming = true
        genJob = viewModelScope.launch {
            val sb = StringBuilder()
            try {
                engine.chat(history, settings.maxTokens).collect { piece ->
                    sb.append(piece)
                    chat[chat.lastIndex] = ChatMessage("assistant", sb.toString())
                }
            } catch (e: Exception) {
                chat[chat.lastIndex] = ChatMessage("assistant", sb.toString() + "\n\n[error: ${e.message}]")
            }
            streaming = false
        }
    }

    fun stopGeneration() { engine.stop(); genJob?.cancel(); streaming = false }
    fun clearChat() { stopGeneration(); chat.clear() }

    fun editsIn(msg: ChatMessage): List<FileEdit> = CodeBlocks.extract(msg.content)

    fun applyEdits(edits: List<FileEdit>): String {
        val p = currentProject ?: return "Open a project first"
        return try {
            edits.forEach { projects.writeSafe(p, it.path, it.content) }
            openFile?.let { f -> if (f.exists()) editorText = f.readText() }
            "Wrote ${edits.size} file(s) to ${p.name}"
        } catch (e: Exception) { "Apply failed: ${e.message}" }
    }

    // ================= projects
    fun createProject(name: String, pkg: String): String = try {
        currentProject = projects.create(name.trim(), pkg.trim()); openFile = null; refresh()
        "Created ${name.trim()}"
    } catch (e: Exception) { e.message ?: "Failed" }

    fun openProject(p: File) { currentProject = p; openFile = null; lastApk = File(p, "${p.name}-debug.apk").takeIf { it.exists() } }

    fun open(f: File) { openFile = f; editorText = f.readText() }

    fun save(): String {
        val f = openFile ?: return "No file open"
        f.writeText(editorText); return "Saved ${f.name}"
    }

    // ================= builds
    private fun logFile(name: String) =
        File(Environment.getExternalStorageDirectory(), "LocalDroid/logs/$name.log")

    private fun runScript(script: String, label: String, onDone: (Int) -> Unit = {}) {
        if (!termux.isInstalled()) { buildLog = "Termux is not installed. See the Build tab for setup steps."; return }
        if (!termux.hasPermission()) { buildLog = "Grant the Termux 'Run commands' permission first."; return }
        building = true; buildLog = ""
        val log = termux.run(script, logFile(label), "LocalDroid: $label")
        viewModelScope.launch {
            termux.tail(log).collect { ev ->
                when (ev) {
                    is BuildEvent.Output -> buildLog = (buildLog + ev.text).takeLast(200_000)
                    is BuildEvent.Finished -> {
                        buildLog += "\n[exit ${ev.exitCode}]"
                        building = false
                        onDone(ev.exitCode)
                    }
                }
            }
        }
    }

    fun setupToolchain() = runScript(BuildScripts.SETUP, "setup")

    fun buildProject() {
        val p = currentProject ?: run { buildLog = "Open a project first"; return }
        openFile?.let { save() }
        runScript(BuildScripts.build(p), "build-${p.name}") { code ->
            lastBuildFailed = code != 0
            lastApk = File(p, "${p.name}-debug.apk").takeIf { code == 0 && it.exists() }
        }
    }

    fun cleanProject() { currentProject?.let { runScript(BuildScripts.clean(it), "clean-${it.name}") } }

    /** Sends the build errors to the model and asks for fixed files. */
    fun fixBuildWithAi() {
        send("The Gradle build failed. Fix it and output every changed file in full.\n\n```\n" +
            BuildScripts.errorExcerpt(buildLog) + "\n```")
    }

    override fun onCleared() { engine.release() }
}
