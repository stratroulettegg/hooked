import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/nominatim_service.dart';
import '../../shared/services/tile_cache_service.dart';

/// Vollbild-Karten-Picker.
// ignore: unintended_html_in_doc_comment
/// Aufruf: final pos = await Navigator.push<PickedLocation>(context, ...);
class PickedLocation {
  final LatLng position;
  final String? waterBodyName;
  const PickedLocation(this.position, {this.waterBodyName});
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialPosition,
    this.title = 'Standort wählen',
  });

  final LatLng? initialPosition;
  final String title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Fallback, wenn weder eine vorgegebene Position noch GPS verfügbar sind.
  static const _defaultCenter = LatLng(52.3906, 13.0645); // Potsdam

  final _mapController = MapController();
  final _searchCtrl = TextEditingController();
  final _nominatim = NominatimService();

  LatLng? _picked;
  String? _pickedName;
  bool _searching = false;
  List<NominatimResult> _results = [];
  Timer? _debounce;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialPosition;
    // Wenn kein Startpunkt vorgegeben ist: GPS holen und die Karte
    // dorthin schwenken. Wir setzen `_picked` dabei NICHT, damit kein
    // automatischer Pin erscheint — der Nutzer wählt seinen Spot bewusst.
    if (widget.initialPosition == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveToCurrent());
    }
  }

  Future<void> _moveToCurrent() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      _mapController.move(LatLng(pos.latitude, pos.longitude), 13);
    } catch (_) {
      // Fallback auf _defaultCenter (Potsdam) — bereits initialer Center.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _showResults = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final results = await _nominatim.searchWater(value.trim());
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
          _showResults = results.isNotEmpty;
        });
      }
    });
  }

  void _selectResult(NominatimResult result) {
    setState(() {
      _picked = result.location;
      // Kurzform übernehmen (z. B. "Bodensee") — die Detail-Adresse
      // gehört nicht in das Gewässerfeld.
      _pickedName = result.shortName;
      _results = [];
      _showResults = false;
      _searchCtrl.text = result.shortName;
      _searchCtrl.selection = TextSelection.collapsed(
        offset: _searchCtrl.text.length,
      );
    });
    FocusScope.of(context).unfocus();

    // Kamera auf Ergebnis zoomen
    final bb = result.boundingBox;
    if (bb.length == 4) {
      final bounds = LatLngBounds(LatLng(bb[0], bb[2]), LatLng(bb[1], bb[3]));
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } else {
      _mapController.move(result.location, 14);
    }
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _picked = point;
      _pickedName = null;
      _showResults = false;
    });
    FocusScope.of(context).unfocus();
  }

  String _formatCoords(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final isDark = context.isDark;

    return Scaffold(
      body: Stack(
        children: [
          // ── Karte ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked ?? _defaultCenter,
              initialZoom: _picked != null ? 14 : 9,
              minZoom: 5,
              onTap: _onMapTap,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
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
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('© CARTO'),
                ],
                alignment: AttributionAlignment.bottomLeft,
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 48,
                      height: 48,
                      child: _PinMarker(
                        color: ApexColors.primary,
                        bgColor: c.background,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Schließen-Button oben links ────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Suchzeile
                  Row(
                    children: [
                      Material(
                        color: c.surface,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          color: c.textPrimary,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Material(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(12),
                          elevation: 3,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Gewässer suchen …',
                              hintStyle: TextStyle(color: c.textMuted),
                              prefixIcon: _searching
                                  ? Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: ApexColors.primary,
                                        ),
                                      ),
                                    )
                                  : Icon(Icons.search, color: c.textMuted),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        color: c.textMuted,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {
                                          _results = [];
                                          _showResults = false;
                                        });
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Suchergebnisse
                  if (_showResults) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _results.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: c.border),
                            itemBuilder: (_, i) {
                              final r = _results[i];
                              return ListTile(
                                leading: Icon(
                                  _iconForType(r.type),
                                  color: ApexColors.primary,
                                  size: 22,
                                ),
                                title: Text(
                                  r.shortName,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  r.displayName
                                      .split(',')
                                      .skip(1)
                                      .take(2)
                                      .join(',')
                                      .trim(),
                                  style: TextStyle(
                                    color: c.textMuted,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selectResult(r),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Tipp-Hinweis (wenn noch nichts gewählt) ───────────────────────
          if (_picked == null)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface.withAlpha(230),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 18, color: c.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Auf Karte tippen oder Gewässer suchen',
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Bestätigen-Button ──────────────────────────────────────────────
          if (_picked != null)
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface.withAlpha(230),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      _formatCoords(_picked!),
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 13,
                        color: c.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        _picked == null
                            ? null
                            : PickedLocation(
                                _picked!,
                                waterBodyName: _pickedName,
                              ),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        'STANDORT BESTÄTIGEN',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ApexColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'lake':
      case 'reservoir':
      case 'pond':
        return Icons.water;
      case 'river':
      case 'stream':
      case 'canal':
        return Icons.waves;
      default:
        return Icons.location_on;
    }
  }
}

class _PinMarker extends StatelessWidget {
  const _PinMarker({required this.color, required this.bgColor});
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: bgColor, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(140),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(Icons.location_on, color: bgColor, size: 22),
        ),
        Container(width: 2, height: 8, color: color),
      ],
    );
  }
}
