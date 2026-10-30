import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/ai_model_info.dart';
import '../models/download_state.dart';
import 'wakelock_service.dart';
import 'chat_storage_service.dart';

/// A place models can be saved to — the app's private internal storage,
/// or (on Android) shared/removable storage such as an SD card.
class StorageLocation {
  final String label;
  final String path;
  const StorageLocation({required this.label, required this.path});
}

/// Manages model catalog, downloads, and local file discovery.
class ModelManager extends GetxService {
  final ChatStorageService _storage = Get.find<ChatStorageService>();

  final catalog = <AiModelInfo>[].obs;
  final downloadedModels = <String>[].obs; // filenames on-disk (list for reactivity)

  // ── Storage locations (internal + SD card) ──────────────────
  final storageLocations = <StorageLocation>[].obs;
  final activeStorageLabel = ''.obs;
  final Map<String, String> _fileDirs = {}; // filename -> directory it was found in

  // ── Download tracking (single reactive object) ─────────────
  final activeDownloads = <String, DownloadState>{}.obs;
  final tick = 0.obs; // force UI refresh counter

  http.Client? _httpClient;
  late String _modelsDir;

  Future<ModelManager> init() async {
    await _discoverStorageLocations();
    _modelsDir = await _resolveActiveModelsDir();
    await _loadCatalog();
    await scanDownloaded();
    return this;
  }

  /// Find every place models could live: the app's private storage, plus
  /// (on Android only) shared and removable storage volumes such as an
  /// inserted SD card, via `getExternalStorageDirectories()` — no special
  /// storage permission needed since these are the app's own per-volume
  /// directories under Android's scoped storage model.
  Future<void> _discoverStorageLocations() async {
    final locations = <StorageLocation>[];

    final appDir = await getApplicationDocumentsDirectory();
    locations.add(StorageLocation(
      label: 'Internal Storage',
      path: p.join(appDir.path, 'PortableAI', 'models'),
    ));

    if (Platform.isAndroid) {
      try {
        final dirs = await getExternalStorageDirectories();
        if (dirs != null) {
          for (var i = 0; i < dirs.length; i++) {
            final label = i == 0
                ? 'Shared Storage'
                : (dirs.length > 2 ? 'SD Card $i' : 'SD Card');
            locations.add(StorageLocation(
              label: label,
              path: p.join(dirs[i].path, 'PortableAI', 'models'),
            ));
          }
        }
      } catch (_) {
        // getExternalStorageDirectories() unsupported or failed — internal-only is fine.
      }
    }

    storageLocations.value = locations;
  }

  /// Resolve which directory new downloads/imports should go into.
  Future<String> _resolveActiveModelsDir() async {
    // Desktop: keep the existing USB-shared-folder convenience check.
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        final execDir = Platform.resolvedExecutable;
        final usbShared = p.join(p.dirname(p.dirname(execDir)), 'Shared', 'models');
        if (await Directory(usbShared).exists()) {
          activeStorageLabel.value = 'USB / Shared Folder';
          return usbShared;
        }
      } catch (_) {
        // Ignore errors resolving executable path
      }
    }

    final savedPath = _storage.modelsStorageDir;
    var chosen = storageLocations.first;
    for (final loc in storageLocations) {
      if (loc.path == savedPath) {
        chosen = loc;
        break;
      }
    }

    activeStorageLabel.value = chosen.label;
    await Directory(chosen.path).create(recursive: true);
    return chosen.path;
  }

  /// Switch which storage location new downloads/imports are saved to.
  /// Existing downloads elsewhere stay put and stay usable — [scanDownloaded]
  /// looks across every known location, not just the active one.
  Future<void> setActiveStorageLocation(StorageLocation location) async {
    await Directory(location.path).create(recursive: true);
    _modelsDir = location.path;
    activeStorageLabel.value = location.label;
    _storage.modelsStorageDir = location.path;
    await scanDownloaded();
  }

  String get modelsDir => _modelsDir;

  /// Force all Obx listeners to rebuild.
  void _notifyUI() {
    tick.value++;
  }

  /// Load the embedded model catalog from assets + persisted custom models.
  Future<void> _loadCatalog() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/models_catalog.json');
      final list = jsonDecode(jsonStr) as List;
      catalog.value =
          list.map((j) => AiModelInfo.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      // Catalog couldn't load — will be empty
    }

    // Load persisted custom models
    try {
      final box = Hive.box('models_meta');
      final customList = box.get('custom_models', defaultValue: <dynamic>[]) as List;
      for (final raw in customList) {
        final model = AiModelInfo.fromJson(Map<String, dynamic>.from(raw as Map));
        // Don't add duplicates
        if (!catalog.any((m) => m.id == model.id)) {
          catalog.add(model);
        }
      }
    } catch (_) {}
  }

  /// Scan every known storage location (internal + any SD card) for
  /// downloaded .gguf files, so a model stays visible and loadable
  /// regardless of which location was active when it was downloaded.
  Future<void> scanDownloaded() async {
    final found = <String>{};
    final dirsToScan = <String>{_modelsDir, ...storageLocations.map((l) => l.path)};

    for (final dirPath in dirsToScan) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      final files = await dir
          .list()
          .where((f) => f is File && f.path.endsWith('.gguf'))
          .map((f) => p.basename(f.path))
          .toList();

      for (final name in files) {
        found.add(name);
        _fileDirs[name] = dirPath;
      }
    }

    downloadedModels.value = found.toList();
  }

  String getModelPath(AiModelInfo model) => getModelPathByFilename(model.filename);
  String getModelPathByFilename(String filename) =>
      p.join(_fileDirs[filename] ?? _modelsDir, filename);
  bool isModelDownloaded(AiModelInfo model) => downloadedModels.contains(model.filename);

  /// Is this model currently downloading?
  bool isDownloading(String filename) {
    return activeDownloads.containsKey(filename) &&
        activeDownloads[filename]!.isActive;
  }

  /// Get the download state for a model (or null).
  DownloadState? getDownloadState(String filename) {
    return activeDownloads[filename];
  }

  /// Download a model with real-time speed tracking.
  /// Enables wake lock + foreground service to keep download alive.
  Future<void> downloadModel(AiModelInfo model) async {
    if (isDownloading(model.filename)) return;

    // Enable wake lock + foreground service for download (fire and forget so UI updates instantly)
    WakelockService? wakelockService;
    try {
      wakelockService = Get.find<WakelockService>();
      wakelockService.enableForDownload(modelName: model.name);
    } catch (e) {
      debugPrint('WakelockService not available: $e');
    }

    // Initialize download state instantly
    activeDownloads[model.filename] = DownloadState(
      filename: model.filename,
      totalBytes: model.sizeGb * 1024 * 1024 * 1024,
    );
    _notifyUI();

    final filePath = getModelPath(model);
    final partFile = File('$filePath.part');

    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(model.url));

      // Support resume
      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await _httpClient!.send(request);
      final contentLength = response.contentLength ?? 0;
      final totalBytes = (existingBytes + contentLength).toDouble();

      // Update total from actual HTTP response
      final state = activeDownloads[model.filename]!;
      state.totalBytes = totalBytes > 0 ? totalBytes : state.totalBytes;
      state.receivedBytes = existingBytes.toDouble();

      final sink = partFile.openWrite(
          mode: existingBytes > 0 ? FileMode.append : FileMode.write);

      int receivedBytes = existingBytes;
      final stopwatch = Stopwatch()..start();
      int lastSpeedCheck = 0;
      int lastSpeedBytes = existingBytes;

      await for (final chunk in response.stream) {
        // Check if cancelled
        if (state.isCancelled) break;

        sink.add(chunk);
        receivedBytes += chunk.length;
        state.receivedBytes = receivedBytes.toDouble();

        // Calculate speed every 500ms
        if (stopwatch.elapsedMilliseconds - lastSpeedCheck > 500) {
          final elapsed = (stopwatch.elapsedMilliseconds - lastSpeedCheck) / 1000;
          final bytesDelta = receivedBytes - lastSpeedBytes;
          state.speedBytesPerSec = bytesDelta / elapsed;
          lastSpeedCheck = stopwatch.elapsedMilliseconds;
          lastSpeedBytes = receivedBytes;
          _notifyUI(); // trigger rebuild

          // Update foreground notification with progress
          if (wakelockService != null && state.totalBytes > 0) {
            final progress = state.receivedBytes / state.totalBytes;
            final speedMb = (state.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1);
            wakelockService.updateDownloadProgress(
              modelName: model.name,
              progress: progress,
              speedText: '$speedMb MB/s',
            );
          }
        }
      }

      await sink.flush();
      await sink.close();

      if (!state.isCancelled) {
        // Rename .part to final
        await partFile.rename(filePath);
        _fileDirs[model.filename] = _modelsDir;
        if (!downloadedModels.contains(model.filename)) {
          downloadedModels.add(model.filename);
        }
      }

      state.isActive = false;
      activeDownloads.remove(model.filename);
      _notifyUI();
    } catch (e) {
      activeDownloads[model.filename]?.isActive = false;
      activeDownloads.remove(model.filename);
      _notifyUI();
      rethrow;
    } finally {
      _httpClient?.close();
      _httpClient = null;

      // Disable wake lock if no other downloads are active
      if (activeDownloads.isEmpty) {
        try {
          await wakelockService?.disable();
        } catch (_) {}
      }
    }
  }

  /// Cancel an active download.
  void cancelDownload(String filename) {
    if (activeDownloads.containsKey(filename)) {
      activeDownloads[filename]!.isCancelled = true;
      activeDownloads[filename]!.isActive = false;
    }
    _httpClient?.close();
    _httpClient = null;
    activeDownloads.remove(filename);
    _notifyUI();
  }

  /// Delete a downloaded model, wherever it actually lives.
  Future<void> deleteModel(String filename) async {
    final dir = _fileDirs[filename] ?? _modelsDir;
    final file = File(p.join(dir, filename));
    if (await file.exists()) {
      await file.delete();
    }
    _fileDirs.remove(filename);
    downloadedModels.remove(filename);
  }

  /// Move a model file from cache to the models directory (instant on most file systems).
  Future<void> moveModel(String sourcePath, String filename) async {
    final destPath = p.join(_modelsDir, filename);
    if (sourcePath == destPath) return;

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    // Try to move the file instantly (rename)
    try {
      await sourceFile.rename(destPath);
    } catch (e) {
      // Fallback to copy if rename fails (e.g. across different partitions)
      await sourceFile.copy(destPath);
      await sourceFile.delete();
    }

    _fileDirs[filename] = _modelsDir;
    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Import a model directly from a stream (useful to bypass FilePicker caching on Android/iOS).
  Future<void> importModelFromStream({
    required String filename,
    required Stream<List<int>> stream,
    required int totalBytes,
    Function(double)? onProgress,
    bool Function()? checkCancelled,
  }) async {
    final destPath = p.join(_modelsDir, filename);
    final destFile = File(destPath);
    
    final sink = destFile.openWrite();
    int copiedBytes = 0;
    bool wasCancelled = false;

    try {
      final mappedStream = stream.map((chunk) {
        if (checkCancelled?.call() == true) {
          throw const FormatException('CANCELLED');
        }
        copiedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(copiedBytes / totalBytes);
        }
        return chunk;
      });
      await sink.addStream(mappedStream);
    } on FormatException catch (e) {
      if (e.message == 'CANCELLED') {
        wasCancelled = true;
      } else {
        rethrow;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (wasCancelled) {
      if (await destFile.exists()) {
        await destFile.delete();
      }
      return;
    }

    _fileDirs[filename] = _modelsDir;
    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Import a model file from external path with progress tracking.
  Future<void> importModel(String sourcePath, {Function(double)? onProgress, bool Function()? checkCancelled}) async {
    final filename = p.basename(sourcePath);
    final destPath = p.join(_modelsDir, filename);

    if (sourcePath != destPath) {
      final sourceFile = File(sourcePath);
      final destFile = File(destPath);
      
      final totalBytes = await sourceFile.length();
      if (totalBytes == 0) return;

      final sourceStream = sourceFile.openRead();
      final sink = destFile.openWrite();

      int copiedBytes = 0;
      bool wasCancelled = false;

      try {
        final mappedStream = sourceStream.map((chunk) {
          if (checkCancelled?.call() == true) {
            throw const FormatException('CANCELLED');
          }
          copiedBytes += chunk.length;
          onProgress?.call(copiedBytes / totalBytes);
          return chunk;
        });
        await sink.addStream(mappedStream);
      } on FormatException catch (e) {
        if (e.message == 'CANCELLED') {
          wasCancelled = true;
        } else {
          rethrow;
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (wasCancelled) {
        if (await destFile.exists()) {
          await destFile.delete();
        }
        return;
      }
    }

    _fileDirs[filename] = _modelsDir;
    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Add custom model to catalog and persist it.
  void addCustomModel(AiModelInfo model) {
    catalog.add(model);
    _persistCustomModels();
  }

  /// Remove a custom model from catalog and persistence.
  void removeCustomModel(String id) {
    catalog.removeWhere((m) => m.id == id);
    _persistCustomModels();
  }

  /// Save all custom models to Hive.
  void _persistCustomModels() {
    final box = Hive.box('models_meta');
    final customList = catalog
        .where((m) => m.isCustom)
        .map((m) => m.toJson())
        .toList();
    box.put('custom_models', customList);
  }

  @override
  void onClose() {
    _httpClient?.close();
    super.onClose();
  }
}
