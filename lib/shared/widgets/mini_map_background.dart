import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../services/tile_cache_service.dart';

/// Nicht-interaktive Mini-Karte, die als Platzhalter für ein fehlendes
/// Hero-Foto in Spot- und Gewässer-Cards verwendet wird.
///
/// Zeigt einen oder mehrere Marker auf einer gekachelten Karte. Touch wird
/// nicht abgefangen, sodass ein darüberliegender Tap-Handler (Card-Tap)
/// weiterhin greift.
class MiniMapBackground extends StatelessWidget {
  const MiniMapBackground({
    super.key,
    required this.markers,
    this.center,
    this.zoom = 13,
  });

  /// Alle anzuzeigenden Marker-Positionen. Mindestens ein Marker wird
  /// gerendert; ist die Liste leer, fällt das Widget auf ein leeres
  /// Karten-Bild zurück.
  final List<LatLng> markers;

  /// Optionaler Mittelpunkt. Wenn `null`, wird der erste Marker als
  /// Zentrum verwendet.
  final LatLng? center;

  /// Initial-Zoom. 13 entspricht etwa Stadtteil-Niveau.
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final c = ApexColors.of(context);
    final initial = center ?? (markers.isNotEmpty ? markers.first : null);
    if (initial == null) {
      return Container(color: c.surfaceVariant);
    }
    // Wichtiger Key: erzwingt einen Rebuild der `FlutterMap`, sobald sich
    // Zentrum oder Marker-Set ändern. `MapOptions.initialCenter` wird nur
    // beim ersten Build berücksichtigt — ohne diesen Key bleibt die Karte
    // nach Anlage eines neuen Spots/Gewässers auf den alten Koordinaten.
    final mapKey = ValueKey(
      'mini_${initial.latitude.toStringAsFixed(5)}_'
      '${initial.longitude.toStringAsFixed(5)}_${markers.length}',
    );
    return IgnorePointer(
      child: FlutterMap(
        key: mapKey,
        options: MapOptions(
          initialCenter: initial,
          initialZoom: zoom,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: MapTiles.urlFor(isDark: isDark),
            subdomains: MapTiles.subdomains,
            userAgentPackageName: MapTiles.userAgent,
            retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.5,
            tileProvider: TileCacheService.instance.provider,
          ),
          MarkerLayer(
            markers: [
              for (final p in markers)
                Marker(
                  point: p,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ApexColors.primary,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
