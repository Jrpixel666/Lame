import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// A model returned by the Hugging Face Hub search API.
class HfModelSummary {
  final String id; // e.g. "TheBloke/Mistral-7B-GGUF"
  final int downloads;
  final int likes;
  final List<String> tags;

  const HfModelSummary({
    required this.id,
    required this.downloads,
    required this.likes,
    required this.tags,
  });

  factory HfModelSummary.fromJson(Map<String, dynamic> json) {
    return HfModelSummary(
      id: json['id'] as String? ?? json['modelId'] as String? ?? '',
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      tags: (json['tags'] as List?)?.map((t) => t.toString()).toList() ?? [],
    );
  }
}

/// A single downloadable .gguf file belonging to a Hugging Face repo.
class HfGgufFile {
  final String repoId;
  final String rfilename;
  final String downloadUrl;

  HfGgufFile({required this.repoId, required this.rfilename})
      : downloadUrl = 'https://huggingface.co/$repoId/resolve/main/$rfilename';

  String get displayName => rfilename;
}

/// Thin client for the public, unauthenticated Hugging Face Hub API.
/// Only used to search/browse model repos and list their GGUF files —
/// actual downloads reuse ModelController.addCustomUrlModel / ModelManager.
class HuggingFaceService extends GetxService {
  static const _base = 'https://huggingface.co/api';

  final isSearching = false.obs;
  final errorMessage = ''.obs;

  /// Search for model repos. Defaults to GGUF-tagged repos, which is what
  /// this app can actually load.
  Future<List<HfModelSummary>> search(String query, {int limit = 25}) async {
    isSearching.value = true;
    errorMessage.value = '';
    try {
      final uri = Uri.parse('$_base/models').replace(queryParameters: {
        if (query.trim().isNotEmpty) 'search': query.trim(),
        'filter': 'gguf',
        'limit': '$limit',
        'sort': 'downloads',
        'direction': '-1',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Hugging Face returned ${response.statusCode}');
      }

      final list = jsonDecode(response.body) as List;
      return list
          .map((j) => HfModelSummary.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      errorMessage.value = e.toString();
      return [];
    } finally {
      isSearching.value = false;
    }
  }

  /// List the .gguf files available in a given model repo.
  Future<List<HfGgufFile>> listGgufFiles(String repoId) async {
    final uri = Uri.parse('$_base/models/$repoId').replace(
      queryParameters: {'expand[]': 'siblings'},
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Hugging Face returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final siblings = (data['siblings'] as List?) ?? [];

    return siblings
        .map((s) => (s as Map<String, dynamic>)['rfilename'] as String? ?? '')
        .where((name) => name.toLowerCase().endsWith('.gguf'))
        .map((name) => HfGgufFile(repoId: repoId, rfilename: name))
        .toList();
  }
}
