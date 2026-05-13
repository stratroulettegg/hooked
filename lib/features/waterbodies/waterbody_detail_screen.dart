import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/models/waterbody.dart';
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/external_map_launcher.dart';
import '../../shared/services/tile_cache_service.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../spots/spot_detail_screen.dart' show SpotDetailArgs;

/// Detail-Ansicht eines Gewässers — analog zu `SpotDetailScreen`:
/// Vollbild-Hero (Foto oder Karte) im Hintergrund, oben drauf ein
/// Glass-Blur-Sheet, das per Tap ausklappbar ist.
class WaterbodyDetailScreen extends ConsumerStatefulWidget {
  const WaterbodyDetailScreen({super.key, required this.waterbody});
  final Waterbody waterbody;

  @override
  ConsumerState<WaterbodyDetailScreen> createState() =>
      _WaterbodyDetailScreenState();
}

class _WaterbodyDetailScreenState extends ConsumerState<WaterbodyDetailScreen> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    final all = ref.watch(waterbodyProvider).valueOrNull ?? const [];
    final wb = all.firstWhere(
      (w) => w.id == widget.waterbody.id,
      orElse: () => widget.waterbody,
    );

    final allSpots = ref.watch(spotProvider).valueOrNull ?? const [];
    final assignedSpots = allSpots
        .where((s) => s.waterbodyId == wb.id)
        .toList();

    final allCatches = ref.watch(catchProvider).valueOrNull ?? const [];
    final assignedSpotIds = {for (final s in assignedSpots) s.id};
    final wbCatches = allCatches
        .where((cn) => cn.spotId != null && assignedSpotIds.contains(cn.spotId))
        .toList();

    final speciesCounts = <FishSpecies, int>{};
    for (final cn in wbCatches) {
      speciesCounts[cn.species] = (speciesCounts[cn.species] ?? 0) + 1;
    }
    final speciesSorted = speciesCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final photoFile = AppPaths.photoFile(wb.photoPath);

    return Scaffold(
      backgroundColor: c.background,
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/waterbodies/edit', extra: wb),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: ApexColors.scoreLow),
            onPressed: () => _confirmDelete(context, wb),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight;
          final collapsedH = math.max(
            maxH * (photoFile != null ? 0.18 : 0.22),
            160.0,
          );
          final expandedH = maxH * 0.95;
          final sheetH = _expanded ? expandedH : collapsedH;

          return Stack(
            children: [
              Positioned.fill(
                child: _WaterbodyHeroBackdrop(
                  waterbody: wb,
                  assignedSpots: assignedSpots,
                  photoFile: photoFile,
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: 0,
                height: sheetH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: ColoredBox(
                        color: c.background.withAlpha(60),
                        child: Column(
                          children: [
                            // Tap-Header: Drag-Handle + Name + Type-Chip + Region
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setState(() => _expanded = !_expanded),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Center(
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        width: _expanded ? 56 : 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: _expanded
                                              ? ApexColors.primary.withAlpha(
                                                  180,
                                                )
                                              : c.border,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Name + Spot-Count
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.baseline,
                                            textBaseline:
                                                TextBaseline.alphabetic,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  wb.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: 'Rajdhani',
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w800,
                                                    height: 1.05,
                                                    letterSpacing: 0.3,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                '${assignedSpots.length}',
                                                style: const TextStyle(
                                                  fontFamily: 'Rajdhani',
                                                  fontSize: 22,
                                                  color: ApexColors.primary,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                assignedSpots.length == 1
                                                    ? 'SPOT'
                                                    : 'SPOTS',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: c.textMuted,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (wbCatches.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          _CatchCountChip(
                                            count: wbCatches.length,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Meta: Typ · Region
                                    Row(
                                      children: [
                                        Icon(
                                          _typeIcon(wb.type),
                                          size: 13,
                                          color: c.textMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            wb.type.displayName,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Rajdhani',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: c.textSecondary,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        if ((wb.region ?? '')
                                            .trim()
                                            .isNotEmpty) ...[
                                          _MetaDot(color: c.textMuted),
                                          Flexible(
                                            child: Text(
                                              wb.region!,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontFamily: 'Rajdhani',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Scrollbarer Content
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.zero,
                                physics: _expanded
                                    ? const ClampingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _WaterbodyMiniMap(
                                          waterbody: wb,
                                          assignedSpots: assignedSpots,
                                        ),
                                        const SizedBox(height: 16),
                                        // Info-Karte
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: c.surface,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(color: c.border),
                                          ),
                                          child: Column(
                                            children: [
                                              _InfoRow(
                                                icon: _typeIcon(wb.type),
                                                label: 'Typ',
                                                value: wb.type.displayName,
                                              ),
                                              if ((wb.region ?? '')
                                                  .trim()
                                                  .isNotEmpty)
                                                _InfoRow(
                                                  icon: Icons.map_outlined,
                                                  label: 'Region',
                                                  value: wb.region!,
                                                ),
                                              if (wb.centerLat != null &&
                                                  wb.centerLng != null)
                                                _InfoRow(
                                                  icon: Icons
                                                      .location_on_outlined,
                                                  label: 'Mittelpunkt',
                                                  value:
                                                      '${wb.centerLat!.toStringAsFixed(5)}, ${wb.centerLng!.toStringAsFixed(5)}',
                                                ),
                                              _InfoRow(
                                                icon: Icons.place_outlined,
                                                label: 'Spots',
                                                value:
                                                    '${assignedSpots.length}',
                                              ),
                                              if (wbCatches.isNotEmpty)
                                                _InfoRow(
                                                  icon: Icons.set_meal,
                                                  label: 'Fänge',
                                                  value: '${wbCatches.length}',
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (wb.allowedSpecies.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'ERLAUBTE FISCHARTEN',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (final s in wb.allowedSpecies)
                                                _SimpleChip(
                                                  label: s.displayName,
                                                ),
                                            ],
                                          ),
                                        ],
                                        if (speciesSorted.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'GEFANGENE ARTEN',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (final e in speciesSorted)
                                                _SpeciesCountChip(
                                                  species: e.key,
                                                  count: e.value,
                                                ),
                                            ],
                                          ),
                                        ],
                                        if (wb.closedSeasons.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'SCHONZEITEN',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          for (final s in wb.closedSeasons)
                                            _ClosedSeasonRow(season: s),
                                        ],
                                        if (wb.spinBans.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'SPINNFISCHVERBOTE',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          for (final b in wb.spinBans)
                                            _SpinBanRow(ban: b),
                                        ],
                                        if ((wb.notes ?? '')
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'NOTIZEN',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: c.surface,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: c.border,
                                              ),
                                            ),
                                            child: Text(
                                              wb.notes!,
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1.4,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if ((wb.regulationsUrl ?? '')
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'REGELWERK',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          _RegulationsTile(
                                            url: wb.regulationsUrl!,
                                          ),
                                        ],
                                        if (assignedSpots.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'ZUGEORDNETE SPOTS',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          for (final s in assignedSpots)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: _AssignedSpotTile(
                                                spot: s,
                                              ),
                                            ),
                                        ],
                                        const SizedBox(height: 24),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Waterbody wb) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ApexColors.of(context).surface,
        title: Text(
          'Gewässer löschen?',
          style: TextStyle(color: ApexColors.of(context).textPrimary),
        ),
        content: Text(
          'Spots verlieren ihre Gewässer-Verknüpfung — bleiben aber erhalten.',
          style: TextStyle(color: ApexColors.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Löschen',
              style: TextStyle(color: ApexColors.scoreLow),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (context.mounted) context.pop();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await ref.read(waterbodyProvider.notifier).removeWaterbody(wb.id);
    }
  }
}

IconData _typeIcon(WaterbodyType t) {
  switch (t) {
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

// ── Hero-Backdrop ───────────────────────────────────────────────────────────

class _WaterbodyHeroBackdrop extends StatelessWidget {
  const _WaterbodyHeroBackdrop({
    required this.waterbody,
    required this.assignedSpots,
    required this.photoFile,
  });
  final Waterbody waterbody;
  final List<FishingSpot> assignedSpots;
  final File? photoFile;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final base = photoFile != null
        ? Image.file(photoFile!, fit: BoxFit.cover)
        : _MapBackdrop(
            waterbody: waterbody,
            assignedSpots: assignedSpots,
          );
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          base,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withAlpha(120), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, c.background.withAlpha(180)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapBackdrop extends StatelessWidget {
  const _MapBackdrop({required this.waterbody, required this.assignedSpots});
  final Waterbody waterbody;
  final List<FishingSpot> assignedSpots;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    LatLng? center;
    if (waterbody.centerLat != null && waterbody.centerLng != null) {
      center = LatLng(waterbody.centerLat!, waterbody.centerLng!);
    } else if (assignedSpots.isNotEmpty) {
      double lat = 0, lng = 0;
      for (final s in assignedSpots) {
        lat += s.lat;
        lng += s.lng;
      }
      center = LatLng(lat / assignedSpots.length, lng / assignedSpots.length);
    }
    if (center == null) {
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
          child: Icon(
            _typeIcon(waterbody.type),
            size: 96,
            color: Colors.white70,
          ),
        ),
      );
    }
    return FlutterMap(
      key: ValueKey(
        'wb_backdrop_${center.latitude.toStringAsFixed(5)}_'
        '${center.longitude.toStringAsFixed(5)}_${assignedSpots.length}',
      ),
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12,
        minZoom: 5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
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
            for (final s in assignedSpots)
              Marker(
                point: LatLng(s.lat, s.lng),
                width: 36,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: ApexColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.background, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: ApexColors.primary.withAlpha(120),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: c.background,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Mini-Map im Sheet ───────────────────────────────────────────────────────

class _WaterbodyMiniMap extends StatelessWidget {
  const _WaterbodyMiniMap({
    required this.waterbody,
    required this.assignedSpots,
  });
  final Waterbody waterbody;
  final List<FishingSpot> assignedSpots;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    LatLng? center;
    if (waterbody.centerLat != null && waterbody.centerLng != null) {
      center = LatLng(waterbody.centerLat!, waterbody.centerLng!);
    } else if (assignedSpots.isNotEmpty) {
      double lat = 0, lng = 0;
      for (final s in assignedSpots) {
        lat += s.lat;
        lng += s.lng;
      }
      center = LatLng(lat / assignedSpots.length, lng / assignedSpots.length);
    }
    if (center == null) return const SizedBox.shrink();

    final pts = [
      for (final s in assignedSpots) LatLng(s.lat, s.lng),
      center,
    ];
    final fit = pts.length == 1
        ? null
        : CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.all(28),
          );

    return GestureDetector(
      onTap: () => ExternalMapLauncher.choose(
        context,
        lat: center!.latitude,
        lng: center.longitude,
        label: waterbody.name,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 180,
          child: Stack(
            children: [
              FlutterMap(
                key: ValueKey(
                  'wb_minimap_${center.latitude.toStringAsFixed(5)}_'
                  '${center.longitude.toStringAsFixed(5)}_'
                  '${assignedSpots.length}',
                ),
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 13,
                  initialCameraFit: fit,
                  minZoom: 5,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
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
                      for (final s in assignedSpots)
                        Marker(
                          point: LatLng(s.lat, s.lng),
                          width: 28,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              color: ApexColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c.background,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: c.background,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.directions,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Route',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
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

// ── Helper-Widgets (Stil identisch zu SpotDetailScreen) ─────────────────────

class _MetaDot extends StatelessWidget {
  const _MetaDot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '·',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CatchCountChip extends StatelessWidget {
  const _CatchCountChip({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ApexColors.primary.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.set_meal, size: 14, color: ApexColors.primary),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ApexColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: ApexColors.primary),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: ApexColors.of(context).textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: ApexColors.of(context).textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleChip extends StatelessWidget {
  const _SimpleChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
    );
  }
}

class _SpeciesCountChip extends StatelessWidget {
  const _SpeciesCountChip({required this.species, required this.count});
  final FishSpecies species;
  final int count;
  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            species.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: ApexColors.primary.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ApexColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosedSeasonRow extends StatelessWidget {
  const _ClosedSeasonRow({required this.season});
  final ClosedSeason season;
  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final isClosed = season.isClosedOn(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isClosed
              ? ApexColors.scoreMid.withAlpha(160)
              : c.border,
          width: isClosed ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.gavel_rounded,
            size: 18,
            color: isClosed ? ApexColors.scoreMid : c.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  season.species.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  season.rangeLabel +
                      (season.minLengthCm != null
                          ? '   ·   Mindestmaß ${season.minLengthCm!.toStringAsFixed(0)} cm'
                          : ''),
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (isClosed)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: ApexColors.scoreMid.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'AKTIV',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: ApexColors.scoreMid,
                  letterSpacing: 0.8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RegulationsTile extends StatelessWidget {
  const _RegulationsTile({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.menu_book_rounded,
              size: 20,
              color: ApexColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

class _AssignedSpotTile extends StatelessWidget {
  const _AssignedSpotTile({required this.spot});
  final FishingSpot spot;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: () => context.push(
        '/spots/detail',
        extra: SpotDetailArgs(spot: spot),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ApexColors.primary.withAlpha(36),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.place_rounded,
                size: 20,
                color: ApexColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  if (spot.depthM != null)
                    Text(
                      '${spot.depthM!.toStringAsFixed(1)} m',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SpinBanRow extends StatelessWidget {
  const _SpinBanRow({required this.ban});
  final SpinFishingBan ban;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final isActive = ban.isActiveOn(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? ApexColors.scoreLow.withAlpha(160)
              : c.border,
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.do_not_disturb_on_outlined,
            size: 18,
            color: isActive ? ApexColors.scoreLow : c.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ban.isYearRound
                      ? 'Spinnfischverbot ganzjährig'
                      : 'Spinnfischverbot ${ban.rangeLabel}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                if ((ban.notes ?? '').trim().isNotEmpty)
                  Text(
                    ban.notes!.trim(),
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: ApexColors.scoreLow.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'AKTIV',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: ApexColors.scoreLow,
                  letterSpacing: 0.8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
