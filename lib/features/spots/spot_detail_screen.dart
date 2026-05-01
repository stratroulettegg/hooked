import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/external_map_launcher.dart';
import '../../shared/services/tile_cache_service.dart';
import '../../shared/widgets/apex_app_bar.dart';

class SpotDetailScreen extends ConsumerWidget {
  const SpotDetailScreen({super.key, required this.spot});
  final FishingSpot spot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live-Daten aus Provider holen (falls nachträglich editiert)
    final spotsAsync = ref.watch(spotProvider);
    final spot = spotsAsync.maybeWhen(
      data: (list) =>
          list.firstWhere((s) => s.id == this.spot.id, orElse: () => this.spot),
      orElse: () => this.spot,
    );

    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          _OfflineDownloadButton(spot: spot),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/spots/edit', extra: spot),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: ApexColors.scoreLow),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Karte (Kachel)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 250,
                child: FlutterMap(
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
                      urlTemplate: context.isDark
                          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                          : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'de.apex.hooked',
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
                ),
              ),
            ),
          ),

          // Foto (wenn vorhanden)
          if (AppPaths.photoFile(spot.photoPath) != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.file(
                    AppPaths.photoFile(spot.photoPath)!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Spot-Info (Maße)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ApexColors.of(context).surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ApexColors.of(context).border),
                  ),
                  child: Column(
                    children: [
                      if (spot.waterBodyName != null)
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
                        icon: Icons.location_on_outlined,
                        label: 'Koordinaten',
                        value:
                            '${spot.lat.toStringAsFixed(5)}, ${spot.lng.toStringAsFixed(5)}',
                      ),
                      if (spot.structures.isNotEmpty)
                        _InfoRow(
                          icon: Icons.terrain,
                          label: 'Struktur',
                          value: spot.structures
                              .map((s) => s.displayName)
                              .join(', '),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // In Karten öffnen
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openInMaps(context),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text(
                      'IN KARTEN ÖFFNEN',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ApexColors.primary,
                      side: BorderSide(
                        color: ApexColors.primary.withAlpha(140),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Saisonnotizen
                if (spot.seasonNotes.isNotEmpty) ...[
                  Text(
                    'SAISONNOTIZEN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: ApexColors.of(context).textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...Season.values.map((season) {
                    final note = spot.seasonNotes
                        .where((sn) => sn.season == season)
                        .firstOrNull;
                    if (note == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SeasonNoteCard(season: season, note: note),
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                // Notizen
                if (spot.notes != null && spot.notes!.isNotEmpty) ...[
                  Container(
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
                          'NOTIZEN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: ApexColors.of(context).textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          spot.notes!,
                          style: TextStyle(
                            color: ApexColors.of(context).textPrimary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInMaps(BuildContext context) async {
    await ExternalMapLauncher.choose(
      context,
      lat: spot.lat,
      lng: spot.lng,
      label: spot.name,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
      await ref.read(spotProvider.notifier).removeSpot(spot.id);
      if (context.mounted) context.pop();
    }
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
        if (mounted)
          setState(() {
            _progress = done;
            _total = total;
          });
      },
    );

    if (mounted)
      setState(() {
        _downloading = false;
        _done = true;
      });
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
