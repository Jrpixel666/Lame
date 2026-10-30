import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../controllers/model_controller.dart';
import '../services/huggingface_service.dart';

/// Lets the user search huggingface.co for GGUF model repos and pick a
/// quantization file to add straight into the local Model Library.
class HuggingFaceSearchScreen extends StatefulWidget {
  const HuggingFaceSearchScreen({super.key});

  @override
  State<HuggingFaceSearchScreen> createState() =>
      _HuggingFaceSearchScreenState();
}

class _HuggingFaceSearchScreenState extends State<HuggingFaceSearchScreen> {
  final _hf = Get.find<HuggingFaceService>();
  final _modelCtrl = Get.find<ModelController>();
  final _queryController = TextEditingController();

  List<HfModelSummary> _results = [];
  bool _searched = false;
  String? _expandedId;
  Future<List<HfGgufFile>>? _filesFuture;

  @override
  void initState() {
    super.initState();
    // Seed with a sensible default search so the screen isn't empty.
    _queryController.text = 'uncensored gguf';
    _runSearch();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _queryController.text.trim();
    final results = await _hf.search(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = true;
      _expandedId = null;
    });
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedId == id) {
        _expandedId = null;
        _filesFuture = null;
      } else {
        _expandedId = id;
        _filesFuture = _hf.listGgufFiles(id);
      }
    });
  }

  Future<void> _addFile(HfGgufFile file) async {
    final shortName = file.rfilename.replaceAll('.gguf', '');
    await _modelCtrl.addCustomUrlModel(
      name: '${file.repoId.split('/').last} ($shortName)',
      url: file.downloadUrl,
    );
    if (mounted) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                  Text(
                    'Hugging Face',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                  ),
                ],
              ),
            ),

            // ── Search field ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _queryController,
                style: TextStyle(color: context.text, fontSize: 14),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search models on huggingface.co...',
                  hintStyle: TextStyle(color: context.textD),
                  prefixIcon: Icon(Icons.search_rounded, color: context.textM),
                  filled: true,
                  fillColor: context.bgInput,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
                onSubmitted: (_) => _runSearch(),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: context.textD),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Showing GGUF repositories only — the format this app can run.',
                      style: TextStyle(fontSize: 11, color: context.textD),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Results ──
            Expanded(
              child: Obx(() {
                if (_hf.isSearching.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_hf.errorMessage.value.isNotEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Search failed: ${_hf.errorMessage.value}',
                        style: TextStyle(color: context.textD, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (_searched && _results.isEmpty) {
                  return Center(
                    child: Text(
                      'No GGUF models found for that search.',
                      style: TextStyle(color: context.textD, fontSize: 13),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _results.length,
                  itemBuilder: (context, index) =>
                      _buildResultCard(context, _results[index]),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, HfModelSummary model) {
    final expanded = _expandedId == model.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleExpand(model.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.smart_toy_outlined,
                        size: 18, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.id,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.download_rounded,
                                size: 12, color: context.textD),
                            const SizedBox(width: 3),
                            Text(
                              '${model.downloads}',
                              style: TextStyle(fontSize: 11, color: context.textD),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.favorite_border_rounded,
                                size: 12, color: context.textD),
                            const SizedBox(width: 3),
                            Text(
                              '${model.likes}',
                              style: TextStyle(fontSize: 11, color: context.textD),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: context.textM,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _buildFilesList(context),
        ],
      ),
    );
  }

  Widget _buildFilesList(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: FutureBuilder<List<HfGgufFile>>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return Text(
              'Could not load files: ${snapshot.error}',
              style: const TextStyle(color: AppColors.red, fontSize: 12),
            );
          }
          final files = snapshot.data ?? [];
          if (files.isEmpty) {
            return Text(
              'No .gguf files found in this repo.',
              style: TextStyle(color: context.textD, fontSize: 12),
            );
          }
          return Column(
            children: files.map((f) {
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.displayName,
                        style: TextStyle(fontSize: 12, color: context.textM),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _addFile(f),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Add', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
