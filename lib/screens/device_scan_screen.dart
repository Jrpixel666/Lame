import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../controllers/model_controller.dart';
import '../models/ai_model_info.dart';
import '../services/device_scan_service.dart';

/// Scans this device's hardware (RAM, CPU cores, free storage) and shows
/// which catalog models are safe to run here.
class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final _scanner = Get.find<DeviceScanService>();
  final _modelCtrl = Get.find<ModelController>();
  DeviceSpecs? _specs;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Future<void> _runScan() async {
    final specs = await _scanner.scan();
    if (!mounted) return;
    setState(() {
      _specs = specs;
      _scanned = true;
    });
  }

  /// Leave ~20% RAM headroom for the OS and the app itself.
  bool _fits(AiModelInfo model, double ramGb) => model.minRamGb <= ramGb * 0.8;

  @override
  Widget build(BuildContext context) {
    final specs = _specs;
    final catalog = _modelCtrl.catalog;
    final ramGb = specs?.ramGb;

    List<AiModelInfo> compatible = [];
    List<AiModelInfo> tooLarge = [];
    if (ramGb != null) {
      for (final m in catalog) {
        (_fits(m, ramGb) ? compatible : tooLarge).add(m);
      }
      compatible.sort((a, b) => b.minRamGb.compareTo(a.minRamGb));
      tooLarge.sort((a, b) => a.minRamGb.compareTo(b.minRamGb));
    }

    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                  Text(
                    'Scan My Device',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                  ),
                  const Spacer(),
                  Obx(() => IconButton(
                        icon: _scanner.isScanning.value
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.refresh_rounded, color: context.textM),
                        onPressed: _scanner.isScanning.value ? null : _runScan,
                        tooltip: 'Re-scan',
                      )),
                ],
              ),
            ),
            Expanded(
              child: Obx(() {
                if (_scanner.isScanning.value && !_scanned) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (specs == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _buildSpecsCard(context, specs),
                    const SizedBox(height: 24),
                    if (ramGb == null) ...[
                      _infoBanner(
                        context,
                        'Could not detect RAM on this platform. '
                        'Showing the full catalog — check each model\'s '
                        'minimum RAM manually before downloading.',
                      ),
                      const SizedBox(height: 12),
                      ...catalog.map((m) => _modelRow(context, m, fits: null)),
                    ] else ...[
                      _sectionLabel(context, 'Recommended for this device (${compatible.length})'),
                      const SizedBox(height: 8),
                      if (compatible.isEmpty)
                        _infoBanner(context, 'No catalog model comfortably fits this device\'s RAM.')
                      else
                        ...compatible.map((m) => _modelRow(context, m, fits: true)),
                      if (tooLarge.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _sectionLabel(context, 'Likely too large (${tooLarge.length})'),
                        const SizedBox(height: 8),
                        ...tooLarge.map((m) => _modelRow(context, m, fits: false)),
                      ],
                    ],
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecsCard(BuildContext context, DeviceSpecs specs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory_rounded, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Device Specs',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _specRow(context, 'Platform', '${specs.os} ${specs.osVersion}'),
          _specRow(context, 'CPU cores', '${specs.cpuCores}'),
          _specRow(
            context,
            'RAM',
            specs.ramGb != null ? '${specs.ramGb!.toStringAsFixed(1)} GB' : 'Unknown',
          ),
          _specRow(
            context,
            'Free storage',
            specs.freeStorageGb != null
                ? '${specs.freeStorageGb!.toStringAsFixed(1)} GB'
                : 'Unknown',
          ),
        ],
      ),
    );
  }

  Widget _specRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 13, color: context.textD)),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.text),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.textM,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _infoBanner(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: context.text)),
          ),
        ],
      ),
    );
  }

  Widget _modelRow(BuildContext context, AiModelInfo model, {required bool? fits}) {
    final downloaded = _modelCtrl.isModelDownloaded(model);
    Color dotColor;
    if (fits == null) {
      dotColor = context.textD;
    } else if (fits) {
      dotColor = AppColors.green;
    } else {
      dotColor = AppColors.red;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${model.sizeGb} GB • Min ${model.minRamGb} GB RAM',
                  style: TextStyle(fontSize: 11, color: context.textD),
                ),
              ],
            ),
          ),
          if (downloaded)
            TextButton(
              onPressed: () {
                _modelCtrl.loadModel(model.filename);
                Get.back();
              },
              child: const Text('Load', style: TextStyle(fontSize: 12)),
            )
          else
            TextButton(
              onPressed: () => _modelCtrl.downloadModel(model),
              child: const Text('Download', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
