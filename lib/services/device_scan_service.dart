import 'dart:io';

import 'package:get/get.dart';

/// Best-effort hardware snapshot of the device the app is running on.
/// Any field that couldn't be detected on this platform is left null —
/// callers should degrade gracefully rather than guess.
class DeviceSpecs {
  final int cpuCores;
  final String os;
  final String osVersion;
  final double? ramGb;
  final double? freeStorageGb;

  const DeviceSpecs({
    required this.cpuCores,
    required this.os,
    required this.osVersion,
    this.ramGb,
    this.freeStorageGb,
  });
}

/// Detects RAM, CPU core count and free storage without any native plugin,
/// so a model's minimum-RAM requirement can be checked against what this
/// device actually has before the user wastes time downloading it.
class DeviceScanService extends GetxService {
  final isScanning = false.obs;
  final lastScan = Rxn<DeviceSpecs>();

  Future<DeviceSpecs> scan() async {
    isScanning.value = true;
    try {
      final ramGb = await _detectRamGb();
      final freeStorageGb = await _detectFreeStorageGb();
      final specs = DeviceSpecs(
        cpuCores: Platform.numberOfProcessors,
        os: Platform.operatingSystem,
        osVersion: Platform.operatingSystemVersion,
        ramGb: ramGb,
        freeStorageGb: freeStorageGb,
      );
      lastScan.value = specs;
      return specs;
    } finally {
      isScanning.value = false;
    }
  }

  /// Total system RAM in GB, or null if it couldn't be determined.
  Future<double?> _detectRamGb() async {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        // /proc/meminfo is world-readable on both Android and Linux —
        // no permission or native plugin needed.
        final file = File('/proc/meminfo');
        if (await file.exists()) {
          final lines = await file.readAsLines();
          for (final line in lines) {
            if (line.startsWith('MemTotal:')) {
              final kb = int.tryParse(
                line.replaceAll('MemTotal:', '').replaceAll('kB', '').trim(),
              );
              if (kb != null) return kb / (1024 * 1024);
            }
          }
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('sysctl', ['-n', 'hw.memsize']);
        if (result.exitCode == 0) {
          final bytes = int.tryParse(result.stdout.toString().trim());
          if (bytes != null) return bytes / (1024 * 1024 * 1024);
        }
      } else if (Platform.isWindows) {
        final result = await Process.run(
          'wmic',
          ['ComputerSystem', 'get', 'TotalPhysicalMemory'],
        );
        if (result.exitCode == 0) {
          final match = RegExp(r'\d+').firstMatch(result.stdout.toString());
          if (match != null) {
            final bytes = int.tryParse(match.group(0)!);
            if (bytes != null) return bytes / (1024 * 1024 * 1024);
          }
        }
      }
    } catch (_) {
      // iOS has no equivalent without a native plugin, and any of the
      // above can legitimately fail in a sandboxed/locked-down environment.
    }
    return null;
  }

  /// Free storage on the drive holding the app's working directory, in GB.
  Future<double?> _detectFreeStorageGb() async {
    try {
      if (Platform.isLinux || Platform.isAndroid || Platform.isMacOS) {
        final result = await Process.run('df', ['-k', Directory.current.path]);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).trim().split('\n');
          if (lines.length >= 2) {
            final parts = lines.last.split(RegExp(r'\s+'));
            // df -k columns: Filesystem 1K-blocks Used Available Use% Mounted
            if (parts.length >= 4) {
              final availableKb = int.tryParse(parts[3]);
              if (availableKb != null) return availableKb / (1024 * 1024);
            }
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run(
          'wmic',
          ['logicaldisk', 'get', 'FreeSpace'],
        );
        if (result.exitCode == 0) {
          final match = RegExp(r'\d+').firstMatch(result.stdout.toString());
          if (match != null) {
            final bytes = int.tryParse(match.group(0)!);
            if (bytes != null) return bytes / (1024 * 1024 * 1024);
          }
        }
      }
    } catch (_) {
      // Best-effort only.
    }
    return null;
  }
}
