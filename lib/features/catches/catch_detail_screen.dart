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

class CatchDetailScreen extends ConsumerWidget {
  const CatchDetailScreen({super.key, required this.entry});
  final CatchEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live-Daten aus Provider holen (falls nachträglich editiert)
    final catchesAsync = ref.watch(catchProvider);
    final all = catchesAsync.valueOrNull ?? const <CatchEntry>[];
    final entry = catchesAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (c) => c.id == this.entry.id,
        orElse: () => this.entry,
      ),
      orElse: () => this.entry,
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: c.background,
      body: Stack(
        children: [
          // Hero: Foto oder Fallback-Gradient (oberer Bildbereich)
          Positioned.fill(
            child: _DetailHeroBackdrop(
              photoFile: photoFile,
              species: entry.species.displayName,
            ),
          ),

          // Bottom-Sheet mit allen Details (anheftet, hochziehbar)
          DraggableScrollableSheet(
            initialChildSize: photoFile != null ? 0.55 : 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            snap: true,
            snapSizes: photoFile != null
                ? const [0.55, 0.95]
                : const [0.7, 0.95],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      // Drag-Handle
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Sheet-Header: Spot · Datum (collapsed sichtbar)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: c.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                AppDateFormats.dayMonthYearHourMinute
                                    .format(entry.caughtAt),
                                style: TextStyle(
                                  fontFamily: 'Rajdhani',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: c.textSecondary,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            if (spot != null) ...[
                              Icon(
                                Icons.place_outlined,
                                size: 14,
                                color: c.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  spot.name,
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
                      ),
                      const SizedBox(height: 14),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hero-Card: Fischart + Gewicht + PB
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isPB
                                      ? ApexColors.scoreMid
                                      : ApexColors.primary.withAlpha(50),
                                  width: isPB ? 1.6 : 1,
                                ),
                                boxShadow: context.isDark
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: isPB
                                              ? ApexColors.scoreMid
                                                  .withAlpha(38)
                                              : c.cardShadow,
                                          blurRadius: isPB ? 16 : 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.species.displayName,
                                          style: TextStyle(
                                            fontFamily: 'Rajdhani',
                                            fontSize: 28,
                                            fontWeight: FontWeight.w700,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isPB) const _PbBadge(),
                                    ],
                                  ),
                                  if (entry.weightG != null)
                                    Text(
                                      entry.weightG! >= 1000
                                          ? '${(entry.weightG! / 1000).toStringAsFixed(2)} kg'
                                          : '${entry.weightG} g',
                                      style: const TextStyle(
                                        fontFamily: 'Rajdhani',
                                        fontSize: 22,
                                        color: ApexColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (entry.lengthCm != null)
                                    Text(
                                      '${entry.lengthCm} cm',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            if (hasCoords) ...[
                              _MiniMap(
                                lat: lat,
                                lng: lng,
                                label: label,
                              ),
                              const SizedBox(height: 16),
                            ],

                            _DetailsGrid(entry: entry),
                            const SizedBox(height: 16),

                            if (spot != null) ...[
                              _SpotDetailsCard(spot: spot),
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
              );
            },
          ),

          // Top-Overlay: Back + Edit + Delete (über Foto)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _OverlayIconButton(
                    icon: Icons.arrow_back,
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  _OverlayIconButton(
                    icon: Icons.edit_outlined,
                    onPressed: () =>
                        context.push('/catches/edit', extra: entry),
                  ),
                  const SizedBox(width: 6),
                  _OverlayIconButton(
                    icon: Icons.delete_outline,
                    iconColor: ApexColors.scoreLow,
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
      await ref.read(catchProvider.notifier).removeCatch(entry.id);
      if (context.mounted) context.pop();
    }
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

class _PbBadge extends StatelessWidget {
  const _PbBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ApexColors.scoreMid,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ApexColors.scoreMid.withAlpha(120),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 14, color: Colors.black),
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
                    urlTemplate: context.isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'de.apex.hooked',
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
