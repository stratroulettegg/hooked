import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/trip.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/firebase/firebase_bootstrap.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/trip_cloud_share_service.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/swipe_to_delete.dart';

class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  bool _initialRefreshDone = false;

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(tripProvider);

    // Beim ersten vollständigen Laden einmalig alle Cloud-verknüpften Trips
    // aktualisieren (best effort, still im Hintergrund).
    if (!_initialRefreshDone && tripsAsync.hasValue) {
      _initialRefreshDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(tripProvider.notifier).refreshAllCloudTrips();
        }
      });
    }

    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Einladung einlösen',
            onPressed: () => _redeemInviteDialog(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: ApexColors.primary,
        onRefresh: () async {
          await ref.read(tripProvider.notifier).refreshAllCloudTrips();
        },
        child: tripsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: ApexColors.primary),
          ),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [Center(child: Text('Fehler: $e'))],
          ),
          data: (trips) {
            if (trips.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _EmptyState(onAdd: () => context.push('/trips/add')),
                ],
              );
            }
            final upcoming = trips.where((t) => t.isUpcoming).toList()
              ..sort((a, b) => a.date.compareTo(b.date));
            final past = trips.where((t) => !t.isUpcoming).toList()
              ..sort((a, b) => b.date.compareTo(a.date));

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (upcoming.isNotEmpty) ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TripSectionHeaderDelegate(
                      label: 'ANSTEHEND',
                      count: upcoming.length,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    sliver: SliverList.separated(
                      itemCount: upcoming.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final t = upcoming[i];
                        return SwipeToDelete(
                          dismissKey: ValueKey('trip-${t.id}'),
                          confirmTitle: 'Trip löschen?',
                          confirmMessage:
                              'Der Trip „${t.name}“ wird gelöscht. Geteilte Cloud-Daten werden bereinigt.',
                          onDelete: () => ref
                              .read(tripProvider.notifier)
                              .removeTrip(t.id),
                          child: _TripCard(trip: t),
                        );
                      },
                    ),
                  ),
                ],
                if (past.isNotEmpty) ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TripSectionHeaderDelegate(
                      label: 'VERGANGEN',
                      count: past.length,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    sliver: SliverList.separated(
                      itemCount: past.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final t = past[i];
                        return SwipeToDelete(
                          dismissKey: ValueKey('trip-${t.id}'),
                          confirmTitle: 'Trip löschen?',
                          confirmMessage:
                              'Der Trip „${t.name}“ wird gelöscht. Geteilte Cloud-Daten werden bereinigt.',
                          onDelete: () => ref
                              .read(tripProvider.notifier)
                              .removeTrip(t.id),
                          child: _TripCard(trip: t, faded: true),
                        );
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TripSectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TripSectionHeaderDelegate({required this.label, required this.count});
  final String label;
  final int count;

  static const double _height = 36;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = ApexColors.of(context);
    return Container(
      height: _height,
      color: c.background,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: c.border),
          ),
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
  bool shouldRebuild(covariant _TripSectionHeaderDelegate old) =>
      old.label != label || old.count != count;
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, this.faded = false});
  final Trip trip;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final df = AppDateFormats.weekdayDate;
    final stops = trip.stops.length;
    final days = trip.daysUntil;

    String counter;
    Color counterColor;
    if (faded) {
      counter = 'VORBEI';
      counterColor = c.textMuted;
    } else if (days == 0) {
      counter = 'HEUTE';
      counterColor = ApexColors.strike;
    } else if (days == 1) {
      counter = 'MORGEN';
      counterColor = ApexColors.scoreMid;
    } else {
      counter = 'IN $days T';
      counterColor = ApexColors.primary;
    }

    return Opacity(
      opacity: faded ? 0.72 : 1.0,
      child: GestureDetector(
        onTap: () => context.push('/trips/detail', extra: trip),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
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
          child: Row(
            children: [
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: counterColor.withAlpha(24),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: counterColor.withAlpha(60)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppDateFormats.dayOfMonth.format(trip.date),
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: counterColor,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppDateFormats.monthShort.format(trip.date).toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                        color: counterColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    if (trip.waterBodyName != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.water, size: 14, color: c.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              trip.waterBodyName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      df.format(trip.date),
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    counter,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 12,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                      color: counterColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.push_pin_outlined,
                        size: 12,
                        color: c.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$stops',
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
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
            Icon(Icons.event_note, size: 64, color: c.textMuted),
            const SizedBox(height: 16),
            Text(
              'Noch kein Trip geplant',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Plane deinen nächsten Angel-Ausflug: Gewässer wählen, Spots markieren, Wetter checken.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Trip planen'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Invite-Flow ─────────────────────────────────────────────────────────
Future<void> _redeemInviteDialog(BuildContext context, WidgetRef ref) async {
  if (!FirebaseBootstrap.isAvailable) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Einladungen benötigen eine Firebase-Konfiguration.'),
      ),
    );
    return;
  }
  final clip = await Clipboard.getData('text/plain');
  final prefill = TripCloudShareService.extractToken(clip?.text ?? '') ?? '';

  if (!context.mounted) return;
  final controller = TextEditingController(text: prefill);
  final token = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Einladung einlösen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gib den 8-stelligen Code aus der Einladung ein.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(letterSpacing: 3, fontSize: 18),
            decoration: const InputDecoration(
              hintText: 'z. B. AB23CD45',
              border: OutlineInputBorder(),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(32),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final t = TripCloudShareService.extractToken(controller.text);
            FocusScope.of(ctx).unfocus();
            Navigator.pop(ctx, t);
          },
          child: const Text('Einlösen'),
        ),
      ],
    ),
  );

  if (token == null || !context.mounted) return;

  // Spinner über den Root-Navigator zeigen, damit das Schließen nicht
  // mit go_router-Routen kollidiert.
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: ApexColors.primary),
    ),
  );
  void closeSpinner() {
    if (rootNavigator.canPop()) rootNavigator.pop();
  }

  try {
    final service = TripCloudShareService();
    final trip = await service.redeemInvite(token);
    final added = await ref.read(tripProvider.notifier).addTrip(trip);
    // Eigenen Eintrag in der Teilnehmer-Liste hinterlegen.
    final user = ref.read(currentUserProvider);
    if (user != null && added.cloudTripId != null) {
      try {
        await service.ensureParticipant(
          cloudTripId: added.cloudTripId!,
          user: user,
        );
      } catch (_) {
        /* nicht kritisch */
      }
    }
    closeSpinner();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Trip „${added.name}" importiert.')));
  } on TripInviteException catch (e) {
    closeSpinner();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (e) {
    closeSpinner();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Einlösen fehlgeschlagen: $e')));
    }
  }
}
