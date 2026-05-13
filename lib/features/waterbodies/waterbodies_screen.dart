import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/models/waterbody.dart';
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/tile_cache_service.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/h_scroll_with_hint.dart';
import '../../shared/widgets/mini_map_background.dart';
import '../../shared/widgets/swipe_to_delete.dart';

class WaterbodiesScreen extends ConsumerStatefulWidget {
  const WaterbodiesScreen({super.key, this.embedded = false});

  /// Wenn `true`, wird der Screen ohne eigenes [Scaffold]/[ApexAppBar]
  /// als reine Body-Ansicht gerendert. Wird vom [WaterHubScreen] genutzt,
  /// um Gewässer als Tab in der Übersicht einzubetten.
  final bool embedded;

  @override
  ConsumerState<WaterbodiesScreen> createState() =>
      _WaterbodiesScreenState();
}

/// Verfügbare Umkreise für den Standort-Filter.
const _radiusOptions = <double>[5, 10, 25, 50];

class _WaterbodiesScreenState extends ConsumerState<WaterbodiesScreen> {
  /// Aktiver Umkreis in km — `null` = Filter aus.
  double? _radiusKm;

  /// Aktive Fischart-Filter — `null` = alle.
  FishSpecies? _species;

  /// Aktiver Gewässer-Typ-Filter — `null` = alle Typen.
  WaterbodyType? _type;

  @override
  Widget build(BuildContext context) {
    final wbAsync = ref.watch(waterbodyProvider);
    final spots = ref.watch(spotProvider).valueOrNull ?? const [];
    final catches = ref.watch(catchProvider).valueOrNull ?? const [];
    final c = ApexColors.of(context);

    // Spot-Anzahl pro Gewässer + Spots gruppieren
    final countBySpot = <String, int>{};
    final spotsByWb = <String, List<FishingSpot>>{};
    for (final s in spots) {
      final id = s.waterbodyId;
      if (id != null) {
        countBySpot[id] = (countBySpot[id] ?? 0) + 1;
        (spotsByWb[id] ??= []).add(s);
      }
    }

    // Pro Gewässer die dort gefangenen Arten ermitteln (über Spot→Waterbody).
    final speciesByWb = <String, Set<FishSpecies>>{};
    final spotToWb = <String, String>{
      for (final s in spots)
        if (s.waterbodyId != null) s.id: s.waterbodyId!,
    };
    for (final cn in catches) {
      final sId = cn.spotId;
      if (sId == null) continue;
      final wbId = spotToWb[sId];
      if (wbId == null) continue;
      (speciesByWb[wbId] ??= <FishSpecies>{}).add(cn.species);
    }

    final body = wbAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: ApexColors.primary),
      ),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (waterbodies) {
        if (waterbodies.isEmpty) {
          return EmptyStateView(
            icon: Icons.water_rounded,
            title: 'Noch keine Gewässer',
            description:
                'Lege Seen, Flüsse & Co. an. Ordne ihnen Spots zu, '
                'pflege Notizen und Schonzeiten an einer Stelle.',
            ctaLabel: 'Gewässer anlegen',
            ctaIcon: Icons.add,
            onCta: () => context.push('/waterbodies/add'),
          );
        }

        // Position für Umkreis-Filter — nur watch wenn Filter aktiv.
        final myPos = _radiusKm == null
            ? null
            : ref.watch(locationProvider).valueOrNull;

        // Hilfsfunktion: ein Gewässer-Mittelpunkt — bevorzugt
        // explizites Center, sonst Mittel der zugeordneten Spots.
        LatLng? wbAnchor(Waterbody w) {
          if (w.centerLat != null && w.centerLng != null) {
            return LatLng(w.centerLat!, w.centerLng!);
          }
          final list = spotsByWb[w.id];
          if (list == null || list.isEmpty) return null;
          if (list.length == 1) return LatLng(list.first.lat, list.first.lng);
          double lat = 0, lng = 0;
          for (final s in list) {
            lat += s.lat;
            lng += s.lng;
          }
          return LatLng(lat / list.length, lng / list.length);
        }

        // Filter anwenden.
        final filtered = waterbodies.where((w) {
          if (_type != null && w.type != _type) return false;
          if (_species != null) {
            final hasSpecies = speciesByWb[w.id]?.contains(_species) ?? false;
            if (!hasSpecies) return false;
          }
          if (_radiusKm != null && myPos != null) {
            final anchor = wbAnchor(w);
            if (anchor == null) return false;
            final dist = const Distance().as(
              LengthUnit.Kilometer,
              LatLng(myPos.latitude, myPos.longitude),
              anchor,
            );
            if (dist > _radiusKm!) return false;
          }
          return true;
        }).toList();

        final hasFilter =
            _species != null || _radiusKm != null || _type != null;

        // Verfügbare Typen (nur die, die mind. einmal vorkommen).
        final availableTypes = <WaterbodyType>{
          for (final w in waterbodies) w.type,
        }.toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

        // Nach Typ gruppieren (Reihenfolge: Anzahl absteigend, dann A-Z).
        final groupedByType = <WaterbodyType, List<Waterbody>>{};
        for (final w in filtered) {
          (groupedByType[w.type] ??= []).add(w);
        }
        final orderedTypeKeys = groupedByType.keys.toList()
          ..sort((a, b) {
            final cmp = groupedByType[b]!.length.compareTo(
              groupedByType[a]!.length,
            );
            if (cmp != 0) return cmp;
            return a.displayName.compareTo(b.displayName);
          });

        // Verfügbare Arten für den Filter (alle, die schon mal gefangen
        // wurden — oder die offiziell erlaubt sind).
        final availableSpecies = <FishSpecies>{
          for (final set in speciesByWb.values) ...set,
          for (final w in waterbodies) ...w.allowedSpecies,
        }.toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _WaterbodyOverviewMap(
                waterbodies: waterbodies,
                spotsByWb: spotsByWb,
              ),
            ),
            SliverToBoxAdapter(
              child: _WaterbodyFilterBar(
                radiusKm: _radiusKm,
                species: _species,
                type: _type,
                availableSpecies: availableSpecies,
                availableTypes: availableTypes,
                onChanged: (r, sp, t) => setState(() {
                  _radiusKm = r;
                  _species = sp;
                  _type = t;
                }),
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _NoWaterbodyResults(
                  onReset: () => setState(() {
                    _radiusKm = null;
                    _species = null;
                    _type = null;
                  }),
                ),
              )
            else
              for (var gi = 0; gi < orderedTypeKeys.length; gi++) ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _WaterbodyTypeHeaderDelegate(
                    type: orderedTypeKeys[gi],
                    count: groupedByType[orderedTypeKeys[gi]]!.length,
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    4,
                    12,
                    gi == orderedTypeKeys.length - 1 ? 24 : 8,
                  ),
                  sliver: SliverList.builder(
                    itemCount: groupedByType[orderedTypeKeys[gi]]!.length,
                    itemBuilder: (_, i) {
                      final w = groupedByType[orderedTypeKeys[gi]]![i];
                      final spotCount = countBySpot[w.id] ?? 0;
                      final assignedSpots = spotsByWb[w.id] ?? const [];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SwipeToDelete(
                          dismissKey: ValueKey('wb_${w.id}'),
                          confirmTitle: '„${w.name}" löschen?',
                          confirmMessage: spotCount > 0
                              ? '$spotCount Spot${spotCount == 1 ? '' : 's'} '
                                    'verlieren ihre Gewässer-Verknüpfung — bleiben '
                                    'aber erhalten.'
                              : 'Das Gewässer wird unwiderruflich entfernt.',
                          onDelete: () => ref
                              .read(waterbodyProvider.notifier)
                              .removeWaterbody(w.id),
                          child: _WaterbodyCard(
                            waterbody: w,
                            spotCount: spotCount,
                            assignedSpots: assignedSpots,
                            onTap: () => context.push(
                              '/waterbodies/detail',
                              extra: w,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            if (hasFilter && filtered.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Center(
                    child: Text(
                      '${filtered.length} von ${waterbodies.length} Gewässern',
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neues Gewässer',
            onPressed: () => context.push('/waterbodies/add'),
          ),
        ],
      ),
      body: body,
      backgroundColor: c.background,
    );
  }
}

// ── Übersichtskarte ────────────────────────────────────────────────────────

class _WaterbodyOverviewMap extends StatefulWidget {
  const _WaterbodyOverviewMap({
    required this.waterbodies,
    required this.spotsByWb,
  });
  final List<Waterbody> waterbodies;
  final Map<String, List<FishingSpot>> spotsByWb;

  @override
  State<_WaterbodyOverviewMap> createState() => _WaterbodyOverviewMapState();
}

class _WaterbodyOverviewMapState extends State<_WaterbodyOverviewMap> {
  final _mapController = MapController();
  double _zoom = 9.0;

  static double _markerSize(double zoom) =>
      (24 + (zoom - 10) * 2.5).clamp(16, 40).toDouble();

  @override
  void didUpdateWidget(covariant _WaterbodyOverviewMap old) {
    super.didUpdateWidget(old);
    final oldKey = old.waterbodies.map((w) => w.id).join(',');
    final newKey = widget.waterbodies.map((w) => w.id).join(',');
    if (oldKey != newKey ||
        old.spotsByWb.length != widget.spotsByWb.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final pts = _anchors().map((e) => e.value).toList(growable: false);
        if (pts.isEmpty) return;
        if (pts.length == 1) {
          _mapController.move(pts.first, _mapController.camera.zoom);
        } else {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(pts),
              padding: const EdgeInsets.all(36),
            ),
          );
        }
      });
    }
  }

  /// Liefert Anker-Punkte pro Gewässer (Center oder Spot-Mittelwert).
  List<MapEntry<Waterbody, LatLng>> _anchors() {
    final out = <MapEntry<Waterbody, LatLng>>[];
    for (final w in widget.waterbodies) {
      LatLng? p;
      if (w.centerLat != null && w.centerLng != null) {
        p = LatLng(w.centerLat!, w.centerLng!);
      } else {
        final list = widget.spotsByWb[w.id];
        if (list != null && list.isNotEmpty) {
          double lat = 0, lng = 0;
          for (final s in list) {
            lat += s.lat;
            lng += s.lng;
          }
          p = LatLng(lat / list.length, lng / list.length);
        }
      }
      if (p != null) out.add(MapEntry(w, p));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final entries = _anchors();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final points = entries.map((e) => e.value).toList(growable: false);
    final cameraFit = points.length == 1
        ? null
        : () {
            final b = LatLngBounds.fromPoints(points);
            if (b.north == b.south || b.east == b.west) return null;
            return CameraFit.bounds(
              bounds: b,
              padding: const EdgeInsets.all(36),
            );
          }();

    return Container(
      height: 152,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: c.cardShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 9,
            initialCameraFit: cameraFit,
            minZoom: 3,
            onMapEvent: (event) {
              if (mounted && event.camera.zoom != _zoom) {
                setState(() => _zoom = event.camera.zoom);
              }
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: MapTiles.urlFor(isDark: context.isDark),
              subdomains: MapTiles.subdomains,
              userAgentPackageName: MapTiles.userAgent,
              retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.5,
              tileProvider: TileCacheService.instance.provider,
            ),
            MarkerLayer(
              markers: [
                for (final e in entries)
                  Marker(
                    point: e.value,
                    width: _markerSize(_zoom),
                    height: _markerSize(_zoom),
                    child: GestureDetector(
                      onTap: () => context.push(
                        '/waterbodies/detail',
                        extra: e.key,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: ApexColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.background, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(50),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.water_rounded,
                          color: c.background,
                          size: _markerSize(_zoom) * 0.55,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter-Leiste ──────────────────────────────────────────────────────────

class _WaterbodyFilterBar extends StatelessWidget {
  const _WaterbodyFilterBar({
    required this.radiusKm,
    required this.species,
    required this.type,
    required this.availableSpecies,
    required this.availableTypes,
    required this.onChanged,
  });
  final double? radiusKm;
  final FishSpecies? species;
  final WaterbodyType? type;
  final List<FishSpecies> availableSpecies;
  final List<WaterbodyType> availableTypes;
  final void Function(
    double? radiusKm,
    FishSpecies? species,
    WaterbodyType? type,
  )
  onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: HScrollWithHint(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Umkreis-Filter
            _FilterChip(
              icon: Icons.my_location_rounded,
              label: radiusKm == null
                  ? 'Umkreis'
                  : 'Umkreis ${radiusKm!.toStringAsFixed(0)} km',
              active: radiusKm != null,
              onTap: () async {
                final picked = await showModalBottomSheet<double?>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  showDragHandle: true,
                  backgroundColor: c.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (_) => _RadiusPickerSheet(current: radiusKm),
                );
                // ignore: use_build_context_synchronously
                onChanged(
                  picked == null ? null : (picked == 0 ? null : picked),
                  species,
                  type,
                );
              },
              onClear: radiusKm == null
                  ? null
                  : () => onChanged(null, species, type),
            ),
            const SizedBox(width: 8),
            // Typ-Filter
            _FilterChip(
              icon: Icons.category_rounded,
              label: type == null ? 'Typ' : type!.displayName,
              active: type != null,
              onTap: () async {
                final picked = await showModalBottomSheet<WaterbodyType?>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  showDragHandle: true,
                  backgroundColor: c.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (_) => _TypePickerSheet(
                    current: type,
                    available: availableTypes,
                  ),
                );
                // ignore: use_build_context_synchronously
                onChanged(radiusKm, species, picked);
              },
              onClear: type == null
                  ? null
                  : () => onChanged(radiusKm, species, null),
            ),
            const SizedBox(width: 8),
            // Art-Filter
            _FilterChip(
              icon: Icons.set_meal_rounded,
              label: species == null
                  ? 'Fischart'
                  : species!.displayName,
              active: species != null,
              onTap: () async {
                final picked = await showModalBottomSheet<FishSpecies?>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  showDragHandle: true,
                  backgroundColor: c.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (_) => _SpeciesPickerSheet(
                    current: species,
                    available: availableSpecies,
                  ),
                );
                // ignore: use_build_context_synchronously
                onChanged(radiusKm, picked, type);
              },
              onClear: species == null
                  ? null
                  : () => onChanged(radiusKm, null, type),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 8, onClear == null ? 12 : 6, 8),
        decoration: BoxDecoration(
          color: active
              ? ApexColors.primary.withAlpha(36)
              : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? ApexColors.primary : c.border,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? ApexColors.primary : c.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? ApexColors.primary : c.textPrimary,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: ApexColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RadiusPickerSheet extends StatelessWidget {
  const _RadiusPickerSheet({required this.current});
  final double? current;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UMKREIS UM AKTUELLEN STANDORT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: c.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RadiusOption(
                  label: 'Aus',
                  selected: current == null,
                  onTap: () => Navigator.pop(context, 0.0),
                ),
                for (final km in _radiusOptions)
                  _RadiusOption(
                    label: '${km.toStringAsFixed(0)} km',
                    selected: current == km,
                    onTap: () => Navigator.pop(context, km),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Standort wird nur lokal ausgewertet.',
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadiusOption extends StatelessWidget {
  const _RadiusOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? ApexColors.primary.withAlpha(36)
              : c.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ApexColors.primary : c.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? ApexColors.primary : c.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SpeciesPickerSheet extends StatelessWidget {
  const _SpeciesPickerSheet({
    required this.current,
    required this.available,
  });
  final FishSpecies? current;
  final List<FishSpecies> available;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GEFANGENE / ERLAUBTE FISCHART',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: c.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              if (available.isEmpty)
                Text(
                  'Noch keine Arten erfasst.',
                  style: TextStyle(fontSize: 13, color: c.textMuted),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _RadiusOption(
                          label: 'Alle',
                          selected: current == null,
                          onTap: () => Navigator.pop(context),
                        ),
                        for (final s in available)
                          _RadiusOption(
                            label: s.displayName,
                            selected: current == s,
                            onTap: () => Navigator.pop(context, s),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoWaterbodyResults extends StatelessWidget {
  const _NoWaterbodyResults({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: c.textMuted),
          const SizedBox(height: 12),
          Text(
            'Keine Gewässer im Filter',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Passe Umkreis oder Fischart an oder setze die Filter zurück.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Filter zurücksetzen'),
          ),
        ],
      ),
    );
  }
}

class _WaterbodyCard extends StatelessWidget {
  const _WaterbodyCard({
    required this.waterbody,
    required this.spotCount,
    required this.assignedSpots,
    required this.onTap,
  });
  final Waterbody waterbody;
  final int spotCount;
  final List<FishingSpot> assignedSpots;
  final VoidCallback onTap;

  IconData get _icon {
    switch (waterbody.type) {
      case WaterbodyType.see:
      case WaterbodyType.teich:
        return Icons.water_rounded;
      case WaterbodyType.fluss:
      case WaterbodyType.kanal:
        return Icons.waves_rounded;
      case WaterbodyType.hafen:
        return Icons.directions_boat_rounded;
      case WaterbodyType.meer:
        return Icons.sailing_rounded;
      case WaterbodyType.sonstiges:
        return Icons.water_drop_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final hasSchonzeiten = waterbody.closedSeasons.isNotEmpty;
    final highlight = spotCount >= 5;

    // Rechte Card-Ecken während des Swipes eckig — gleiches Verhalten
    // wie bei den Spot-Cards.
    final swiping = SwipeAffordance.of(context);
    final cardRadius = swiping
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            bottomLeft: Radius.circular(18),
          )
        : BorderRadius.circular(18);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: cardRadius,
          border: Border.all(
            color: highlight ? ApexColors.primary.withAlpha(160) : c.border,
            width: highlight ? 1.6 : 1,
          ),
          boxShadow: context.isDark
              ? []
              : [
                  BoxShadow(
                    color: highlight
                        ? ApexColors.primary.withAlpha(40)
                        : c.cardShadow,
                    blurRadius: highlight ? 14 : 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: cardRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero-Bild (16:9) ───────────────────────────────────────
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LayoutBuilder(
                      builder: (ctx, constraints) {
                        final file = AppPaths.photoFile(waterbody.photoPath);
                        if (file != null) {
                          final cacheW =
                              (constraints.maxWidth *
                                      MediaQuery.devicePixelRatioOf(ctx))
                                  .round();
                          return Image.file(
                            file,
                            fit: BoxFit.cover,
                            cacheWidth: cacheW,
                          );
                        }
                        // Fallback: Mini-Karte mit zugeordneten Spots
                        // (der Gewässer-Mittelpunkt selbst wird **nicht**
                        // als Marker gezeigt — sonst entsteht ein doppelter
                        // Eindruck zwischen "Gewässer" und "Spot").
                        final spotPoints = [
                          for (final s in assignedSpots)
                            LatLng(s.lat, s.lng),
                        ];
                        final wbCenter =
                            (waterbody.centerLat != null &&
                                waterbody.centerLng != null)
                            ? LatLng(
                                waterbody.centerLat!,
                                waterbody.centerLng!,
                              )
                            : null;
                        if (wbCenter != null || spotPoints.isNotEmpty) {
                          return MiniMapBackground(
                            center: wbCenter ?? spotPoints.first,
                            markers: spotPoints,
                          );
                        }
                        return _waterbodyFallbackBackground(_icon);
                      },
                    ),
                    // Top-Right: Typ-Badge
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(110),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_icon, size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              waterbody.type.displayName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Top-Left: nur ausblenden, wenn Mini-Karte oder
                    // Foto sichtbar ist – sonst „Kein Foto"-Hinweis.
                    if (waterbody.photoPath == null &&
                        waterbody.centerLat == null &&
                        assignedSpots.isEmpty)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(70),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.image_not_supported_outlined,
                                size: 12,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Kein Foto',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Header: Name + Spot-Count ─────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            waterbody.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (waterbody.region != null &&
                              waterbody.region!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              waterbody.region!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$spotCount',
                          style: const TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: ApexColors.primary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          spotCount == 1 ? 'SPOT' : 'SPOTS',
                          style: TextStyle(
                            fontSize: 9,
                            color: c.textMuted,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ── Footer: Chips ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _WbFooterChip(
                      icon: Icons.place_outlined,
                      text: spotCount == 0
                          ? 'Noch kein Spot'
                          : spotCount == 1
                          ? '1 Spot'
                          : '$spotCount Spots',
                      iconColor: spotCount > 0
                          ? ApexColors.primary
                          : c.textMuted,
                      muted: spotCount == 0,
                    ),
                    if (waterbody.allowedSpecies.isNotEmpty)
                      _WbFooterChip(
                        icon: Icons.set_meal_rounded,
                        text:
                            '${waterbody.allowedSpecies.length} '
                            '${waterbody.allowedSpecies.length == 1 ? 'Art' : 'Arten'}',
                        iconColor: ApexColors.primary,
                      ),
                    if (hasSchonzeiten)
                      _WbFooterChip(
                        icon: Icons.gavel_rounded,
                        text:
                            '${waterbody.closedSeasons.length} '
                            '${waterbody.closedSeasons.length == 1 ? 'Schonzeit' : 'Schonzeiten'}',
                        iconColor: ApexColors.scoreMid,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _waterbodyFallbackBackground(IconData icon) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          ApexColors.primary.withAlpha(50),
          ApexColors.primary.withAlpha(15),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Icon(icon, size: 56, color: Colors.white70),
    ),
  );
}

class _WbFooterChip extends StatelessWidget {
  const _WbFooterChip({
    required this.icon,
    required this.text,
    required this.iconColor,
    this.muted = false,
  });
  final IconData icon;
  final String text;
  final Color iconColor;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: muted ? c.textMuted : c.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Typ-Picker-Sheet ───────────────────────────────────────────────────────

class _TypePickerSheet extends StatelessWidget {
  const _TypePickerSheet({required this.current, required this.available});
  final WaterbodyType? current;
  final List<WaterbodyType> available;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GEWÄSSER-TYP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: c.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              if (available.isEmpty)
                Text(
                  'Noch keine Typen erfasst.',
                  style: TextStyle(fontSize: 13, color: c.textMuted),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _RadiusOption(
                          label: 'Alle',
                          selected: current == null,
                          onTap: () => Navigator.pop(context),
                        ),
                        for (final t in available)
                          _RadiusOption(
                            label: t.displayName,
                            selected: current == t,
                            onTap: () => Navigator.pop(context, t),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Typ-Section-Header (Trennstrich + Label) ───────────────────────────────

class _WaterbodyTypeHeaderDelegate extends SliverPersistentHeaderDelegate {
  _WaterbodyTypeHeaderDelegate({required this.type, required this.count});
  final WaterbodyType type;
  final int count;

  static const double _height = 36;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  IconData get _icon {
    switch (type) {
      case WaterbodyType.see:
      case WaterbodyType.teich:
        return Icons.water_rounded;
      case WaterbodyType.fluss:
      case WaterbodyType.kanal:
        return Icons.waves_rounded;
      case WaterbodyType.hafen:
        return Icons.directions_boat_rounded;
      case WaterbodyType.meer:
        return Icons.sailing_rounded;
      case WaterbodyType.sonstiges:
        return Icons.water_drop_outlined;
    }
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final c = ApexColors.of(context);
    return Container(
      height: _height,
      color: c.background,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(_icon, size: 14, color: c.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              type.displayName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: c.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: c.border)),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _WaterbodyTypeHeaderDelegate old) =>
      old.type != type || old.count != count;
}
