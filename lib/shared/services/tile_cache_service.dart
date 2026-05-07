import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:path_provider/path_provider.dart';

/// Zentrale URL-Templates für die Carto Basemaps. Enthält den `{r}`-
/// Platzhalter, damit auf Retina-Displays automatisch die `@2x`-Tiles
/// geladen werden (statt das Flutter-Map-eigene Retina-Simulating, das
/// die Tiles unscharf wirken lässt).
abstract class MapTiles {
  static const String light =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  static const String dark =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const List<String> subdomains = ['a', 'b', 'c', 'd'];
  static const String userAgent = 'de.apex.hooked';

  /// Bequemer Helper für Screens: liefert das passende Template je nach
  /// Theme-Modus.
  static String urlFor({required bool isDark}) => isDark ? dark : light;
}

class TileCacheService {
  static TileCacheService? _instance;
  static TileCacheService get instance {
    assert(
      _instance != null,
      'TileCacheService.init() muss zuerst aufgerufen werden',
    );
    return _instance!;
  }

  final HiveCacheStore _store;
  CachedTileProvider? _provider;

  TileCacheService._(this._store);

  static Future<void> init() async {
    final dir = await getApplicationCacheDirectory();
    final store = HiveCacheStore(
      '${dir.path}/map_tiles',
      hiveBoxName: 'map_tiles_cache',
    );
    _instance = TileCacheService._(store);
  }

  /// Tile-Provider für TileLayer — bedient gecachte Tiles vom Disk-Cache (30 Tage gültig).
  ///
  /// Wird einmalig erzeugt und über alle Karten-Screens geteilt, damit nicht
  /// pro Rebuild ein neuer Dio-Client/Interceptor entsteht (Verbindungs-Pool-
  /// Churn → seltene "Tiles laden nicht"-Effekte unter Last).
  CachedTileProvider get provider => _provider ??= CachedTileProvider(
    store: _store,
    maxStale: const Duration(days: 30),
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: const {'User-Agent': 'de.apex.hooked/1.0 (Flutter)'},
      ),
    ),
  );

  /// Lädt alle Tiles für einen Spot vor (~10–15 MB, Zoom 10–15, ±0.05°).
  Future<void> downloadForSpot({
    required double lat,
    required double lng,
    required bool isDark,
    required void Function(int done, int total) onProgress,
  }) async {
    final style = isDark ? 'dark_all' : 'light_all';
    final tiles = _tilesAround(lat, lng);

    final options = CacheOptions(
      store: _store,
      policy: CachePolicy.refreshForceCache, // immer neu laden + cachen
      maxStale: const Duration(days: 30),
    );
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'User-Agent': 'de.apex.hooked'},
      ),
    )..interceptors.add(DioCacheInterceptor(options: options));

    int done = 0;
    for (final t in tiles) {
      final subdomain = MapTiles.subdomains[t.x % MapTiles.subdomains.length];
      // Wir laden nur die @2x-Variante: deckt Retina-Geräte ab und ist
      // kompatibel mit dem `{r}`-Platzhalter im Runtime-Template.
      // Auf Nicht-Retina-Geräten greift der Online-Fallback (oder es wird
      // auf eine Zoomstufe runter gerendert — Tiles bleiben sichtbar).
      final url =
          'https://$subdomain.basemaps.cartocdn.com/$style/${t.z}/${t.x}/${t.y}@2x.png';
      try {
        await dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
      } catch (_) {
        // Einzelne Tiles können fehlschlagen — kein Abbruch
      }
      done++;
      onProgress(done, tiles.length);
    }
  }

  /// Tile-Koordinaten für einen Bereich ±0.05° um lat/lng, Zoom 10–15.
  List<_Tile> _tilesAround(double lat, double lng) {
    const delta = 0.05; // ~5.5 km Radius
    final result = <_Tile>[];
    for (int z = 10; z <= 15; z++) {
      final x1 = _lngX(lng - delta, z);
      final x2 = _lngX(lng + delta, z);
      final y1 = _latY(lat + delta, z); // nördlichere Lat → kleinere y
      final y2 = _latY(lat - delta, z);
      for (int x = x1; x <= x2; x++) {
        for (int y = y1; y <= y2; y++) {
          result.add(_Tile(z, x, y));
        }
      }
    }
    return result;
  }

  int _lngX(double lng, int z) =>
      ((lng + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);

  int _latY(double lat, int z) {
    final r = lat * pi / 180;
    return ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * (1 << z)).floor().clamp(
      0,
      (1 << z) - 1,
    );
  }
}

class _Tile {
  final int z, x, y;
  const _Tile(this.z, this.x, this.y);
}
