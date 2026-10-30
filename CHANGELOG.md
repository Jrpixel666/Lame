# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-10-30

### Added
- **Development screen**: a second, independent chat screen alongside Chat — its own history,
  its own coding/debugging-focused system prompt, same model and local inference underneath.
- **Hugging Face search**: search huggingface.co for GGUF model repos from inside the app and add
  a quantization straight to the Model Library.
- **Device scan**: detects this device's RAM, CPU cores and free storage, and flags which catalog
  models will actually fit, without any native plugin.
- **SD card / external storage support**: Settings → Storage now lists every place models can be
  saved — internal app storage, plus (on Android) shared or removable storage such as an SD
  card — and lets you pick where new downloads go. Models already downloaded elsewhere keep working.
- Local Android development scripts (`scripts/check_android_dev_env.sh`,
  `setup_android_dev.sh`, `run_android_local.sh`) and full GitHub support: CI (analyze/test/build
  on every PR), a release workflow that publishes a GitHub Release with a single universal Android
  APK plus Linux/Windows/macOS builds, Dependabot, issue/PR templates, `LICENSE`, `SECURITY.md`,
  `CONTRIBUTING.md`.

### Changed
- Release builds now ship a **single universal APK** (all ABIs bundled) instead of three
  ABI-split files, for simple fully-offline installs with no app store involved.
- Upgraded every dependency to its latest version, each checked against its own changelog/docs
  for breaking changes first — most notably `llamadart` (0.6.10 → 0.17.0, the inference engine)
  and `file_picker` (8.1.7 → 13.3.0, whose API changed and required code updates). Android
  toolchain settled at AGP 8.13.2 / Kotlin 2.4.21 / Gradle 8.14.6 after CI caught three
  independent build breaks from going further (see 1.2.1 below and `CONTRIBUTING.md`).

### Fixed
- `file_picker` 13.x API migration: `FilePicker.platform` singleton removed, `pickFiles()` no
  longer wraps results in `FilePickerResult`, and `PlatformFile.size` replaced by an async
  `length()` — all updated in the model import flow.

---

## [1.2.1] - 2026-10-30

### Fixed
- **Android model loading crash**: 1.2.0 dropped the `llamadart_native_backends.platforms` hook
  key, wrongly believing `llamadart_native_runtimes` had replaced it — the two are separate,
  complementary keys (one picks the GGUF/LiteRT runtime, the other picks which GPU backend `.so`
  files get bundled). Without it, Android builds stopped bundling the OpenCL and Vulkan backends,
  so a device whose Settings → Hardware Configuration auto-detected OpenCL would fail to load any
  model at all (`Backend module 'opencl' not loaded from any candidate`). Restored the key.
- `LlmService.loadModel` now catches that specific failure class and falls back to CPU once,
  persisting the fallback so it doesn't recur, instead of surfacing a raw native error.

---

## [2.0.0] - 2026-04-23

### Added
- **Global Loading Overlay**: Real-time feedback during large model imports with dynamic pulse messages.
- **Deduplication Logic**: Prevents duplicate model cards and synchronized loading states for models with the same filename.
- **Log Viewer**: New "Logs" screen accessible from the drawer to track and share system logs for troubleshooting.
- **RAM/Size Validation**: Safety dialogs that warn users before importing or loading models that exceed device resource thresholds.
- **Manual Cache Management**: "Clear Temporary Cache" button in settings to reclaim storage from interrupted imports.

### Changed
- **Optimized Model Imports**: Switched from slow stream-copying to instantaneous file-renaming (moving) for local file imports.
- **Startup Resilience**: App no longer crashes on splash screen if the Local API port is already in use.
- **UI Improvements**: Hidden '0%' percentage text on local imports for a cleaner indeterminate loading state.
- **Version Bump**: Updated app version to v2.0.0.

### Fixed
- **Ghost Writing**: Resolved issue where AI generation continued after tapping the "Stop" button.
- **Temporary Cache Bloat**: Automatic cleanup of massive temporary files after successful model imports.
- **Address in Use Error**: Handled socket exceptions in `LocalApiServerService`.

---
