import 'package:flutter/material.dart';
import '../../shared/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/engines/spot_heatmap_engine.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/h_scroll_with_hint.dart';
import '../../shared/services/tile_cache_service.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/swipe_to_delete.dart';
import 'spot_detail_screen.dart' show SpotDetailArgs;

class SpotListScreen extends ConsumerStatefulWidget {
  const SpotListScreen({super.key});

  @override
  ConsumerState<SpotListScreen> createState() => _SpotListScreenState();
}

class _SpotListScreenState extends ConsumerState<SpotListScreen> {
  StructureType? _structure;
  _SpotActivity _activity = _SpotActivity.all;
  bool _seasonTipOnly = false;
  _SpotSort _sort = _SpotSort.newest;
  bool _twoColumns = false;

  @override
  Widget build(BuildContext context) {
    final spotsAsync = ref.watch(spotProvider);
    final allCatches = ref.watch(catchProvider).valueOrNull ?? const [];

    // Catches pro Spot vorberechnen (für Filter + Sort)
    final catchCount = <String, int>{};
    for (final cn in allCatches) {
      final id = cn.spotId;
      if (id != null) catchCount[id] = (catchCount[id] ?? 0) + 1;
    }

    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Karte',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _SpotsMapScreen(spots: spotsAsync.value ?? []),
              ),
            ),
          ),
        ],
      ),
      body: spotsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ApexColors.primary),
        ),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (spots) {
          if (spots.isEmpty) {
            return _EmptyState(onAdd: () => context.push('/spots/add'));
          }

          final currentSeason = SeasonExt.current();

          // ── Filter anwenden ─────────────────────────────────────────────
          var filtered = spots.where((s) {
            if (_structure != null && !s.structures.contains(_structure)) {
              return false;
            }
            final cnt = catchCount[s.id] ?? 0;
            switch (_activity) {
              case _SpotActivity.all:
                break;
              case _SpotActivity.withCatches:
                if (cnt == 0) return false;
                break;
              case _SpotActivity.hotspots:
                if (cnt < 5) return false;
                break;
            }
            if (_seasonTipOnly &&
                !s.seasonNotes.any((n) => n.season == currentSeason)) {
              return false;
            }
            return true;
          }).toList();

          // ── Sortieren ───────────────────────────────────────────────────
          switch (_sort) {
            case _SpotSort.newest:
              filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              break;
            case _SpotSort.mostCatches:
              filtered.sort(
                (a, b) =>
                    (catchCount[b.id] ?? 0).compareTo(catchCount[a.id] ?? 0),
              );
              break;
            case _SpotSort.deepest:
              filtered.sort(
                (a, b) => (b.depthM ?? -1).compareTo(a.depthM ?? -1),
              );
              break;
            case _SpotSort.nameAsc:
              filtered.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
              break;
          }

          final availableStructures = <StructureType>{
            for (final s in spots) ...s.structures,
          }.toList()..sort((a, b) => a.displayName.compareTo(b.displayName));

          // Gruppierung nach Gewässer (nur bei Standard-Sortierung sinnvoll).
          final grouped = _sort == _SpotSort.newest
              ? _groupByWater(filtered, catchCount)
              : null;

          final hasFilter =
              _structure != null ||
              _activity != _SpotActivity.all ||
              _seasonTipOnly;

          // ID-Liste in aktueller Filter-/Sort-Reihenfolge — wird an die
          // Detail-Ansicht durchgereicht.
          final siblingIds = [for (final s in filtered) s.id];

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _SpotOverviewMap(spots: spots)),
              SliverToBoxAdapter(
                child: _SpotFilterBar(
                  structure: _structure,
                  activity: _activity,
                  seasonTipOnly: _seasonTipOnly,
                  sort: _sort,
                  twoColumns: _twoColumns,
                  availableStructures: availableStructures,
                  onChanged: (st, ac, se, so) => setState(() {
                    _structure = st;
                    _activity = ac;
                    _seasonTipOnly = se;
                    _sort = so;
                  }),
                  onToggleColumns: () =>
                      setState(() => _twoColumns = !_twoColumns),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoSpotResults(
                    onReset: () => setState(() {
                      _structure = null;
                      _activity = _SpotActivity.all;
                      _seasonTipOnly = false;
                      _sort = _SpotSort.newest;
                    }),
                  ),
                )
              else if (grouped != null)
                ..._buildGroupedSlivers(grouped, catchCount, siblingIds)
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: _twoColumns
                      ? _flatGridSliver(filtered, siblingIds)
                      : _flatListSliver(filtered, siblingIds),
                ),
              if (hasFilter && filtered.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Center(
                      child: Text(
                        '${filtered.length} von ${spots.length} Spots',
                        style: TextStyle(
                          fontSize: 11,
                          color: ApexColors.of(context).textMuted,
                          letterSpacing: 0.6,
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

  List<Widget> _buildGroupedSlivers(
    List<_WaterGroup> groups,
    Map<String, int> catchCount,
    List<String> siblingIds,
  ) {
    final slivers = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _WaterHeaderDelegate(
            group: group,
            totalCatches: group.spots.fold(
              0,
              (sum, s) => sum + (catchCount[s.id] ?? 0),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            g == groups.length - 1 ? 32 : 8,
          ),
          sliver: _twoColumns
              ? _flatGridSliver(group.spots, siblingIds)
              : _flatListSliver(group.spots, siblingIds),
        ),
      );
    }
    return slivers;
  }

  Widget _flatListSliver(List<FishingSpot> spots, List<String> siblingIds) {
    return SliverList.builder(
      itemCount: spots.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SwipeToDelete(
          dismissKey: ValueKey('spot-${spots[i].id}'),
          confirmTitle: 'Spot löschen?',
          confirmMessage:
              'Der Spot „${spots[i].name}“ wird unwiderruflich gelöscht.',
          onDelete: () =>
              ref.read(spotProvider.notifier).removeSpot(spots[i].id),
          child: _SpotCard(
            spot: spots[i],
            compact: false,
            onTap: () => context.push(
              '/spots/detail',
              extra: SpotDetailArgs(spot: spots[i], siblingIds: siblingIds),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flatGridSliver(List<FishingSpot> spots, List<String> siblingIds) {
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: spots.length,
      itemBuilder: (_, i) => _SpotCard(
        spot: spots[i],
        compact: true,
        onTap: () => context.push(
          '/spots/detail',
          extra: SpotDetailArgs(spot: spots[i], siblingIds: siblingIds),
        ),
      ),
    );
  }
}

// ─── Gewässer-Gruppierung ────────────────────────────────────────────────────

class _WaterGroup {
  _WaterGroup({required this.label, required this.spots});
  final String label;
  final List<FishingSpot> spots;
}

List<_WaterGroup> _groupByWater(
  List<FishingSpot> sorted,
  Map<String, int> catchCount,
) {
  final byKey = <String, _WaterGroup>{};
  final order = <String>[];
  for (final s in sorted) {
    final key = (s.waterBodyName?.trim().isNotEmpty ?? false)
        ? s.waterBodyName!.trim()
        : '__none__';
    final label = key == '__none__' ? 'Ohne Gewässer' : key;
    final g = byKey.putIfAbsent(key, () {
      order.add(key);
      return _WaterGroup(label: label, spots: []);
    });
    g.spots.add(s);
  }
  return [for (final k in order) byKey[k]!];
}

class _WaterHeaderDelegate extends SliverPersistentHeaderDelegate {
  _WaterHeaderDelegate({required this.group, required this.totalCatches});
  final _WaterGroup group;
  final int totalCatches;

  static const double _height = 36;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final c = ApexColors.of(context);
    final spotCount = group.spots.length;
    final catchPart = totalCatches > 0
        ? '$totalCatches ${totalCatches == 1 ? 'Fang' : 'Fänge'}'
        : null;
    return Container(
      height: _height,
      color: c.background,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(Icons.water_drop_outlined, size: 14, color: c.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              group.label,
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
            catchPart != null ? '$spotCount · $totalCatches' : '$spotCount',
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
  bool shouldRebuild(covariant _WaterHeaderDelegate old) =>
      old.group.label != group.label ||
      old.group.spots.length != group.spots.length ||
      old.totalCatches != totalCatches;
}

class _SpotOverviewMap extends StatefulWidget {
  const _SpotOverviewMap({required this.spots});
  final List<FishingSpot> spots;

  @override
  State<_SpotOverviewMap> createState() => _SpotOverviewMapState();
}

class _SpotOverviewMapState extends State<_SpotOverviewMap> {
  final _mapController = MapController();
  double _zoom = 10.0;

  static double _markerSize(double zoom) =>
      (24 + (zoom - 10) * 2.5).clamp(16, 40).toDouble();

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final points = widget.spots
        .map((s) => LatLng(s.lat, s.lng))
        .toList(growable: false);

    final cameraFit = points.length == 1
        ? null
        : CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(36),
          );

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
            initialZoom: 10,
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
              markers: widget.spots
                  .map(
                    (s) => Marker(
                      point: LatLng(s.lat, s.lng),
                      width: _markerSize(_zoom),
                      height: _markerSize(_zoom),
                      child: GestureDetector(
                        onTap: () => context.push('/spots/detail', extra: s),
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
                            Icons.location_on,
                            color: c.background,
                            size: _markerSize(_zoom) * 0.55,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotCard extends ConsumerWidget {
  const _SpotCard({
    required this.spot,
    required this.onTap,
    this.compact = false,
  });
  final FishingSpot spot;
  final VoidCallback onTap;
  final bool compact;

  static const _hotspotThreshold = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final currentSeason = SeasonExt.current();
    final seasonNote = spot.seasonNotes
        .where((sn) => sn.season == currentSeason)
        .firstOrNull;

    final allCatches = ref.watch(catchProvider).valueOrNull ?? const [];
    final spotCatches = allCatches.where((cn) => cn.spotId == spot.id).toList();
    final catchCount = spotCatches.length;
    final isHotspot = catchCount >= _hotspotThreshold;

    // Rechte Card-Ecken während des Swipes eckig.
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
            color: isHotspot ? ApexColors.scoreMid.withAlpha(160) : c.border,
            width: isHotspot ? 1.6 : 1,
          ),
          boxShadow: context.isDark
              ? []
              : [
                  BoxShadow(
                    color: isHotspot
                        ? ApexColors.scoreMid.withAlpha(40)
                        : c.cardShadow,
                    blurRadius: isHotspot ? 14 : 10,
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
                        final file = AppPaths.photoFile(spot.photoPath);
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
                        return _spotFallbackBackground();
                      },
                    ),
                    // Top-Right: Hotspot-Badge
                    if (isHotspot)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: ApexColors.scoreMid,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(70),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department,
                                size: 13,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'HOTSPOT',
                                style: TextStyle(
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
                    // Top-Left: Hinweis bei fehlendem Foto
                    if (spot.photoPath == null ||
                        AppPaths.photoFile(spot.photoPath) == null)
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
              // ── Header: Name + Tiefe ──────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 14,
                  compact ? 9 : 12,
                  compact ? 10 : 14,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: compact ? 16 : 19,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (spot.waterBodyName != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              spot.waterBodyName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 11 : 12,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (spot.depthM != null && !compact) ...[
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppNum.meters(spot.depthM!),
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ApexColors.primary,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            'TIEFE',
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
                  ],
                ),
              ),
              // ── Strukturen-Badges ─────────────────────────────────────
              if (spot.structures.isNotEmpty && !compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final s in spot.structures)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: c.surfaceVariant,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: c.border),
                          ),
                          child: Text(
                            s.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textSecondary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              // ── Footer: Fänge-Count + Saison-Hinweis ──────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 14,
                  8,
                  compact ? 10 : 14,
                  compact ? 10 : 12,
                ),
                child: Wrap(
                  spacing: compact ? 8 : 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SpotFooterChip(
                      icon: Icons.set_meal,
                      text: catchCount == 0
                          ? (compact ? '0' : 'Noch kein Fang')
                          : compact
                          ? '$catchCount'
                          : catchCount == 1
                          ? '1 Fang'
                          : '$catchCount Fänge',
                      iconColor: catchCount > 0
                          ? ApexColors.primary
                          : c.textMuted,
                      muted: catchCount == 0,
                    ),
                    if (compact && spot.depthM != null)
                      _SpotFooterChip(
                        icon: Icons.height,
                        text: AppNum.meters(spot.depthM!),
                        iconColor: ApexColors.primary,
                      ),
                    if (seasonNote != null && !compact)
                      _SpotFooterChip(
                        icon: Icons.eco_outlined,
                        text: '${currentSeason.displayName}-Tipp',
                        iconColor: ApexColors.primary,
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

Widget _spotFallbackBackground() {
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
    child: const Center(
      child: Icon(Icons.location_on, size: 56, color: Colors.white70),
    ),
  );
}

class _SpotFooterChip extends StatelessWidget {
  const _SpotFooterChip({
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
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: muted ? c.textMuted : c.textSecondary,
              fontWeight: FontWeight.w600,
              fontStyle: muted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Filterbar / Sort / Picker ───────────────────────────────────────────────

enum _SpotActivity {
  all('Alle', Icons.filter_list),
  withCatches('Mit Fängen', Icons.set_meal),
  hotspots('Hotspots', Icons.local_fire_department);

  const _SpotActivity(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _SpotSort {
  newest('Neueste zuerst', 'Neueste'),
  mostCatches('Meiste Fänge', 'Fänge'),
  deepest('Tiefste zuerst', 'Tiefe'),
  nameAsc('Name A–Z', 'Name');

  const _SpotSort(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}

class _SpotFilterBar extends StatelessWidget {
  const _SpotFilterBar({
    required this.structure,
    required this.activity,
    required this.seasonTipOnly,
    required this.sort,
    required this.twoColumns,
    required this.availableStructures,
    required this.onChanged,
    required this.onToggleColumns,
  });

  final StructureType? structure;
  final _SpotActivity activity;
  final bool seasonTipOnly;
  final _SpotSort sort;
  final bool twoColumns;
  final List<StructureType> availableStructures;
  final void Function(
    StructureType? structure,
    _SpotActivity activity,
    bool seasonTipOnly,
    _SpotSort sort,
  )
  onChanged;
  final VoidCallback onToggleColumns;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final hasAny =
        structure != null ||
        activity != _SpotActivity.all ||
        seasonTipOnly ||
        sort != _SpotSort.newest;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: HScrollWithHint(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _SpotFilterChip(
                    icon: Icons.terrain,
                    label: structure?.displayName ?? 'Struktur',
                    active: structure != null,
                    onTap: () async {
                      if (availableStructures.isEmpty) {
                        AppToast.show(
                          context,
                          'Noch keine Strukturen an deinen Spots',
                        );
                        return;
                      }
                      final picked = await showModalBottomSheet<StructureType>(
                        context: context,
                        showDragHandle: true,
                        backgroundColor: c.surface,
                        builder: (ctx) => _SpotPickerSheet<StructureType>(
                          title: 'Struktur',
                          items: availableStructures,
                          selected: structure,
                          labelOf: (s) => s.displayName,
                        ),
                      );
                      if (picked == null && structure != null) return;
                      onChanged(picked, activity, seasonTipOnly, sort);
                    },
                    onClear: structure != null
                        ? () => onChanged(null, activity, seasonTipOnly, sort)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _SpotFilterChip(
                    icon: activity.icon,
                    label: activity == _SpotActivity.all
                        ? 'Aktivität'
                        : activity.label,
                    active: activity != _SpotActivity.all,
                    onTap: () async {
                      final picked = await showModalBottomSheet<_SpotActivity>(
                        context: context,
                        showDragHandle: true,
                        backgroundColor: c.surface,
                        builder: (ctx) => _SpotPickerSheet<_SpotActivity>(
                          title: 'Aktivität',
                          items: _SpotActivity.values,
                          selected: activity,
                          labelOf: (a) => a.label,
                        ),
                      );
                      if (picked == null) return;
                      onChanged(structure, picked, seasonTipOnly, sort);
                    },
                    onClear: activity != _SpotActivity.all
                        ? () => onChanged(
                            structure,
                            _SpotActivity.all,
                            seasonTipOnly,
                            sort,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _SpotFilterChip(
                    icon: Icons.eco_outlined,
                    label: 'Saison-Tipp',
                    active: seasonTipOnly,
                    isToggle: true,
                    onTap: () =>
                        onChanged(structure, activity, !seasonTipOnly, sort),
                  ),
                  const SizedBox(width: 8),
                  _SpotFilterChip(
                    icon: Icons.sort,
                    label: sort.shortLabel,
                    active: sort != _SpotSort.newest,
                    onTap: () async {
                      final picked = await showModalBottomSheet<_SpotSort>(
                        context: context,
                        showDragHandle: true,
                        backgroundColor: c.surface,
                        builder: (ctx) => _SpotPickerSheet<_SpotSort>(
                          title: 'Sortieren nach',
                          items: _SpotSort.values,
                          selected: sort,
                          labelOf: (s) => s.label,
                        ),
                      );
                      if (picked == null) return;
                      onChanged(structure, activity, seasonTipOnly, picked);
                    },
                    onClear: sort != _SpotSort.newest
                        ? () => onChanged(
                            structure,
                            activity,
                            seasonTipOnly,
                            _SpotSort.newest,
                          )
                        : null,
                  ),
                  if (hasAny) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => onChanged(
                        null,
                        _SpotActivity.all,
                        false,
                        _SpotSort.newest,
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Zurücksetzen'),
                      style: TextButton.styleFrom(
                        foregroundColor: c.textSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SpotFilterChip(
            icon: Icons.grid_view,
            label: '2 Spalten',
            active: twoColumns,
            isToggle: true,
            onTap: onToggleColumns,
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _SpotFilterChip extends StatelessWidget {
  const _SpotFilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
    this.isToggle = false,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool isToggle;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? ApexColors.primary.withAlpha(28) : c.surface,
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
              size: 16,
              color: active ? ApexColors.primary : c.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? ApexColors.primary : c.textPrimary,
              ),
            ),
            if (isToggle) ...[
              const SizedBox(width: 4),
              Icon(
                active ? Icons.check : Icons.circle_outlined,
                size: 14,
                color: active ? ApexColors.primary : c.textMuted,
              ),
            ] else if (active && onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: ApexColors.primary),
              ),
            ] else if (!active) ...[
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 16, color: c.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpotPickerSheet<T> extends StatelessWidget {
  const _SpotPickerSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.labelOf,
  });
  final String title;
  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final isSel = item == selected;
                  return ListTile(
                    title: Text(labelOf(item)),
                    trailing: isSel
                        ? const Icon(Icons.check, color: ApexColors.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, item),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NoSpotResults extends StatelessWidget {
  const _NoSpotResults({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: c.textMuted),
            const SizedBox(height: 12),
            Text(
              'Keine Spots passen zu den Filtern',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Filter zurücksetzen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map, size: 64, color: c.textMuted),
            const SizedBox(height: 16),
            Text(
              'Noch keine Spots',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lege deinen ersten Geheimspot an: Position markieren, Strukturen notieren, später wiederfinden.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Spot anlegen'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Vollbild-Karte aller Spots ───────────────────────────────────────────────

class _SpotsMapScreen extends ConsumerStatefulWidget {
  const _SpotsMapScreen({required this.spots});
  final List<FishingSpot> spots;

  @override
  ConsumerState<_SpotsMapScreen> createState() => _SpotsMapScreenState();
}

class _SpotsMapScreenState extends ConsumerState<_SpotsMapScreen> {
  final _mapController = MapController();
  FishingSpot? _selected;
  HeatmapCell? _selectedCell;
  double _zoom = 10.0;
  bool _showHeatmap = true;
  HeatmapFilter _filter = const HeatmapFilter();

  static double _markerSize(double zoom) =>
      (38 + (zoom - 10) * 3).clamp(18, 52).toDouble();

  /// Radius einer Heatmap-Zelle in Pixeln, abhängig vom Zoom.
  static double _cellRadius(double zoom) =>
      (12 + (zoom - 10) * 6).clamp(8, 60).toDouble();

  /// Farbe für einen normalisierten Score (0..1) — kalt → warm → heiß.
  static Color _scoreColor(double s) {
    if (s <= 0.5) {
      return Color.lerp(
        ApexColors.scoreLow,
        ApexColors.scoreMid,
        (s / 0.5).clamp(0.0, 1.0),
      )!;
    }
    return Color.lerp(
      ApexColors.scoreMid,
      ApexColors.scoreHigh,
      ((s - 0.5) / 0.5).clamp(0.0, 1.0),
    )!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
  }

  void _fitAll() {
    if (widget.spots.isEmpty) return;
    if (widget.spots.length == 1) {
      _mapController.move(
        LatLng(widget.spots.first.lat, widget.spots.first.lng),
        14,
      );
      return;
    }
    final lats = widget.spots.map((s) => s.lat);
    final lngs = widget.spots.map((s) => s.lng);
    final bounds = LatLngBounds(
      LatLng(
        lats.reduce((a, b) => a < b ? a : b),
        lngs.reduce((a, b) => a < b ? a : b),
      ),
      LatLng(
        lats.reduce((a, b) => a > b ? a : b),
        lngs.reduce((a, b) => a > b ? a : b),
      ),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final catchesAsync = ref.watch(catchProvider);
    final catches = catchesAsync.value ?? const <CatchEntry>[];
    final heatmap = _showHeatmap
        ? computeSpotHeatmap(
            catches: catches,
            spots: widget.spots,
            filter: _filter,
          )
        : SpotHeatmap.empty;

    return Scaffold(
      appBar: const ApexAppBar(),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.spots.isNotEmpty
                  ? LatLng(widget.spots.first.lat, widget.spots.first.lng)
                  : const LatLng(48.137154, 11.576124),
              initialZoom: 10,
              minZoom: 5,
              onTap: (_, __) => setState(() {
                _selected = null;
                _selectedCell = null;
              }),
              onMapEvent: (event) {
                if (mounted) setState(() => _zoom = event.camera.zoom);
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
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('© CARTO'),
                ],
                alignment: AttributionAlignment.bottomLeft,
              ),

              // Heatmap-Layer (unter den Spot-Pins).
              if (_showHeatmap && heatmap.cells.isNotEmpty)
                CircleLayer(
                  circles: heatmap.cells.map((cell) {
                    final color = _scoreColor(cell.score);
                    final radiusPx =
                        _cellRadius(_zoom) *
                        (0.55 + 0.45 * cell.score.clamp(0.0, 1.0));
                    final isSelected =
                        _selectedCell != null &&
                        _selectedCell!.center == cell.center;
                    return CircleMarker(
                      point: cell.center,
                      radius: radiusPx,
                      useRadiusInMeter: false,
                      color: color.withAlpha(isSelected ? 180 : 110),
                      borderColor: color.withAlpha(isSelected ? 255 : 200),
                      borderStrokeWidth: isSelected ? 2.5 : 1.2,
                    );
                  }).toList(),
                ),

              // Unsichtbarer Tap-Layer für Heatmap-Zellen (Marker statt Circle,
              // damit GestureDetector zuverlässig greift).
              if (_showHeatmap && heatmap.cells.isNotEmpty)
                MarkerLayer(
                  markers: heatmap.cells.map((cell) {
                    final radiusPx =
                        _cellRadius(_zoom) *
                        (0.55 + 0.45 * cell.score.clamp(0.0, 1.0));
                    final size = (radiusPx * 2).clamp(20, 120).toDouble();
                    return Marker(
                      point: cell.center,
                      width: size,
                      height: size,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => setState(() {
                          _selectedCell = cell;
                          _selected = null;
                        }),
                        child: const SizedBox.expand(),
                      ),
                    );
                  }).toList(),
                ),

              MarkerLayer(
                markers: widget.spots.map((s) {
                  final isSelected = _selected?.id == s.id;
                  final base = _markerSize(_zoom);
                  final size = isSelected ? base * 1.35 : base;
                  return Marker(
                    point: LatLng(s.lat, s.lng),
                    width: size,
                    height: size,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selected = s;
                          _selectedCell = null;
                        });
                        _mapController.move(LatLng(s.lat, s.lng), 15);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? ApexColors.strike
                              : ApexColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.background, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isSelected
                                          ? ApexColors.strike
                                          : ApexColors.primary)
                                      .withAlpha(140),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: c.background,
                          size: size * 0.55,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // Heatmap-Stats / Filter-Indikator (top-left)
          if (_showHeatmap)
            Positioned(
              top: 12,
              left: 12,
              child: _HeatmapStatsBadge(heatmap: heatmap, filter: _filter),
            ),

          // Info-Card beim ausgewählten Spot
          if (_selected != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Material(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                elevation: 6,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    final spot = _selected;
                    Navigator.pop(context);
                    if (spot != null) {
                      context.push('/spots/detail', extra: spot);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: ApexColors.primary.withAlpha(24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: ApexColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selected!.name,
                                style: TextStyle(
                                  fontFamily: 'Rajdhani',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                              if (_selected!.waterBodyName != null)
                                Text(
                                  _selected!.waterBodyName!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textSecondary,
                                  ),
                                ),
                              if (_selected!.depthM != null)
                                Text(
                                  'Tiefe: ${_selected!.depthM} m',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: c.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Info-Card bei ausgewählter Heatmap-Zelle
          if (_selected == null && _selectedCell != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: _HeatmapCellCard(
                cell: _selectedCell!,
                onClose: () => setState(() => _selectedCell = null),
              ),
            ),

          // Rechte Button-Spalte: Fit-All, Heatmap-Toggle, Filter
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'fit_all',
                  backgroundColor: c.surface,
                  foregroundColor: ApexColors.primary,
                  onPressed: _fitAll,
                  tooltip: 'Alle anzeigen',
                  child: const Icon(Icons.fit_screen),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'heatmap_toggle',
                  backgroundColor: _showHeatmap
                      ? ApexColors.primary
                      : c.surface,
                  foregroundColor: _showHeatmap
                      ? c.background
                      : ApexColors.primary,
                  onPressed: () => setState(() => _showHeatmap = !_showHeatmap),
                  tooltip: _showHeatmap
                      ? 'Heatmap ausblenden'
                      : 'Heatmap einblenden',
                  child: const Icon(Icons.local_fire_department),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'heatmap_filter',
                  backgroundColor: _filter.isActive
                      ? ApexColors.strike
                      : c.surface,
                  foregroundColor: _filter.isActive
                      ? c.background
                      : ApexColors.primary,
                  onPressed: _showHeatmap ? _openFilterSheet : null,
                  tooltip: 'Heatmap filtern',
                  child: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<HeatmapFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HeatmapFilterSheet(initial: _filter),
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }
}

// ─── Heatmap-Hilfswidgets ─────────────────────────────────────────────────────

class _HeatmapStatsBadge extends StatelessWidget {
  const _HeatmapStatsBadge({required this.heatmap, required this.filter});
  final SpotHeatmap heatmap;
  final HeatmapFilter filter;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final hasData = heatmap.totalCatches > 0;
    return Material(
      color: c.surface.withAlpha(230),
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              size: 16,
              color: hasData ? ApexColors.strike : c.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              hasData
                  ? '${heatmap.totalCatches} Fänge · ${heatmap.cells.length} Zonen'
                  : 'Keine Daten',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            if (filter.isActive) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: ApexColors.strike.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'gefiltert',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: ApexColors.strike,
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

class _HeatmapCellCard extends StatelessWidget {
  const _HeatmapCellCard({required this.cell, required this.onClose});
  final HeatmapCell cell;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final color = _SpotsMapScreenState._scoreColor(cell.score);
    final pct = (cell.score * 100).round();

    // Top-Spezies in dieser Zelle
    final speciesCounts = <FishSpecies, int>{};
    for (final ce in cell.catches) {
      speciesCounts[ce.species] = (speciesCounts[ce.species] ?? 0) + 1;
    }
    final topSpecies = speciesCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '$pct',
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hotspot-Zone',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cell.catchCount} Fang${cell.catchCount == 1 ? '' : 'e'}'
                    '${cell.avgLengthCm > 0 ? ' · Ø ${AppNum.cm(cell.avgLengthCm)}' : ''}'
                    '${cell.totalWeightG > 0 ? ' · ${AppNum.fixed(cell.totalWeightG / 1000, 1)} kg ges.' : ''}',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                  if (topSpecies.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: topSpecies.take(3).map((e) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ApexColors.primary.withAlpha(28),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${e.key.displayName} ×${e.value}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: ApexColors.primary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: c.textMuted,
              onPressed: onClose,
              tooltip: 'Schließen',
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatmapFilterSheet extends StatefulWidget {
  const _HeatmapFilterSheet({required this.initial});
  final HeatmapFilter initial;

  @override
  State<_HeatmapFilterSheet> createState() => _HeatmapFilterSheetState();
}

class _HeatmapFilterSheetState extends State<_HeatmapFilterSheet> {
  late final Set<FishSpecies> _species = {...widget.initial.species};
  late final Set<Season> _seasons = {...widget.initial.seasons};
  late final Set<DaytimeBucket> _daytimes = {...widget.initial.daytimes};
  late int? _lastDays = widget.initial.lastDays;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.textMuted.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  'Heatmap-Filter',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _species.clear();
                    _seasons.clear();
                    _daytimes.clear();
                    _lastDays = null;
                  }),
                  child: const Text('Zurücksetzen'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionTitle('Fischart'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FishSpecies.values.map((s) {
                final selected = _species.contains(s);
                return FilterChip(
                  label: Text(s.displayName),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _species.add(s);
                    } else {
                      _species.remove(s);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _SectionTitle('Saison'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Season.values.map((s) {
                final selected = _seasons.contains(s);
                return FilterChip(
                  label: Text(s.displayName),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _seasons.add(s);
                    } else {
                      _seasons.remove(s);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _SectionTitle('Tageszeit'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DaytimeBucket.values.map((d) {
                final selected = _daytimes.contains(d);
                return FilterChip(
                  label: Text(d.displayName),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _daytimes.add(d);
                    } else {
                      _daytimes.remove(d);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _SectionTitle('Zeitraum'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                    ('Alle', null),
                    ('30 Tage', 30),
                    ('90 Tage', 90),
                    ('1 Jahr', 365),
                  ].map((opt) {
                    final selected = _lastDays == opt.$2;
                    return ChoiceChip(
                      label: Text(opt.$1),
                      selected: selected,
                      onSelected: (_) => setState(() => _lastDays = opt.$2),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  HeatmapFilter(
                    species: _species,
                    seasons: _seasons,
                    daytimes: _daytimes,
                    lastDays: _lastDays,
                  ),
                ),
                child: const Text('Anwenden'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: c.textSecondary,
        ),
      ),
    );
  }
}
