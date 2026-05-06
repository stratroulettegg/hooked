import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/catch_entry.dart';
import '../../utils/image_compression.dart';

/// Antwort der iNaturalist Computer Vision API.
///
/// `species` ist `null`, wenn kein Fisch erkannt wurde oder der Score
/// zu niedrig ist — der Client zeigt dann keinen Vorschlag.
class FishSuggestion {
  final FishSpecies? species;

  /// Immer false — iNaturalist hat kein Tages-Limit für uns.
  final bool capped;

  const FishSuggestion({required this.species, this.capped = false});
}

class FishSuggestionService {
  static const _endpoint =
      'https://api.inaturalist.org/v1/computervision/score_image';

  /// Mindest-Konfidenz für einen Vorschlag. Darunter gilt: kein Fisch erkannt.
  static const _minScore = 0.10;

  /// Sendet ein komprimiertes Foto direkt an die iNaturalist CV API und
  /// liefert den besten Fischart-Treffer zurück.
  Future<FishSuggestion?> suggestFromFile(File photo) async {
    final bytes = await compressForUpload(photo, maxEdge: 768, quality: 80);

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: 'fish.jpg',
      ));

    final streamed = await request.send().timeout(const Duration(seconds: 25));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('iNaturalist ${streamed.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final results = (json['results'] as List<dynamic>?) ?? [];

    if (results.isEmpty) return const FishSuggestion(species: null);

    final top = results.first as Map<String, dynamic>;
    final score = (top['combined_score'] as num?)?.toDouble() ?? 0.0;

    if (score < _minScore) return const FishSuggestion(species: null);

    final taxon = top['taxon'] as Map<String, dynamic>?;
    final species = _mapTaxon(taxon);

    return FishSuggestion(species: species);
  }

  /// Mappt einen iNaturalist-Taxon auf unsere FishSpecies.
  ///
  /// Strategie:
  /// 1. Wissenschaftlicher Name des Taxons direkt prüfen
  /// 2. ancestor_ids für übergeordnete Taxa prüfen
  /// 3. Ist überhaupt ein Fisch erkannt worden? → `andere`
  /// 4. Kein Fisch → null
  static FishSpecies? _mapTaxon(Map<String, dynamic>? taxon) {
    if (taxon == null) return null;

    final name = (taxon['name'] as String? ?? '').toLowerCase();
    final ancestorIds = (taxon['ancestor_ids'] as List<dynamic>? ?? [])
        .map((e) => e as int)
        .toSet();
    final taxonId = taxon['id'] as int? ?? 0;

    // ── Name-basiertes Matching (robust gegenüber ID-Änderungen) ──────────

    if (_nameContainsAny(name, ['esox'])) return FishSpecies.hecht;

    if (_nameContainsAny(name, ['sander lucioperca', 'lucioperca'])) {
      return FishSpecies.zander;
    }

    if (_nameContainsAny(name, ['perca fluviatilis'])) return FishSpecies.barsch;

    if (_nameContainsAny(name, ['silurus glanis', 'silurus'])) return FishSpecies.wels;

    if (_nameContainsAny(name, ['hucho hucho', 'hucho'])) return FishSpecies.huchen;

    if (_nameContainsAny(name, ['anguilla anguilla', 'anguilla'])) return FishSpecies.aal;

    if (_nameContainsAny(name, [
      'salmo trutta',
      'oncorhynchus mykiss',
      'salvelinus',
      'thymallus', // Äsche – passt zu Forelle
    ])) {
      return FishSpecies.forelle;
    }

    // ── ID-basiertes Matching als Fallback ────────────────────────────────
    // iNaturalist taxon IDs (stabil, aber doppelt absichern via Namen)

    const hechtIds = {55775, 48443}; // Esox (Gattung), Esox lucius
    const zanderIds = {85546}; // Sander lucioperca
    const barschIds = {63745}; // Perca fluviatilis
    const welsIds = {84540}; // Silurus glanis
    const aalIds = {79830}; // Anguilla anguilla
    const huchenIds = {79831}; // Hucho hucho
    const forelleIds = {4828, 79878, 63837, 63836}; // Salmonidae, Salmo trutta, O.mykiss, Salvelinus

    final allIds = {taxonId, ...ancestorIds};
    if (allIds.intersection(hechtIds).isNotEmpty) return FishSpecies.hecht;
    if (allIds.intersection(zanderIds).isNotEmpty) return FishSpecies.zander;
    if (allIds.intersection(barschIds).isNotEmpty) return FishSpecies.barsch;
    if (allIds.intersection(welsIds).isNotEmpty) return FishSpecies.wels;
    if (allIds.intersection(aalIds).isNotEmpty) return FishSpecies.aal;
    if (allIds.intersection(huchenIds).isNotEmpty) return FishSpecies.huchen;
    if (allIds.intersection(forelleIds).isNotEmpty) return FishSpecies.forelle;

    // ── Ist überhaupt ein Fisch erkannt? ──────────────────────────────────
    // Actinopterygii (47178), Chondrichthyes (47273), Petromyzontidae (47533)
    const fishClassIds = {47178, 47273, 47533};
    if (allIds.intersection(fishClassIds).isNotEmpty) return FishSpecies.andere;

    // Kein Fisch → kein Vorschlag
    return null;
  }

  static bool _nameContainsAny(String name, List<String> patterns) =>
      patterns.any(name.contains);
}
