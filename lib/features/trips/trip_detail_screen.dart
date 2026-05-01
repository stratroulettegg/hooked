import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/trip.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/external_map_launcher.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/firebase_bootstrap.dart';
import '../../shared/services/firebase/trip_cloud_share_service.dart';
import '../../shared/services/tile_cache_service.dart';
import '../../shared/services/trip_share_service.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/daily_forecast_card.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({super.key, required this.trip});
  final Trip trip;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  late Set<int> _checkedItems;

  @override
  void initState() {
    super.initState();
    _checkedItems = <int>{};
    // Best-effort Cloud-Sync beim Öffnen — Fehler werden stumm ignoriert.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.trip.cloudTripId != null) {
        ref.read(tripProvider.notifier).refreshCloudTrip(widget.trip);
        // Eigenen Teilnehmer-Eintrag aktualisieren (z. B. wenn der User
        // gerade seinen Nicknamen oder das Bild geändert hat).
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final isOwner =
              widget.trip.cloudTripId == widget.trip.id; // siehe app_providers
          TripCloudShareService()
              .ensureParticipant(
                cloudTripId: widget.trip.cloudTripId!,
                user: user,
                role: isOwner ? 'owner' : 'member',
              )
              .catchError((_) {});
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Live-Daten aus Provider holen (falls editiert wurde)
    final tripsAsync = ref.watch(tripProvider);
    final trip = tripsAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (t) => t.id == widget.trip.id,
        orElse: () => widget.trip,
      ),
      orElse: () => widget.trip,
    );

    final c = ApexColors.of(context);
    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Einladung erstellen',
            onPressed: () => _shareTrip(context, trip),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Bearbeiten',
            onPressed: () => context.push('/trips/edit', extra: trip),
          ),
          IconButton(
            icon: Icon(
              trip.cloudTripId != null && trip.cloudTripId != trip.id
                  ? Icons.exit_to_app
                  : Icons.delete_outline,
            ),
            tooltip: trip.cloudTripId != null && trip.cloudTripId != trip.id
                ? 'Verlassen'
                : 'Löschen',
            onPressed: () async {
              final isShared = trip.cloudTripId != null;
              final isOwner = isShared && trip.cloudTripId == trip.id;
              final isMember = isShared && !isOwner;
              final title = isMember ? 'Trip verlassen?' : 'Trip löschen?';
              final body = isOwner
                  ? '„${trip.name}" wird für dich und alle Eingeladenen '
                        'dauerhaft entfernt.'
                  : isMember
                  ? 'Du wirst aus „${trip.name}" entfernt. Der Trip '
                        'bleibt für den Ersteller bestehen.'
                  : '„${trip.name}" wird dauerhaft entfernt.';
              final actionLabel = isMember ? 'Verlassen' : 'Löschen';
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(title),
                  content: Text(body),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: ApexColors.strike,
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await ref.read(tripProvider.notifier).removeTrip(trip.id);
                if (context.mounted) context.pop();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: ApexColors.primary,
        onRefresh: () async {
          // Cloud-Trip ggf. aktualisieren, dann Wetter/Forecast neu laden.
          if (trip.cloudTripId != null) {
            await ref.read(tripProvider.notifier).refreshCloudTrip(trip);
          }
          ref.invalidate(tripForecastProvider);
          ref.invalidate(tripProvider);
          await ref.read(tripProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _HeaderCard(trip: trip),
            const SizedBox(height: 16),
            _MapSection(trip: trip),
            const SizedBox(height: 16),
            if (trip.stops.isNotEmpty) ...[
              _SectionHeading('SPOTS (${trip.stops.length})'),
              const SizedBox(height: 8),
              for (int i = 0; i < trip.stops.length; i++)
                _StopTile(stop: trip.stops[i], index: i),
              const SizedBox(height: 16),
            ],
            if (trip.cloudTripId != null) ...[
              _ParticipantsSection(cloudTripId: trip.cloudTripId!),
              const SizedBox(height: 16),
            ],
            DailyForecastCard(
              latitude: trip.centerLat,
              longitude: trip.centerLng,
              date: trip.date,
            ),
            const SizedBox(height: 16),
            if (trip.checklist.isNotEmpty) ...[
              const _SectionHeading('PACKLISTE'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < trip.checklist.length; i++)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: ApexColors.primary,
                        value: _checkedItems.contains(i),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _checkedItems.add(i);
                            } else {
                              _checkedItems.remove(i);
                            }
                          });
                        },
                        title: Text(
                          trip.checklist[i],
                          style: TextStyle(
                            decoration: _checkedItems.contains(i)
                                ? TextDecoration.lineThrough
                                : null,
                            color: _checkedItems.contains(i)
                                ? c.textMuted
                                : c.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (trip.notes != null && trip.notes!.isNotEmpty) ...[
              const _SectionHeading('NOTIZEN'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  trip.notes!,
                  style: TextStyle(color: c.textPrimary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Share-Flow ─────────────────────────────────────────────────────────
  Future<void> _shareTrip(BuildContext context, Trip trip) async {
    final user = ref.read(currentUserProvider);

    // Ohne Firebase/Login: Fallback = alter Text-Share.
    if (!FirebaseBootstrap.isAvailable || user == null) {
      final reason = !FirebaseBootstrap.isAvailable
          ? 'Firebase ist nicht konfiguriert.'
          : 'Du musst angemeldet sein, um eine Einladung zu erstellen.';
      if (!context.mounted) return;
      final useFallback = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keine Cloud-Einladung möglich'),
          content: Text('$reason\n\nTrip stattdessen als Text teilen?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Als Text teilen'),
            ),
          ],
        ),
      );
      if (useFallback == true && context.mounted) {
        await const TripShareService().shareTrip(context, trip);
      }
      return;
    }

    // Cloud-Flow: Einladung erzeugen, Fortschritt anzeigen.
    final rootNav = Navigator.of(context, rootNavigator: true);
    var spinnerOpen = true;
    void closeSpinner() {
      if (spinnerOpen) {
        spinnerOpen = false;
        rootNav.pop();
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: ApexColors.primary),
      ),
    );
    try {
      final service = TripCloudShareService();
      final invite = await service.createInvite(trip: trip, ownerUid: user.uid);
      // Owner als Teilnehmer eintragen, damit er in der Liste auftaucht.
      try {
        await service.ensureParticipant(
          cloudTripId: invite.tripId,
          user: user,
          role: 'owner',
        );
      } catch (_) {
        /* nicht kritisch */
      }
      // Lokalen Trip als Cloud-verknüpft markieren, damit künftige Edits
      // automatisch gepusht werden und Pull-to-Refresh greift.
      if (trip.cloudTripId != trip.id) {
        await ref
            .read(tripProvider.notifier)
            .editTrip(trip.copyWith(cloudTripId: trip.id));
      }
      if (context.mounted) closeSpinner();
      if (!context.mounted) return;

      final text =
          'Ich habe dich zu meinem Angel-Trip "${trip.name}" eingeladen.\n'
          'Code: ${invite.token}\n\n'
          'In Hooked öffnen → "Einladung einlösen" → Code eingeben.';
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        text,
        subject: 'Hooked-Einladung: ${trip.name}',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } on TripInviteException catch (e) {
      if (context.mounted) closeSpinner();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (context.mounted) closeSpinner();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Einladung fehlgeschlagen: $e')));
      }
    }
  }
}

class _ParticipantsSection extends StatelessWidget {
  const _ParticipantsSection({required this.cloudTripId});
  final String cloudTripId;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return StreamBuilder<List<TripParticipant>>(
      stream: TripCloudShareService().participantsStream(cloudTripId),
      builder: (context, snap) {
        final list = snap.data ?? const <TripParticipant>[];
        if (snap.connectionState == ConnectionState.waiting && list.isEmpty) {
          return const SizedBox.shrink();
        }
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading('TEILNEHMER (${list.length})'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _ParticipantTile(participant: list[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant});
  final TripParticipant participant;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final name = (participant.displayName?.trim().isNotEmpty ?? false)
        ? participant.displayName!.trim()
        : 'Anonym';
    final photo = participant.photoURL;
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: ApexColors.primary.withAlpha(40),
                backgroundImage: (photo != null && photo.isNotEmpty)
                    ? NetworkImage(photo)
                    : null,
                child: (photo == null || photo.isEmpty)
                    ? Icon(Icons.person, color: ApexColors.primary)
                    : null,
              ),
              if (participant.isOwner)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star,
                      size: 14,
                      color: ApexColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: c.textSecondary,
              fontWeight: participant.isOwner ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Rajdhani',
      fontSize: 12,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w700,
      color: ApexColors.of(context).textMuted,
    ),
  );
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final days = trip.daysUntil;
    final String countdown;
    final Color color;
    if (!trip.isUpcoming) {
      countdown = 'VORBEI';
      color = c.textMuted;
    } else if (days == 0) {
      countdown = 'HEUTE';
      color = ApexColors.strike;
    } else if (days == 1) {
      countdown = 'MORGEN';
      color = ApexColors.scoreMid;
    } else {
      countdown = 'IN $days TAGEN';
      color = ApexColors.primary;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(60)),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: c.cardShadow,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                countdown,
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 12,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                AppDateFormats.weekdayDate.format(trip.date),
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            trip.name,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          if (trip.waterBodyName != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.water, size: 16, color: c.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trip.waterBodyName!,
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MapSection extends StatefulWidget {
  const _MapSection({required this.trip});
  final Trip trip;

  @override
  State<_MapSection> createState() => _MapSectionState();
}

class _MapSectionState extends State<_MapSection> {
  final _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final stops = widget.trip.stops;
    final points = stops.map((s) => LatLng(s.lat, s.lng)).toList();
    final center = LatLng(widget.trip.centerLat, widget.trip.centerLng);

    LatLngBounds? bounds;
    if (points.length >= 2) {
      bounds = LatLngBounds.fromPoints([...points, center]);
    }

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      // Border über der Karte zeichnen, sonst übermalen die Tile-
      // Antialiasing-Kanten die Linie und der Rahmen wirkt unvollständig.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 12,
          initialCameraFit: bounds != null
              ? CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(40),
                )
              : null,
          minZoom: 4,
          maxZoom: 18,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
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
          if (points.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 3,
                  color: ApexColors.primary.withAlpha(200),
                  pattern: StrokePattern.dashed(segments: const [10, 6]),
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              for (int i = 0; i < stops.length; i++)
                Marker(
                  point: LatLng(stops[i].lat, stops[i].lng),
                  width: 34,
                  height: 34,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ApexColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.background, width: 2),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (stops.isEmpty)
                Marker(
                  point: center,
                  width: 32,
                  height: 32,
                  child: Container(
                    decoration: BoxDecoration(
                      color: ApexColors.strike,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.background, width: 2),
                    ),
                    child: const Icon(
                      Icons.place,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap contributors'),
              TextSourceAttribution('© CARTO'),
            ],
            alignment: AttributionAlignment.bottomLeft,
          ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.stop, required this.index});
  final TripStop stop;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ApexColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  '${stop.lat.toStringAsFixed(4)}, ${stop.lng.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Navigieren',
            onPressed: () => ExternalMapLauncher.choose(
              context,
              lat: stop.lat,
              lng: stop.lng,
              label: stop.name,
            ),
            icon: Icon(Icons.directions, color: ApexColors.primary),
          ),
        ],
      ),
    );
  }
}
