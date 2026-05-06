import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

import '../../models/catch_entry.dart';
import '../../utils/image_compression.dart';

/// Antwort des `suggestFishSpecies`-Callables.
///
/// `species` ist `null`, wenn das Modell unsicher war oder kein Fisch
/// erkannt wurde — der Client zeigt dann **keinen** Vorschlags-Banner.
class FishSuggestion {
  final FishSpecies? species;
  final bool capped;

  const FishSuggestion({required this.species, required this.capped});
}

class FishSuggestionService {
  FishSuggestionService();

  static final _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Schickt ein kleines JPEG-Thumbnail an die Cloud Function und liefert
  /// einen Fischart-Vorschlag zurück. Fehler werden geschluckt — die
  /// Erkennung ist optional.
  Future<FishSuggestion?> suggestFromFile(File photo) async {
    try {
      // Klein halten: 768px reicht Gemini locker, hält Payload < 200 KB.
      final bytes = await compressForUpload(photo, maxEdge: 768, quality: 80);
      final base64Image = base64Encode(bytes);

      final result = await _functions
          .httpsCallable('suggestFishSpecies')
          .call<Map<Object?, Object?>>({'imageBase64': base64Image});

      final data = result.data;
      final raw = data['species'] as String?;
      final capped = (data['capped'] as bool?) ?? false;

      if (raw == null || raw == 'unbekannt') {
        return FishSuggestion(species: null, capped: capped);
      }

      final match = FishSpecies.values.where((s) => s.name == raw).firstOrNull;
      return FishSuggestion(species: match, capped: capped);
    } catch (_) {
      // Vorschlag ist optional — keine User-sichtbaren Fehler.
      return null;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
