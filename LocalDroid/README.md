# LocalDroid

An offline Android-development assistant that runs on your phone. It loads GGUF models with llama.cpp, chats about your code, writes files straight into your project, and builds APKs on the device through Termux.

## Get the APK (no PC needed)

1. Create a new GitHub repository and upload everything in this folder (keep the `.github` folder).
2. Open the **Actions** tab. The *Build APK* workflow runs on every push; you can also start it with **Run workflow**.
3. When it finishes (about 10–15 minutes, mostly compiling llama.cpp), open the run and download **LocalDroid-apk**.
4. Unzip it on your phone and install `app-release.apk`. Allow installs from your browser or file manager if asked.

The APK is arm64-only, which covers essentially every Android phone from the last several years. It needs Android 11 or newer.

## First run

**Models tab**
- Download a GGUF file on your phone (for example from Hugging Face), then tap **Import .gguf model** and pick it.
- Tap **Load**. Good starting points:
  - Qwen2.5-Coder-1.5B-Instruct Q4_K_M: about 1 GB, fast, works on most phones.
  - Qwen2.5-Coder-7B-Instruct Q4_K_M: about 4.7 GB, much smarter, needs 8 GB+ RAM.
- Settings for context size, threads and temperature apply the next time you load a model.

**Code tab**
- Grant "All files access". Projects live in `/sdcard/LocalDroid/projects` so Termux can see them.
- Create a project from the starter template, or copy an existing one into that folder.
- Tap any file to open it in the editor.

**Chat tab**
- With "Send project + open file as context" ticked, the model sees your file list and the open file.
- When the reply contains complete files, an **Apply N file(s) to project** button appears. Tapping it writes them into the open project.

**Build tab** (one-time setup)
1. Install **Termux from F-Droid or GitHub**. The Play Store version is outdated and won't work.
2. In Termux run: `termux-setup-storage`
3. In Termux run: `echo allow-external-apps=true >> ~/.termux/termux.properties`
4. Back in LocalDroid, tap **Grant Termux permission**, then **Install toolchain**. This downloads about 1.5 GB (JDK 17, Gradle, aapt2, Android SDK 34) and takes a while.

After that, **Build APK** compiles the open project. When it succeeds, **Install APK** appears. When it fails, **Fix with AI** sends the errors to the Chat tab so the model can propose fixes.

## Limits worth knowing

- **On-device builds are the fragile part.** Gradle in Termux works, but it is slow (the first build downloads dependencies and can take 10+ minutes) and memory-hungry. Unload the model before building on phones with less than 8 GB RAM.
- The starter template uses plain Views rather than Jetpack Compose, because Compose builds are much heavier on a phone. Compose projects can work, but expect slower builds.
- Small models (1–3B) are good at single files and explanations. For multi-file changes, use 7B if your phone can handle it.
- Each message re-sends the whole conversation, so very long chats slow down. Tap **Clear** to start fresh.

## Project layout

```
app/src/main/cpp/            llama.cpp (pinned b4600, fetched at build time) + JNI bridge
app/src/main/java/com/localdroid/
  llm/      LlamaNative (JNI), LlmEngine (streaming), ModelStore (GGUF import)
  project/  ProjectStore, starter Templates, CodeBlocks (parses "// FILE:" blocks)
  build/    TermuxBridge (RUN_COMMAND + log tailing), BuildScripts
  ui/       AppViewModel, Compose screens
.github/workflows/build.yml  CI that produces the APK
```

To use newer model architectures, bump `GIT_TAG` in `app/src/main/cpp/CMakeLists.txt` to a newer llama.cpp release. Check the JNI calls still compile, since llama.cpp's API changes now and then.
