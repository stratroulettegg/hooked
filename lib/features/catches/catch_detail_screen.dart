import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/external_map_launcher.dart';
import '../../shared/services/tile_cache_service.dart';
import '../../shared/widgets/apex_app_bar.dart';

class CatchDetailArgs {
  const CatchDetailArgs({required this.entry, this.siblingIds});
  final CatchEntry entry;
  final List<String>? siblingIds;
}

class CatchDetailScreen extends ConsumerStatefulWidget {
  const CatchDetailScreen({
    super.key,
    required this.entry,
    this.siblingIds,
  });
  final CatchEntry entry;

  /// Optionale gefilterte/geordnete ID-Liste, durch die vertikal geswiped wird.
  /// Wenn null, werden alle Fänge nach Datum absteigend genutzt.
  final List<String>? siblingIds;

  @override
  ConsumerState<CatchDetailScreen> createState() =>
      _CatchDetailScreenState();
}

class _CatchDetailScreenState extends ConsumerState<CatchDetailScreen> {
  late PageController _controller;
  late String _currentId;
  final ValueNotifier<bool> _isSwiping = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _currentId = widget.entry.id;
    final all =
        ref.read(catchProvider).valueOrNull ?? const <CatchEntry>[];
    final sorted = _orderedFor(all);
    final idx = sorted.indexWhere((e) => e.id == widget.entry.id);
    _controller = PageController(initialPage: idx >= 0 ? idx : 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _isSwiping.dispose();
    super.dispose();
  }

  /// Falls eine gefilterte sibling-Liste übergeben wurde, liefere die Fänge
  /// in genau dieser Reihenfolge (nur die, die noch existieren).
  /// Sonst alle Fänge nach Datum absteigend.
  /// Es werden nur Einträge mit Foto behalten — der initiale Eintrag bleibt
  /// in jedem Fall enthalten.
  List<CatchEntry> _orderedFor(List<CatchEntry> all) {
    final ids = widget.siblingIds;
    bool hasPhoto(CatchEntry e) =>
        AppPaths.photoFile(e.photoPath) != null;
    bool keep(CatchEntry e) => e.id == widget.entry.id || hasPhoto(e);
    if (ids == null || ids.isEmpty) {
      final out = [for (final e in all) if (keep(e)) e];
      out.sort((a, b) => b.caughtAt.compareTo(a.caughtAt));
      return out;
    }
    final byId = {for (final e in all) e.id: e};
    return [
      for (final id in ids)
        if (byId[id] != null && keep(byId[id]!)) byId[id]!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final all =
        ref.watch(catchProvider).valueOrNull ?? const <CatchEntry>[];
    final sorted = _orderedFor(all);

    if (sorted.isEmpty) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: const ApexAppBar(),
        body: _CatchDetailContent(
          initialEntry: widget.entry,
          isSwiping: _isSwiping,
        ),
      );
    }

    final currentEntry = sorted.firstWhere(
      (e) => e.id == _currentId,
      orElse: () => widget.entry,
    );

    return Scaffold(
      backgroundColor: c.background,
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push('/catches/edit', extra: currentEntry),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: ApexColors.scoreLow),
            onPressed: () => _confirmDelete(context, currentEntry),
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
          itemCount: sorted.length,
          onPageChanged: (i) =>
              setState(() => _currentId = sorted[i].id),
          itemBuilder: (context, i) => _CatchDetailContent(
            initialEntry: sorted[i],
            isSwiping: _isSwiping,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, CatchEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ApexColors.of(context).surface,
        title: Text(
          'Fang löschen?',
          style: TextStyle(color: ApexColors.of(context).textPrimary),
        ),
        content: Text(
          'Dieser Eintrag wird dauerhaft gelöscht.',
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
      // Erst die Detail-Route poppen, DANN den Eintrag löschen — und zwar
      // erst NACHDEM die Pop-Animation zu Ende ist. Sonst sieht man w\u00e4hrend
      // des Slide-Outs kurz den ge\u00e4nderten PageView-Hintergrund (anderer
      // Fang rutscht an die aktuelle Position) und es flackert.
      final id = entry.id;
      final notifier = ref.read(catchProvider.notifier);
      if (context.mounted) context.pop();
      // Warte bis die Standard-Pop-Transition (~300 ms) durch ist.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await notifier.removeCatch(id);
    }
  }
}

class _CatchDetailContent extends ConsumerStatefulWidget {
  const _CatchDetailContent({
    required this.initialEntry,
    required this.isSwiping,
  });
  final CatchEntry initialEntry;
  final ValueListenable<bool> isSwiping;

  @override
  ConsumerState<_CatchDetailContent> createState() =>
      _CatchDetailContentState();
}

class _CatchDetailContentState extends ConsumerState<_CatchDetailContent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Live-Daten aus Provider holen (falls nachträglich editiert)
    final catchesAsync = ref.watch(catchProvider);
    final all = catchesAsync.valueOrNull ?? const <CatchEntry>[];
    final entry = catchesAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (c) => c.id == widget.initialEntry.id,
        orElse: () => widget.initialEntry,
      ),
      orElse: () => widget.initialEntry,
    );
    final isPB = _isPersonalBest(entry, all);

    // Verknüpfter Spot (wenn vorhanden)
    FishingSpot? spot;
    if (entry.spotId != null) {
      final spots = ref.watch(spotProvider).valueOrNull;
      spot = spots?.where((s) => s.id == entry.spotId).firstOrNull;
    }
    // Koordinaten entweder direkt am Fang oder via verknüpftem Spot
    double? lat = entry.lat;
    double? lng = entry.lng;
    String? label = entry.species.displayName;
    if ((lat == null || lng == null) && spot != null) {
      lat = spot.lat;
      lng = spot.lng;
      label = spot.name;
    }
    final hasCoords = lat != null && lng != null;
    final photoFile = AppPaths.photoFile(entry.photoPath);
    final c = ApexColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final collapsedH = math.max(
          maxH * 0.16,
          photoFile != null ? 150.0 : 0.0,
        );
        final expandedH = maxH * 0.95;
        final sheetH = _expanded ? expandedH : collapsedH;

        return Stack(
          children: [
            // Hero: Foto oder Fallback-Gradient
            Positioned.fill(
              child: _DetailHeroBackdrop(
                photoFile: photoFile,
                species: entry.species.displayName,
                speciesAsset: entry.species.imageAsset,
              ),
            ),

            // Sheet (animiert, Tap-Toggle, kein Drag) — fade-out beim Wischen
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
                          // Tap-Toggle-Header: Drag-Handle + Caption (Spezies, Gewicht/Länge, PB, Datum/Spot)
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
                                  // Drag-Handle visual (zentriert)
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
                                  // Spezies + Gewicht + PB-Chip in einer Zeile
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
                                                entry.species.displayName,
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
                                            if (entry.weightG != null) ...[
                                              const SizedBox(width: 10),
                                              Text(
                                                AppNum.kg(entry.weightG!),
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
                                      if (isPB) ...[
                                        const SizedBox(width: 8),
                                        const _PbBadge(),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Meta: Länge · Datum
                                  Row(
                                    children: [
                                      if (entry.lengthCm != null) ...[
                                        Text(
                                          '${entry.lengthCm} cm',
                                          style: TextStyle(
                                            fontFamily: 'Rajdhani',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: c.textSecondary,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        _MetaDot(color: c.textMuted),
                                      ],
                                      Icon(
                                        Icons.access_time,
                                        size: 13,
                                        color: c.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          AppDateFormats
                                              .dayMonthYearHourMinute
                                              .format(entry.caughtAt),
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'Rajdhani',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // See in eigener Zeile
                                  if (spot != null) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.place_outlined,
                                          size: 13,
                                          color: c.textMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            spot.name,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Rajdhani',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
                                      if (hasCoords) ...[
                                        _MiniMap(
                                          lat: lat!,
                                          lng: lng!,
                                          label: label,
                                        ),
                                        const SizedBox(height: 16),
                                      ],

                                      _DetailsGrid(entry: entry),
                                      const SizedBox(height: 16),

                                      if (spot != null) ...[
                                        _SpotDetailsCard(spot: spot),
                                        const SizedBox(height: 16),
                                      ] else if (hasCoords) ...[
                                        _CreateSpotFromCatchCard(
                                          lat: lat!,
                                          lng: lng!,
                                          suggestedName:
                                              'Spot ${entry.species.displayName}',
                                        ),
                                        const SizedBox(height: 16),
                                      ],

                                      if (entry.notes != null &&
                                          entry.notes!.isNotEmpty) ...[
                                        _SectionCard(
                                          title: 'NOTIZEN',
                                          child: Text(
                                            entry.notes!,
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
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
            ),
          ],
        );
      },
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.entry});
  final CatchEntry entry;

  @override
  Widget build(BuildContext context) {
    final items = <_DetailItem>[
      _DetailItem(
        icon: Icons.access_time,
        label: 'Datum & Zeit',
        value: AppDateFormats.dayMonthYearHourMinute.format(entry.caughtAt),
      ),
      if (entry.lure != null)
        _DetailItem(icon: Icons.straighten, label: 'Köder', value: entry.lure!),
      if (entry.lureColor != null)
        _DetailItem(
          icon: Icons.color_lens_outlined,
          label: 'Farbe',
          value: entry.lureColor!,
        ),
      if (entry.retrieveStyles.isNotEmpty)
        _DetailItem(
          icon: Icons.rotate_right,
          label: 'Technik',
          value: entry.retrieveStyles.map((e) => e.displayName).join(', '),
        ),
      if (entry.depthM != null)
        _DetailItem(
          icon: Icons.water,
          label: 'Tiefe',
          value: '${entry.depthM} m',
        ),
      if (entry.waterTempC != null)
        _DetailItem(
          icon: Icons.thermostat,
          label: 'Wassertemp.',
          value: '${entry.waterTempC}°C',
        ),
      if (entry.weatherDesc != null)
        _DetailItem(
          icon: Icons.wb_sunny_outlined,
          label: 'Wetter',
          value: entry.weatherDesc!,
        ),
      if (entry.drillDurationSec != null)
        _DetailItem(
          icon: Icons.timer_outlined,
          label: 'Kampfdauer',
          value:
              '${entry.drillDurationSec! ~/ 60}:${(entry.drillDurationSec! % 60).toString().padLeft(2, '0')} min',
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ApexColors.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ApexColors.of(context).border),
      ),
      child: Column(
        children: items.map((item) => _DetailRow(item: item)).toList(),
      ),
    );
  }
}

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.item});
  final _DetailItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(item.icon, size: 18, color: ApexColors.primary),
          const SizedBox(width: 12),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 13,
              color: ApexColors.of(context).textMuted,
            ),
          ),
          const Spacer(),
          Text(
            item.value,
            style: TextStyle(
              fontSize: 13,
              color: ApexColors.of(context).textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ApexColors.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ApexColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: ApexColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SpotDetailsCard extends StatelessWidget {
  const _SpotDetailsCard({required this.spot});
  final FishingSpot spot;

  @override
  Widget build(BuildContext context) {
    final rows = <_DetailItem>[
      _DetailItem(icon: Icons.place_outlined, label: 'Spot', value: spot.name),
      if (spot.waterBodyName != null)
        _DetailItem(
          icon: Icons.water,
          label: 'Gewässer',
          value: spot.waterBodyName!,
        ),
      if (spot.depthM != null)
        _DetailItem(
          icon: Icons.water_drop,
          label: 'Tiefe',
          value: '${spot.depthM} m',
        ),
      _DetailItem(
        icon: Icons.location_on_outlined,
        label: 'Koordinaten',
        value: '${spot.lat.toStringAsFixed(5)}, ${spot.lng.toStringAsFixed(5)}',
      ),
      if (spot.structures.isNotEmpty)
        _DetailItem(
          icon: Icons.terrain,
          label: 'Struktur',
          value: spot.structures.map((s) => s.displayName).join(', '),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ApexColors.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ApexColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPOT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: ApexColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 6),
          ...rows.map((item) => _DetailRow(item: item)),
        ],
      ),
    );
  }
}

bool _isPersonalBest(CatchEntry e, List<CatchEntry> all) {
  final sameSpecies = all.where((x) => x.species == e.species);
  if (sameSpecies.isEmpty) return false;
  int score(CatchEntry x) =>
      ((x.weightG ?? 0) * 1000 + (x.lengthCm ?? 0)).toInt();
  final best = sameSpecies.reduce((a, b) => score(a) >= score(b) ? a : b);
  return best.id == e.id && score(e) > 0;
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

class _PbBadge extends StatelessWidget {
  const _PbBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ApexColors.scoreMid,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ApexColors.scoreMid.withAlpha(160),
            blurRadius: 14,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 13, color: Colors.black),
          SizedBox(width: 4),
          Text(
            'PB',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({
    required this.lat,
    required this.lng,
    required this.label,
  });

  final double lat;
  final double lng;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return GestureDetector(
      onTap: () => ExternalMapLauncher.choose(
        context,
        lat: lat,
        lng: lng,
        label: label,
      ),
      child: Container(
        height: 140,
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(lat, lng),
                  initialZoom: 13,
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
                        point: LatLng(lat, lng),
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: ApexColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ApexColors.primary.withAlpha(120),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.set_meal,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surface.withAlpha(230),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new,
                          size: 14, color: ApexColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'IN KARTEN',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
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

class _DetailHeroBackdrop extends StatelessWidget {
  const _DetailHeroBackdrop({
    required this.photoFile,
    required this.species,
    required this.speciesAsset,
  });

  final File? photoFile;
  final String species;
  final String? speciesAsset;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photoFile != null)
            Image.file(photoFile!, fit: BoxFit.cover)
          else
            // Fallback: dezenter Gradient + Spezies-Illustration aus Lexikon
            // (oder gro\u00dfe Typo, falls f\u00fcr die Art kein Asset existiert).
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.surface,
                    c.background,
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: speciesAsset != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
                      child: Opacity(
                        opacity: 0.85,
                        child: Image.asset(
                          speciesAsset!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 80, 24, 120),
                      child: Text(
                        species,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: c.textPrimary.withAlpha(60),
                          height: 1.0,
                        ),
                      ),
                    ),
            ),
          // Gradient-Overlay nach unten für Lesbarkeit der Buttons / Sheet-Übergang
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.25, 0.7, 1.0],
                  colors: [
                    Colors.black.withAlpha(70),
                    Colors.transparent,
                    Colors.transparent,
                    c.background.withAlpha(180),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Karte, die unter dem Mini-Map angezeigt wird, wenn ein Fang Koordinaten,
/// aber (noch) keinen verkn\u00fcpften Spot hat. Vorschlag: aus den Fang-GPS
/// einen neuen Spot anlegen.
class _CreateSpotFromCatchCard extends StatelessWidget {
  const _CreateSpotFromCatchCard({
    required this.lat,
    required this.lng,
    required this.suggestedName,
  });

  final double lat;
  final double lng;
  final String suggestedName;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ApexColors.primary.withAlpha(40),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.add_location_alt_outlined,
              color: ApexColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spot aus diesem Fang',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Standort als neuen Angel-Spot speichern',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => context.push(
              '/spots/add',
              extra: <String, dynamic>{
                'lat': lat,
                'lng': lng,
                'name': suggestedName,
              },
            ),
            style: TextButton.styleFrom(
              foregroundColor: ApexColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text(
              'ANLEGEN',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
