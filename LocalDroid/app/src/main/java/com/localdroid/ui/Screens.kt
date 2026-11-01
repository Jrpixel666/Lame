package com.localdroid.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import kotlin.math.roundToInt

private enum class Tab(val label: String, val icon: String) {
    Models("Models", "▣"), Chat("Chat", "✎"), Code("Code", "{ }"), Build("Build", "▶")
}

@Composable
fun LocalDroidApp(vm: AppViewModel) {
    var tab by rememberSaveable { mutableStateOf(Tab.Models) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.refresh() }

    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t, onClick = { tab = t },
                        icon = { Text(t.icon, fontWeight = FontWeight.Bold) }, label = { Text(t.label) },
                    )
                }
            }
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            StatusBar(vm)
            when (tab) {
                Tab.Models -> ModelsScreen(vm)
                Tab.Chat -> ChatScreen(vm)
                Tab.Code -> CodeScreen(vm)
                Tab.Build -> BuildScreen(vm)
            }
        }
    }
}

@Composable
private fun StatusBar(vm: AppViewModel) {
    Surface(tonalElevation = 2.dp) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(vm.status, style = MaterialTheme.typography.labelMedium, modifier = Modifier.weight(1f), maxLines = 1)
            vm.currentProject?.let { Text("◆ ${it.name}", style = MaterialTheme.typography.labelMedium) }
        }
    }
    if (vm.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
}

// ---------------------------------------------------------------- Models
@Composable
private fun ModelsScreen(vm: AppViewModel) {
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { vm.importModel(it) }
    }
    LazyColumn(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Button(onClick = { picker.launch(arrayOf("*/*")) }, enabled = !vm.busy, modifier = Modifier.fillMaxWidth()) {
                Text("Import .gguf model")
            }
            Text(
                "Good coding models for phones: Qwen2.5-Coder 1.5B/3B/7B Instruct (Q4_K_M), " +
                    "DeepSeek-Coder 1.3B/6.7B. Rough RAM need ≈ file size + 1 GB.",
                style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 6.dp),
            )
        }
        if (vm.modelFiles.isEmpty()) item { Text("No models yet.") }
        items(vm.modelFiles, key = { it.path }) { f ->
            val loaded = vm.loadedModel == f.name
            ElevatedCard(Modifier.fillMaxWidth()) {
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(f.name, fontWeight = FontWeight.SemiBold)
                        Text("%.2f GB".format(f.length() / 1e9), style = MaterialTheme.typography.bodySmall)
                    }
                    if (loaded) AssistChip(onClick = {}, label = { Text("Loaded") })
                    else TextButton(onClick = { vm.loadModel(f) }, enabled = !vm.busy) { Text("Load") }
                    TextButton(onClick = { vm.deleteModel(f) }, enabled = !vm.busy) { Text("Delete") }
                }
            }
        }
        item { SettingsCard(vm) }
    }
}

@Composable
private fun SettingsCard(vm: AppViewModel) {
    val s = vm.settings
    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text("Engine settings (applied on next Load)", fontWeight = FontWeight.SemiBold)
            LabeledSlider("Context", s.contextSize.toFloat(), 1024f..16384f, "${s.contextSize}") {
                vm.settings = s.copy(contextSize = (it / 1024).roundToInt() * 1024)
            }
            LabeledSlider("Threads", s.threads.toFloat(), 1f..12f, "${s.threads}") {
                vm.settings = s.copy(threads = it.roundToInt())
            }
            LabeledSlider("Temperature", s.temperature, 0f..1.5f, "%.2f".format(s.temperature)) {
                vm.settings = s.copy(temperature = it)
            }
            LabeledSlider("Max reply tokens", s.maxTokens.toFloat(), 128f..4096f, "${s.maxTokens}") {
                vm.settings = s.copy(maxTokens = (it / 128).roundToInt() * 128)
            }
        }
    }
}

@Composable
private fun LabeledSlider(label: String, v: Float, range: ClosedFloatingPointRange<Float>, shown: String, set: (Float) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.width(120.dp), style = MaterialTheme.typography.bodySmall)
        Slider(v, set, valueRange = range, modifier = Modifier.weight(1f))
        Text(shown, Modifier.width(52.dp), style = MaterialTheme.typography.bodySmall)
    }
}

// ---------------------------------------------------------------- Chat
@Composable
private fun ChatScreen(vm: AppViewModel) {
    var input by rememberSaveable { mutableStateOf("") }
    var toast by remember { mutableStateOf<String?>(null) }
    val list = rememberLazyListState()
    LaunchedEffect(vm.chat.size, vm.chat.lastOrNull()?.content?.length) {
        if (vm.chat.isNotEmpty()) list.scrollToItem(vm.chat.lastIndex)
    }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Checkbox(vm.includeContext, { vm.includeContext = it })
            Text("Send project + open file as context", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
            TextButton(onClick = vm::clearChat) { Text("Clear") }
        }
        toast?.let { Text(it, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(horizontal = 12.dp)) }
        LazyColumn(Modifier.weight(1f).padding(horizontal = 8.dp), state = list, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            itemsIndexed(vm.chat) { i, m ->
                val mine = m.role == "user"
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = if (mine) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(10.dp)) {
                        SelectionContainer {
                            Text(m.content.ifEmpty { "…" }, fontFamily = if (mine) FontFamily.Default else FontFamily.Monospace, fontSize = 13.sp)
                        }
                        val isLast = i == vm.chat.lastIndex
                        if (!mine && !(isLast && vm.streaming)) {
                            val edits = remember(m.content) { vm.editsIn(m) }
                            if (edits.isNotEmpty()) {
                                Spacer(Modifier.height(6.dp))
                                Text(edits.joinToString("\n") { "• ${it.path}" }, style = MaterialTheme.typography.bodySmall)
                                FilledTonalButton(onClick = { toast = vm.applyEdits(edits) }, enabled = vm.currentProject != null) {
                                    Text(if (vm.currentProject != null) "Apply ${edits.size} file(s) to project" else "Open a project to apply")
                                }
                            }
                        }
                    }
                }
            }
        }
        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(input, { input = it }, Modifier.weight(1f), placeholder = { Text("Ask about Android code…") }, maxLines = 6)
            Spacer(Modifier.width(6.dp))
            if (vm.streaming) Button(onClick = vm::stopGeneration) { Text("Stop") }
            else Button(onClick = { vm.send(input); input = "" }, enabled = vm.loadedModel != null) { Text("Send") }
        }
    }
}

// ---------------------------------------------------------------- Code
@Composable
private fun CodeScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    if (!vm.hasStorageAccess()) {
        Column(Modifier.padding(16.dp)) {
            Text("LocalDroid keeps projects in /sdcard/LocalDroid so Termux can build them. Allow 'All files access' to continue.")
            Button(onClick = {
                ctx.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${ctx.packageName}")))
            }) { Text("Grant access") }
        }
        return
    }
    val p = vm.currentProject
    var msg by remember { mutableStateOf<String?>(null) }
    when {
        p == null -> ProjectPicker(vm)
        vm.openFile == null -> Column {
            Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { vm.currentProject = null }) { Text("← Projects") }
                Text(p.name, fontWeight = FontWeight.SemiBold)
            }
            LazyColumn(Modifier.fillMaxSize()) {
                items(vm.projects.sourceFiles(p), key = { it.path }) { f ->
                    Text(
                        f.relativeTo(p).path, fontFamily = FontFamily.Monospace, fontSize = 13.sp,
                        modifier = Modifier.fillMaxWidth().clickable { vm.open(f) }.padding(horizontal = 16.dp, vertical = 10.dp),
                    )
                    HorizontalDivider()
                }
            }
        }
        else -> Column(Modifier.fillMaxSize()) {
            Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { vm.openFile = null; msg = null }) { Text("← Files") }
                Text(vm.openFile!!.name, Modifier.weight(1f), maxLines = 1, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = { msg = vm.save() }) { Text("Save") }
            }
            msg?.let { Text(it, Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.labelSmall) }
            OutlinedTextField(
                vm.editorText, { vm.editorText = it },
                Modifier.fillMaxSize().padding(8.dp).horizontalScroll(rememberScrollState()).widthIn(min = 900.dp),
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, fontSize = 12.sp),
            )
        }
    }
}

@Composable
private fun ProjectPicker(vm: AppViewModel) {
    var name by rememberSaveable { mutableStateOf("MyApp") }
    var pkg by rememberSaveable { mutableStateOf("com.example.myapp") }
    var msg by remember { mutableStateOf<String?>(null) }
    LazyColumn(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            OutlinedCard {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("New project", fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(pkg, { pkg = it }, label = { Text("Package") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { msg = vm.createProject(name, pkg) }) { Text("Create") }
                    msg?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                }
            }
            Text("Projects in /sdcard/LocalDroid/projects", style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 8.dp))
        }
        items(vm.projectList, key = { it.path }) { p ->
            ElevatedCard(Modifier.fillMaxWidth().clickable { vm.openProject(p) }) {
                Text(p.name, Modifier.padding(16.dp), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

// ---------------------------------------------------------------- Build
@Composable
private fun BuildScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    val scroll = rememberScrollState()
    LaunchedEffect(vm.buildLog.length) { scroll.scrollTo(scroll.maxValue) }
    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { vm.refresh() }

    Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!vm.termux.isInstalled() || !vm.termux.hasPermission()) {
            OutlinedCard {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("One-time Termux setup", fontWeight = FontWeight.SemiBold)
                    Text("1. Install Termux from F-Droid or GitHub (not the Play Store).")
                    Text("2. In Termux run:  termux-setup-storage")
                    Text("3. In Termux run:  echo allow-external-apps=true >> ~/.termux/termux.properties")
                    Text("4. Grant the permission below, then tap 'Install toolchain'.")
                    Button(onClick = { permLauncher.launch("com.termux.permission.RUN_COMMAND") }, enabled = vm.termux.isInstalled()) {
                        Text("Grant Termux permission")
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedButton(onClick = vm::setupToolchain, enabled = !vm.building) { Text("Install toolchain") }
            OutlinedButton(onClick = vm::cleanProject, enabled = !vm.building && vm.currentProject != null) { Text("Clean") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Button(onClick = vm::buildProject, enabled = !vm.building && vm.currentProject != null) {
                Text(if (vm.building) "Running…" else "Build APK")
            }
            vm.lastApk?.let { apk ->
                Button(onClick = {
                    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", apk)
                    ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Text("Install APK") }
            }
            if (vm.lastBuildFailed && !vm.building) {
                FilledTonalButton(onClick = vm::fixBuildWithAi, enabled = vm.loadedModel != null && !vm.streaming) { Text("Fix with AI") }
            }
        }
        if (vm.building) LinearProgressIndicator(Modifier.fillMaxWidth())
        Surface(tonalElevation = 1.dp, modifier = Modifier.fillMaxSize()) {
            SelectionContainer {
                Text(
                    vm.buildLog.ifEmpty { "Build output appears here. First build downloads Gradle dependencies and can take 10+ minutes." },
                    fontFamily = FontFamily.Monospace, fontSize = 11.sp,
                    modifier = Modifier.verticalScroll(scroll).padding(8.dp),
                )
            }
        }
    }
}
