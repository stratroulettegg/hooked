import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class NominatimResult {
  const NominatimResult({
    required this.displayName,
    required this.shortName,
    required this.location,
    required this.boundingBox,
    this.type,
  });

  final String displayName;
  final String shortName;
  final LatLng location;
  final List<double> boundingBox; // [minLat, maxLat, minLng, maxLng]
  final String? type;

  factory NominatimResult.fromJson(Map<String, dynamic> json) {
    final bb = (json['boundingbox'] as List).map((e) => double.parse(e as String)).toList();
    return NominatimResult(
      displayName: json['display_name'] as String,
      shortName: (json['name'] as String?) ?? (json['display_name'] as String).split(',').first,
      location: LatLng(
        double.parse(json['lat'] as String),
        double.parse(json['lon'] as String),
      ),
      boundingBox: bb,
      type: json['type'] as String?,
    );
  }
}

class NominatimService {
  static const _base = 'https://nominatim.openstreetmap.org/search';
  static const _headers = {
    'User-Agent': 'Hooked/1.0 (de.apex.hooked)',
    'Accept-Language': 'de',
  };

  /// Sucht nach Gewässern (Seen, Flüsse, Teiche etc.) und allgemeinen Orten.
  /// [query] kann z.B. "Starnberger See" oder "Isar München" sein.
  Future<List<NominatimResult>> searchWater(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      // Erst spezifisch nach Gewässern suchen
      final waterResults = await _search(query, extraParams: {
        'featuretype': 'waterway',
      });

      // Dann allgemein (fängt Seen, Weiher, etc.)
      final generalResults = await _search(query);

      // Deduplizieren nach display_name
      final seen = <String>{};
      final merged = <NominatimResult>[];
      for (final r in [...waterResults, ...generalResults]) {
        if (seen.add(r.displayName)) merged.add(r);
      }
      return merged.take(8).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<NominatimResult>> _search(String query, {Map<String, String>? extraParams}) async {
    final params = <String, String>{
      'q': query,
      'format': 'json',
      'addressdetails': '1',
      'limit': '10',
      'countrycodes': 'de,at,ch',
      ...?extraParams,
    };

    final uri = Uri.parse(_base).replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return [];

    final data = json.decode(response.body) as List;
    return data
        .cast<Map<String, dynamic>>()
        .map(NominatimResult.fromJson)
        .toList();
  }
}
