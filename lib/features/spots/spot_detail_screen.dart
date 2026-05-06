import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../catches/catch_detail_screen.dart' show CatchDetailArgs;
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/external_map_launcher.dart';
import '../../shared/services/tile_cache_service.dart';
import '../../shared/widgets/apex_app_bar.dart';

class SpotDetailArgs {
  const SpotDetailArgs({required this.spot, this.siblingIds});
  final FishingSpot spot;
  final List<String>? siblingIds;
}

class SpotDetailScreen extends ConsumerStatefulWidget {
  const SpotDetailScreen({
    super.key,
    required this.spot,
    this.siblingIds,
  });
  final FishingSpot spot;

  /// Optionale gefilterte/geordnete ID-Liste, durch die vertikal geswiped wird.
  /// Wenn null, werden alle Spots nach createdAt absteigend genutzt.
  final List<String>? siblingIds;

  @override
  ConsumerState<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends ConsumerState<SpotDetailScreen> {
  late PageController _controller;
  late String _currentId;
  final ValueNotifier<bool> _isSwiping = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _currentId = widget.spot.id;
    final all =
        ref.read(spotProvider).valueOrNull ?? const <FishingSpot>[];
    final ordered = _orderedFor(all);
    final idx = ordered.indexWhere((s) => s.id == widget.spot.id);
    _controller = PageController(initialPage: idx >= 0 ? idx : 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _isSwiping.dispose();
    super.dispose();
  }

  List<FishingSpot> _orderedFor(List<FishingSpot> all) {
    final ids = widget.siblingIds;
    bool hasPhoto(FishingSpot s) =>
        AppPaths.photoFile(s.photoPath) != null;
    // Aktueller Spot bleibt immer enthalten — auch ohne Foto.
    bool keep(FishingSpot s) => s.id == widget.spot.id || hasPhoto(s);
    if (ids == null || ids.isEmpty) {
      final out = [for (final s in all) if (keep(s)) s];
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    }
    final byId = {for (final s in all) s.id: s};
    return [
      for (final id in ids)
        if (byId[id] != null && keep(byId[id]!)) byId[id]!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final all =
        ref.watch(spotProvider).valueOrNull ?? const <FishingSpot>[];
    final ordered = _orderedFor(all);

    if (ordered.isEmpty) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: const ApexAppBar(),
        body: _SpotDetailContent(
          initialSpot: widget.spot,
          isSwiping: _isSwiping,
        ),
      );
    }

    final currentSpot = ordered.firstWhere(
      (s) => s.id == _currentId,
      orElse: () => widget.spot,
    );

    return Scaffold(
      backgroundColor: c.background,
      appBar: ApexAppBar(
        extraActions: [
          _OfflineDownloadButton(spot: currentSpot),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/spots/edit', extra: currentSpot),
          ),
          IconButton(
            icon:
                const Icon(Icons.delete_outline, color: ApexColors.scoreLow),
            onPressed: () => _confirmDelete(context, currentSpot),
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0) return false;
          if (n is ScrollStartNotification) {
            _isSwiping.value = true;
          } else if (n is ScrollEndNotification) {
            _isSwiping.value = false;
          }
          return false;
        },
        child: PageView.builder(
          controller: _controller,
          scrollDirection: Axis.vertical,
          itemCount: ordered.length,
          onPageChanged: (i) => setState(() => _currentId = ordered[i].id),
          itemBuilder: (context, i) => _SpotDetailContent(
            initialSpot: ordered[i],
            isSwiping: _isSwiping,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, FishingSpot spot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ApexColors.of(context).surface,
        title: Text(
          'Spot löschen?',
          style: TextStyle(color: ApexColors.of(context).textPrimary),
        ),
        content: Text(
          'Dieser Spot wird dauerhaft gelöscht.',
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
      // Erst die Detail-Route poppen, DANN den Eintrag löschen — sonst
      // baut der Screen während der Slide-Out-Animation kurz den
      // "keine Spots"-Fallback auf und es flackert. Analog zum Catch-
      // Detail-Flow.
      if (context.mounted) context.pop();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await ref.read(spotProvider.notifier).removeSpot(spot.id);
    }
  }
}

class _SpotDetailContent extends ConsumerStatefulWidget {
  const _SpotDetailContent({
    required this.initialSpot,
    required this.isSwiping,
  });
  final FishingSpot initialSpot;
  final ValueListenable<bool> isSwiping;

  @override
  ConsumerState<_SpotDetailContent> createState() =>
      _SpotDetailContentState();
}

class _SpotDetailContentState extends ConsumerState<_SpotDetailContent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final spotsAsync = ref.watch(spotProvider);
    final spot = spotsAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (s) => s.id == widget.initialSpot.id,
        orElse: () => widget.initialSpot,
      ),
      orElse: () => widget.initialSpot,
    );

    final allCatches =
        ref.watch(catchProvider).valueOrNull ?? const [];
    final spotCatches =
        allCatches.where((c) => c.spotId == spot.id).toList();
    final catchCount = spotCatches.length;

    // Arten-Aufschlüsselung: nach Häufigkeit absteigend
    final speciesCounts = <FishSpecies, int>{};
    for (final entry in spotCatches) {
      speciesCounts[entry.species] =
          (speciesCounts[entry.species] ?? 0) + 1;
    }
    final speciesSorted = speciesCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final photoFile = AppPaths.photoFile(spot.photoPath);
    final c = ApexColors.of(context);

    return LayoutBuilder(
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
            // Hero-Backdrop: Foto ODER Vollbild-Karte
            Positioned.fill(
              child: _SpotHeroBackdrop(spot: spot, photoFile: photoFile),
            ),
            // Sheet
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: sheetH,
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.isSwiping,
                builder: (context, swiping, child) {
                  return IgnorePointer(
                    ignoring: swiping,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      offset: swiping
                          ? const Offset(0, 1)
                          : Offset.zero,
                      child: child,
                    ),
                  );
                },
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
                            // Tap-Toggle-Header: Drag-Handle + Caption
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setState(() => _expanded = !_expanded),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 8, 20, 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Center(
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                            milliseconds: 220),
                                        width: _expanded ? 56 : 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: _expanded
                                              ? ApexColors.primary
                                                  .withAlpha(180)
                                              : c.border,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Spot-Name + Tiefe
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
                                                  spot.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: 'Rajdhani',
                                                    fontSize: 28,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    height: 1.05,
                                                    letterSpacing: 0.3,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              if (spot.depthM != null) ...[
                                                const SizedBox(width: 10),
                                                Text(
                                                  '${spot.depthM} m',
                                                  style: const TextStyle(
                                                    fontFamily: 'Rajdhani',
                                                    fontSize: 22,
                                                    color:
                                                        ApexColors.primary,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (catchCount > 0) ...[
                                          const SizedBox(width: 8),
                                          _CatchCountChip(
                                              count: catchCount),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Meta: Gewässer · Struktur
                                    if (spot.waterBodyName != null ||
                                        spot.structures.isNotEmpty)
                                      Row(
                                        children: [
                                          if (spot.waterBodyName !=
                                              null) ...[
                                            Icon(
                                              Icons.water,
                                              size: 13,
                                              color: c.textMuted,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                spot.waterBodyName!,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontFamily: 'Rajdhani',
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  color: c.textSecondary,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (spot.waterBodyName != null &&
                                              spot.structures.isNotEmpty)
                                            _MetaDot(color: c.textMuted),
                                          if (spot.structures.isNotEmpty)
                                            Flexible(
                                              child: Text(
                                                spot.structures
                                                    .map((s) =>
                                                        s.displayName)
                                                    .join(', '),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontFamily: 'Rajdhani',
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            ),
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
                                        horizontal: 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Karte (immer als Mini-Map im Sheet — auch wenn Backdrop = Karte)
                                        _SpotMiniMap(spot: spot),
                                        const SizedBox(height: 16),
                                        // Spot-Info
                                        Container(
                                          padding:
                                              const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: c.surface,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color: c.border),
                                          ),
                                          child: Column(
                                            children: [
                                              if (spot.waterBodyName !=
                                                  null)
                                                _InfoRow(
                                                  icon: Icons.water,
                                                  label: 'Gewässer',
                                                  value: spot.waterBodyName!,
                                                ),
                                              if (spot.depthM != null)
                                                _InfoRow(
                                                  icon: Icons.water_drop,
                                                  label: 'Tiefe',
                                                  value: '${spot.depthM} m',
                                                ),
                                              _InfoRow(
                                                icon: Icons
                                                    .location_on_outlined,
                                                label: 'Koordinaten',
                                                value:
                                                    '${spot.lat.toStringAsFixed(5)}, ${spot.lng.toStringAsFixed(5)}',
                                              ),
                                              if (spot.structures.isNotEmpty)
                                                _InfoRow(
                                                  icon: Icons.terrain,
                                                  label: 'Struktur',
                                                  value: spot.structures
                                                      .map((s) =>
                                                          s.displayName)
                                                      .join(', '),
                                                ),
                                              if (catchCount > 0)
                                                _InfoRow(
                                                  icon: Icons.set_meal,
                                                  label: 'Fänge',
                                                  value: '$catchCount',
                                                ),
                                            ],
                                          ),
                                        ),
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
                                                _SpeciesChip(
                                                  species: e.key,
                                                  count: e.value,
                                                  onTap: () {
                                                    final ofSpecies = [
                                                      for (final ce
                                                          in spotCatches)
                                                        if (ce.species ==
                                                            e.key)
                                                          ce,
                                                    ]..sort((a, b) => b
                                                        .caughtAt
                                                        .compareTo(
                                                            a.caughtAt));
                                                    if (ofSpecies.isEmpty) {
                                                      return;
                                                    }
                                                    context.push(
                                                      '/catches/detail',
                                                      extra:
                                                          CatchDetailArgs(
                                                        entry:
                                                            ofSpecies.first,
                                                        siblingIds: [
                                                          for (final ce
                                                              in ofSpecies)
                                                            ce.id,
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        // Saisonnotizen
                                        if (spot
                                            .seasonNotes.isNotEmpty) ...[
                                          Text(
                                            'SAISONNOTIZEN',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.5,
                                              color: c.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...Season.values.map((season) {
                                            final note = spot.seasonNotes
                                                .where((sn) =>
                                                    sn.season == season)
                                                .firstOrNull;
                                            if (note == null) {
                                              return const SizedBox
                                                  .shrink();
                                            }
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.only(
                                                      bottom: 8),
                                              child: _SeasonNoteCard(
                                                  season: season,
                                                  note: note),
                                            );
                                          }),
                                          const SizedBox(height: 16),
                                        ],
                                        // Notizen
                                        if (spot.notes != null &&
                                            spot.notes!.isNotEmpty) ...[
                                          Container(
                                            padding:
                                                const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: c.surface,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                  color: c.border),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'NOTIZEN',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    letterSpacing: 1.5,
                                                    color: c.textMuted,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  spot.notes!,
                                                  style: TextStyle(
                                                    color: c.textPrimary,
                                                    height: 1.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 32),
                                        ] else
                                          const SizedBox(height: 32),
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
            ),
          ],
        );
      },
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ApexColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ApexColors.primary.withAlpha(140),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.set_meal, size: 13, color: Colors.black),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeciesChip extends StatelessWidget {
  const _SpeciesChip({
    required this.species,
    required this.count,
    required this.onTap,
  });
  final FishSpecies species;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                species.emoji,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 5),
              Text(
                species.displayName,
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: ApexColors.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
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

class _SpotHeroBackdrop extends StatelessWidget {
  const _SpotHeroBackdrop({required this.spot, required this.photoFile});
  final FishingSpot spot;
  final File? photoFile;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    final base = photoFile != null
        ? Image.file(photoFile!, fit: BoxFit.cover)
        : _MapBackdrop(spot: spot);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          base,
          // Top fade for app bar legibility
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
                    colors: [
                      Colors.black.withAlpha(120),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom fade for sheet legibility
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
                    colors: [
                      Colors.transparent,
                      c.background.withAlpha(180),
                    ],
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
  const _MapBackdrop({required this.spot});
  final FishingSpot spot;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(spot.lat, spot.lng),
        initialZoom: 13,
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
            Marker(
              point: LatLng(spot.lat, spot.lng),
              width: 44,
              height: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: ApexColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ApexColors.of(context).background,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ApexColors.primary.withAlpha(120),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.location_on,
                  color: ApexColors.of(context).background,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SpotMiniMap extends StatelessWidget {
  const _SpotMiniMap({required this.spot});
  final FishingSpot spot;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    return GestureDetector(
      onTap: () => ExternalMapLauncher.choose(
        context,
        lat: spot.lat,
        lng: spot.lng,
        label: spot.name,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 180,
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(spot.lat, spot.lng),
                  initialZoom: 13.5,
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
                    retinaMode:
                        MediaQuery.devicePixelRatioOf(context) > 1.5,
                    tileProvider: TileCacheService.instance.provider,
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(spot.lat, spot.lng),
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: ApexColors.primary,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: c.background, width: 2),
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
                            size: 24,
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
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surface.withAlpha(220),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined,
                          size: 14, color: ApexColors.primary),
                      SizedBox(width: 6),
                      Text(
                        'IN KARTEN',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: ApexColors.primary,
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

// ─── Offline-Download-Button ──────────────────────────────────────────────────

class _OfflineDownloadButton extends StatefulWidget {
  const _OfflineDownloadButton({required this.spot});
  final FishingSpot spot;

  @override
  State<_OfflineDownloadButton> createState() => _OfflineDownloadButtonState();
}

class _OfflineDownloadButtonState extends State<_OfflineDownloadButton> {
  bool _downloading = false;
  bool _done = false;
  int _progress = 0;
  int _total = 0;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _done = false;
      _progress = 0;
    });

    await TileCacheService.instance.downloadForSpot(
      lat: widget.spot.lat,
      lng: widget.spot.lng,
      isDark: context.isDark,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _progress = done;
            _total = total;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _downloading = false;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_downloading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: _total > 0 ? _progress / _total : null,
                strokeWidth: 2.5,
                color: ApexColors.primary,
              ),
              if (_total > 0)
                Center(
                  child: Text(
                    '${(_progress / _total * 100).round()}',
                    style: const TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      color: ApexColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(
        _done ? Icons.offline_pin : Icons.download_for_offline_outlined,
        color: _done ? ApexColors.primary : null,
      ),
      tooltip: _done ? 'Offline gespeichert' : 'Offline speichern',
      onPressed: _done ? null : _download,
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

class _SeasonNoteCard extends StatelessWidget {
  const _SeasonNoteCard({required this.season, required this.note});
  final Season season;
  final SeasonNote note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ApexColors.of(context).surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ApexColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            season.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ApexColors.primary,
            ),
          ),
          if (note.depthNote != null) ...[
            const SizedBox(height: 4),
            Text(
              'Tiefe: ${note.depthNote}',
              style: TextStyle(
                fontSize: 12,
                color: ApexColors.of(context).textSecondary,
              ),
            ),
          ],
          if (note.tacticNote != null) ...[
            const SizedBox(height: 4),
            Text(
              'Taktik: ${note.tacticNote}',
              style: TextStyle(
                fontSize: 12,
                color: ApexColors.of(context).textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
