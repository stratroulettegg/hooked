import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/trip.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/pro/pro_providers.dart';
import 'pro_gate.dart';

/// Free-User dürfen maximal so viele aktive (= zukünftige oder laufende)
/// Trips parallel haben. Vergangene Trips zählen nicht.
const int kFreeTripLimit = 3;

/// Liefert die Anzahl aktiver Trips (zukünftig oder heute).
int countActiveTrips(List<Trip> trips) =>
    trips.where((t) => t.isUpcoming).length;

/// Reaktiver Provider: wie viele aktive Trips hat der User aktuell?
final activeTripsCountProvider = Provider<int>((ref) {
  final trips = ref.watch(tripProvider).valueOrNull ?? const [];
  return countActiveTrips(trips);
});

/// Reaktiver Provider: hat der User das Free-Limit erreicht?
/// `false` für Pro-User.
final tripLimitReachedProvider = Provider<bool>((ref) {
  if (ref.watch(isProProvider)) return false;
  return ref.watch(activeTripsCountProvider) >= kFreeTripLimit;
});

/// Helper, der vor dem Add-Trip-Flow die Pro-Gate prüft.
/// Liefert `true`, wenn navigiert/erlaubt wurde — `false`, wenn der
/// Paywall geschlossen wurde, ohne zu kaufen.
Future<bool> ensureCanAddTrip({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final reached = ref.read(tripLimitReachedProvider);
  if (!reached) return true;
  final unlocked = await showPaywall(
    context,
    feature: ProFeature.unlimitedTrips,
  );
  return unlocked;
}
