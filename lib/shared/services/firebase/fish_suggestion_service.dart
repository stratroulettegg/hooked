import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

import '../../models/catch_entry.dart';
import '../../utils/image_compression.dart';

class FishSuggestion {
  final FishSpecies? species;
  final bool capped;
  const FishSuggestion({required this.species, this.capped = false});
}

class FishSuggestionService {
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  Future<FishSuggestion?> suggestFromFile(File photo) async {
    final bytes = await compressForUpload(photo, maxEdge: 768, quality: 80);
    final base64Image = base64Encode(bytes);

    final result = await _functions
        .httpsCallable('suggestFishSpecies')
        .call<Map<String, dynamic>>({'imageBase64': base64Image});

    final data = result.data;
    final raw = data['species'] as String?;
    final capped = (data['capped'] as bool?) ?? false;

    if (raw == null || raw == 'unbekannt') {
      return FishSuggestion(species: null, capped: capped);
    }

    final match = FishSpecies.values.cast<FishSpecies?>().firstWhere(
      (s) => s?.name == raw,
      orElse: () => null,
    );
    return FishSuggestion(species: match, capped: capped);
  }
}
