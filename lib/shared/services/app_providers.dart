import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../models/catch_entry.dart';
import '../models/fishing_spot.dart';
import '../models/waterbody.dart';
import '../models/mission.dart';
import '../models/trip.dart';
import '../../core/engines/predator_score_engine.dart';
import 'local_database_service.dart';
import 'weather_service.dart';
import 'firebase/firebase_bootstrap.dart';
import 'firebase/trip_cloud_share_service.dart';
import 'firebase/feed_service.dart';
import 'firebase/moderation_service.dart';
import '../widgets/pb_celebration.dart';

// ─── Theme Mode Provider ─────────────────────────────────────────────────────
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

// ─── Selected Species Provider ───────────────────────────────────────────────
/// Aktuell gewähltes Artprofil für den Predator Index
final selectedSpeciesProvider = StateProvider<SpeciesProfile>(
  (ref) => SpeciesProfiles.hecht,
);
// ─── Water Conditions (Manuelle Eingabe) ───────────────────────────────────────
/// null = automatisch aus Lufttemp-Proxy bzw. Wind/Niederschlag
final waterTempProvider = StateProvider<double?>((ref) => null);
final waterClarityProvider = StateProvider<WaterClarity?>((ref) => null);
final waterBodyTypeProvider = StateProvider<WaterBodyType?>((ref) => null);

// ─── Location Provider ───────────────────────────────────────────────────────
/// Manuell gewählte Forecast-Location (z. B. ein Gewässer per Suche).
/// Wenn gesetzt, hat sie Vorrang vor dem GPS-Standort.
class ForecastLocation {
  final double latitude;
  final double longitude;
  final String label;
  const ForecastLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
  });
}

final forecastLocationOverrideProvider = StateProvider<ForecastLocation?>(
  (ref) => null,
);

/// Gibt den aktuellen GPS-Standort zurück oder null bei fehlender Permission
final locationProvider = FutureProvider<Position?>((ref) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
  }
  if (permission == LocationPermission.deniedForever) return null;

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
  );
});

// ─── Current Weather Provider (standortbasiert) ──────────────────────────────
final currentWeatherProvider = FutureProvider<WeatherData?>((ref) async {
  final override = ref.watch(forecastLocationOverrideProvider);
  if (override != null) {
    return WeatherService().fetchCurrent(override.latitude, override.longitude);
  }
  final position = await ref.watch(locationProvider.future);
  final lat = position?.latitude ?? 48.137154;
  final lng = position?.longitude ?? 11.576124;
  return WeatherService().fetchCurrent(lat, lng);
});

// ─── Forecast DateTime Picker (Datum + Uhrzeit für Predator Index) ───────────
/// Gewählter Zeitpunkt für den Forecast-Screen. Default = jetzt.
/// Wird zurückgesetzt, wenn der User die Seite verlässt oder die Location
/// ändert, damit der Nutzer immer den aktuellen Stand sieht beim Öffnen.
final selectedForecastDateTimeProvider = StateProvider<DateTime>(
  (ref) => DateTime.now(),
);

// ─── Predator Score Provider (geteilt zwischen Home + Forecast) ───────────────
/// Einzige Score-Berechnung für die gesamte App — verhindert Abweichungen.
final predatorScoreProvider = FutureProvider<PredatorScore>((ref) async {
  final weather = await ref.watch(currentWeatherProvider.future);
  final species = ref.watch(selectedSpeciesProvider);
  final waterTemp = ref.watch(waterTempProvider);
  final waterClarity = ref.watch(waterClarityProvider);
  final waterBodyType = ref.watch(waterBodyTypeProvider);
  return PredatorScoreEngine.calculate(
    weather: weather ?? const WeatherData(),
    now: DateTime.now(),
    species: species,
    waterTempC: waterTemp,
    waterClarity: waterClarity,
    waterBodyType: waterBodyType,
  );
});

final _db = LocalDatabaseService();
const _uuid = Uuid();
final _feedService = FeedService();
final _moderationService = ModerationService();

/// FeedService f\u00fcr UI-Aktionen (Like/Kommentar).
final feedServiceProvider = Provider<FeedService>((_) => _feedService);

/// ModerationService f\u00fcr Reports und Block-Listen.
final moderationServiceProvider = Provider<ModerationService>(
  (_) => _moderationService,
);

/// Stream der UIDs, die der eingeloggte Nutzer blockiert hat.
/// Wird als Filter f\u00fcr Feed und Kommentare verwendet.
final blockedUidsProvider = StreamProvider<Set<String>>((ref) {
  return _moderationService.watchBlockedUids();
});

/// Stream der Server-seitigen Rate-Limit-Treffer (Cloud Functions).
/// Die UI lauscht hier, um eine Snackbar zu zeigen, wenn der eigene
/// User durch Posts/Kommentare/Reports den 1h-Schwellwert \u00fcberschreitet.
final rateLimitHitsProvider = StreamProvider<RateLimitHit?>((ref) {
  return _moderationService.watchRateLimitHits();
});

/// Stream der aktuellsten Community-Feed-Posts (gemeinsame Quelle f\u00fcr alle UIs).
/// Posts von blockierten Nutzern und auto-versteckte Posts (`hidden=true`)
/// werden client-seitig herausgefiltert.
final feedPostsProvider = StreamProvider<List<FeedPost>>((ref) {
  final blocked =
      ref.watch(blockedUidsProvider).valueOrNull ?? const <String>{};
  return _feedService.watchFeed().map(
    (posts) =>
        posts.where((p) => !p.hidden && !blocked.contains(p.userId)).toList(),
  );
});

/// Stream der eigenen Feed-Posts (alle, ohne Limit), als Map keyed by postId.
final myFeedPostsProvider = StreamProvider<Map<String, FeedPost>>((ref) {
  return _feedService.watchMyFeed().map(
    (posts) => {for (final p in posts) p.id: p},
  );
});

/// Stream der Kommentare zu einem Post. Kommentare blockierter Nutzer
/// werden ebenfalls client-seitig ausgeblendet.
final feedCommentsProvider = StreamProvider.family<List<FeedComment>, String>((
  ref,
  postId,
) {
  final blocked =
      ref.watch(blockedUidsProvider).valueOrNull ?? const <String>{};
  return _feedService
      .watchComments(postId)
      .map((list) => list.where((c) => !blocked.contains(c.userId)).toList());
});

// ─── Catch Provider ──────────────────────────────────────────────────────────

class CatchNotifier extends AsyncNotifier<List<CatchEntry>> {
  @override
  Future<List<CatchEntry>> build() => _db.getCatches();

  Future<CatchEntry> addCatch(CatchEntry entry) async {
    final newEntry = entry.copyWith(id: _uuid.v4());
    await _db.insertCatch(newEntry);
    final previous = state.valueOrNull ?? const <CatchEntry>[];
    final newList = <CatchEntry>[newEntry, ...previous];
    state = AsyncData(newList);
    await _missionService.onCatchAdded(newEntry, newList, ref);
    // PB-Party: gegen alle vorherigen Fänge derselben Art vergleichen.
    ref
        .read(pbCelebrationControllerProvider)
        .maybeTrigger(newEntry: newEntry, previousCatches: previous);
    if (newEntry.isShared) {
      unawaited(_publishToFeed(newEntry));
    }
    return newEntry;
  }

  Future<void> editCatch(CatchEntry entry) async {
    final previous = (state.valueOrNull ?? const <CatchEntry>[]).firstWhere(
      (c) => c.id == entry.id,
      orElse: () => entry,
    );
    await _db.updateCatch(entry);
    state = AsyncData([
      for (final c in state.valueOrNull ?? [])
        if (c.id == entry.id) entry else c,
    ]);
    if (entry.isShared) {
      unawaited(_publishToFeed(entry));
    } else if (previous.isShared) {
      unawaited(_feedService.unpublish(entry.id));
    }
  }

  Future<void> removeCatch(String id) async {
    final entry = (state.valueOrNull ?? const <CatchEntry>[])
        .where((c) => c.id == id)
        .firstOrNull;
    await _db.deleteCatch(id);
    state = AsyncData(
      (state.valueOrNull ?? []).where((c) => c.id != id).toList(),
    );
    if (entry?.isShared ?? false) {
      unawaited(_feedService.unpublish(id));
    }
  }

  /// Markiert einen lokalen Fang als „nicht (mehr) im Feed geteilt", ohne
  /// ihn zu löschen. Wird genutzt, wenn der zugehörige Online-Post separat
  /// entfernt wurde (z. B. via Feed-Detail-Screen) — der Fang selbst soll
  /// im lokalen Tagebuch erhalten bleiben.
  ///
  /// No-op, wenn lokal kein Fang mit der ID existiert (typischer Fall nach
  /// App-Re-Install: der Online-Post lebt weiter, lokal ist nichts da).
  Future<void> markUnshared(String id) async {
    final list = state.valueOrNull ?? const <CatchEntry>[];
    final idx = list.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final entry = list[idx];
    if (!entry.isShared) return;
    final updated = entry.copyWith(isShared: false);
    await _db.updateCatch(updated);
    state = AsyncData([
      for (final c in list)
        if (c.id == id) updated else c,
    ]);
  }

  Future<void> _publishToFeed(CatchEntry entry) async {
    FishingSpot? spot;
    if (entry.shareWater && entry.spotId != null) {
      final spots = ref.read(spotProvider).valueOrNull ?? const [];
      spot = spots.where((s) => s.id == entry.spotId).firstOrNull;
    }
    try {
      await _feedService.publish(entry: entry, spot: spot);
    } catch (e, st) {
      // Best-effort: Feed darf das lokale Speichern nicht blockieren.
      debugPrint('Feed-Publish fehlgeschlagen f\u00fcr ${entry.id}: $e\n$st');
    }
  }
}

final catchProvider = AsyncNotifierProvider<CatchNotifier, List<CatchEntry>>(
  CatchNotifier.new,
);

// ─── Spot Provider ────────────────────────────────────────────────────────────

class SpotNotifier extends AsyncNotifier<List<FishingSpot>> {
  @override
  Future<List<FishingSpot>> build() => _db.getSpots();

  Future<FishingSpot> addSpot(FishingSpot spot) async {
    final newSpot = spot.copyWith(id: _uuid.v4());
    await _db.insertSpot(newSpot);
    final newList = <FishingSpot>[newSpot, ...?state.valueOrNull];
    state = AsyncData(newList);
    await _missionService.onSpotAdded(newList, ref);
    return newSpot;
  }

  Future<void> editSpot(FishingSpot spot) async {
    await _db.updateSpot(spot);
    state = AsyncData([
      for (final s in state.valueOrNull ?? [])
        if (s.id == spot.id) spot else s,
    ]);
  }

  Future<void> removeSpot(String id) async {
    await _db.deleteSpot(id);
    state = AsyncData(
      (state.valueOrNull ?? []).where((s) => s.id != id).toList(),
    );
  }
}

final spotProvider = AsyncNotifierProvider<SpotNotifier, List<FishingSpot>>(
  SpotNotifier.new,
);

// ─── Waterbody Provider ───────────────────────────────────────────────────────

class WaterbodyNotifier extends AsyncNotifier<List<Waterbody>> {
  @override
  Future<List<Waterbody>> build() => _db.getWaterbodies();

  Future<Waterbody> addWaterbody(Waterbody wb) async {
    final newWb = wb.id.isEmpty ? wb.copyWith(id: _uuid.v4()) : wb;
    await _db.insertWaterbody(newWb);
    final list = [newWb, ...?state.valueOrNull];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = AsyncData(list);
    return newWb;
  }

  Future<void> editWaterbody(Waterbody wb) async {
    await _db.updateWaterbody(wb);
    final list = [
      for (final w in state.valueOrNull ?? <Waterbody>[])
        if (w.id == wb.id) wb else w,
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = AsyncData(list);
  }

  Future<void> removeWaterbody(String id) async {
    await _db.deleteWaterbody(id);
    state = AsyncData(
      (state.valueOrNull ?? <Waterbody>[]).where((w) => w.id != id).toList(),
    );
    // Spots werden in der DB auf null gesetzt — Spot-Cache neu laden
    ref.invalidate(spotProvider);
  }
}

final waterbodyProvider =
    AsyncNotifierProvider<WaterbodyNotifier, List<Waterbody>>(
      WaterbodyNotifier.new,
    );

// ─── Trip Provider ────────────────────────────────────────────────────────────

class TripNotifier extends AsyncNotifier<List<Trip>> {
  @override
  Future<List<Trip>> build() => _db.getTrips();

  Future<Trip> addTrip(Trip trip) async {
    final id = trip.id.isEmpty ? _uuid.v4() : trip.id;
    // Stops bekommen trip_id + ggf. neue IDs + orderIndex
    final stops = <TripStop>[];
    for (int i = 0; i < trip.stops.length; i++) {
      final s = trip.stops[i];
      stops.add(
        s.copyWith(
          id: s.id.isEmpty ? _uuid.v4() : s.id,
          tripId: id,
          orderIndex: i,
        ),
      );
    }
    final newTrip = trip.copyWith(id: id, stops: stops);
    await _db.insertTrip(newTrip);
    state = AsyncData(
      [newTrip, ...state.valueOrNull ?? []]
        ..sort((a, b) => a.date.compareTo(b.date)),
    );
    return newTrip;
  }

  Future<void> editTrip(Trip trip) async {
    final stops = <TripStop>[];
    for (int i = 0; i < trip.stops.length; i++) {
      final s = trip.stops[i];
      stops.add(
        s.copyWith(
          id: s.id.isEmpty ? _uuid.v4() : s.id,
          tripId: trip.id,
          orderIndex: i,
        ),
      );
    }
    final updated = trip.copyWith(stops: stops);
    await _db.updateTrip(updated);
    final list = <Trip>[
      for (final t in state.valueOrNull ?? <Trip>[])
        if (t.id == trip.id) updated else t,
    ]..sort((a, b) => a.date.compareTo(b.date));
    state = AsyncData(list);

    // Nur der Eigentümer pushed Changes in die Cloud. Der Eigentümer
    // erkennt man daran, dass seine lokale Trip-ID zugleich die Cloud-ID ist
    // (Invitees erhalten beim Redeem eine neue lokale UUID).
    final isOwner =
        updated.cloudTripId != null && updated.cloudTripId == updated.id;
    if (isOwner && FirebaseBootstrap.isAvailable) {
      try {
        await TripCloudShareService().pushUpdate(updated);
      } catch (_) {
        // stumm schlucken — UI kann beim nächsten Öffnen refreshen
      }
    }
  }

  /// Holt den aktuellen Cloud-Stand für einen einzelnen Trip und
  /// speichert ihn lokal. Fehler werden stumm ignoriert (Offline-OK).
  /// Gibt den aktualisierten Trip zurück, oder den unveränderten, wenn
  /// kein Cloud-Link besteht oder der Abruf fehlschlägt.
  Future<Trip> refreshCloudTrip(Trip trip) async {
    if (trip.cloudTripId == null || !FirebaseBootstrap.isAvailable) {
      return trip;
    }
    try {
      final fetched = await TripCloudShareService().fetchCloudTrip(trip);
      if (fetched == null) return trip; // Cloud-Trip gelöscht — lokal belassen
      // Eingeladene haben eine **eigene, lokale** Packliste. Damit deren
      // persönliche Ergänzungen beim Pull-Refresh nicht verlorengehen, wird
      // für Nicht-Owner die lokale Checklist beibehalten.
      final isOwner = trip.cloudTripId == trip.id;
      final fresh = isOwner
          ? fetched
          : fetched.copyWith(checklist: trip.checklist);
      // Nur speichern, wenn sich etwas geändert hat (billiger Vergleich).
      if (_tripsEquivalent(trip, fresh)) return trip;
      await _db.updateTrip(fresh);
      final list = <Trip>[
        for (final t in state.valueOrNull ?? <Trip>[])
          if (t.id == fresh.id) fresh else t,
      ]..sort((a, b) => a.date.compareTo(b.date));
      state = AsyncData(list);
      return fresh;
    } catch (_) {
      return trip;
    }
  }

  /// Aktualisiert alle lokal vorhandenen Cloud-verknüpften Trips parallel.
  Future<void> refreshAllCloudTrips() async {
    final current = state.valueOrNull ?? const <Trip>[];
    final linked = current.where((t) => t.cloudTripId != null).toList();
    if (linked.isEmpty || !FirebaseBootstrap.isAvailable) return;
    await Future.wait(linked.map(refreshCloudTrip));
  }

  bool _tripsEquivalent(Trip a, Trip b) {
    if (a.name != b.name) return false;
    if (a.date != b.date) return false;
    if (a.waterBodyName != b.waterBodyName) return false;
    if (a.centerLat != b.centerLat) return false;
    if (a.centerLng != b.centerLng) return false;
    if (a.notes != b.notes) return false;
    if (a.checklist.length != b.checklist.length) return false;
    for (var i = 0; i < a.checklist.length; i++) {
      if (a.checklist[i] != b.checklist[i]) return false;
    }
    if (a.stops.length != b.stops.length) return false;
    for (var i = 0; i < a.stops.length; i++) {
      final sa = a.stops[i];
      final sb = b.stops[i];
      if (sa.name != sb.name ||
          sa.lat != sb.lat ||
          sa.lng != sb.lng ||
          sa.notes != sb.notes ||
          sa.orderIndex != sb.orderIndex) {
        return false;
      }
    }
    return true;
  }

  Future<void> removeTrip(String id) async {
    // Cloud-Aufräumen vor lokalem Delete: Owner löscht den Cloud-Trip
    // (samt Teilnehmern + offenen Invites), Member entfernt nur seinen
    // eigenen Teilnehmer-Eintrag. Sonst tauchte der Trip beim nächsten
    // App-Start via `restoreCloudTrips` wieder auf.
    final current = state.valueOrNull ?? const <Trip>[];
    Trip? trip;
    for (final t in current) {
      if (t.id == id) {
        trip = t;
        break;
      }
    }
    if (trip != null &&
        trip.cloudTripId != null &&
        FirebaseBootstrap.isAvailable) {
      final isOwner = trip.cloudTripId == trip.id;
      final svc = TripCloudShareService();
      try {
        if (isOwner) {
          await svc.deleteSharedTrip(trip.cloudTripId!);
        } else {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            await svc.leaveSharedTrip(cloudTripId: trip.cloudTripId!, uid: uid);
          }
        }
      } catch (_) {
        // Best effort — wenn die Cloud gerade nicht erreichbar ist,
        // bleibt der lokale Delete trotzdem konsistent. Beim nächsten
        // Online-Sync taucht der Trip ggf. einmalig wieder auf; ein
        // erneuter Löschversuch räumt das dann nach.
      }
    }
    await _db.deleteTrip(id);
    state = AsyncData(
      (state.valueOrNull ?? []).where((t) => t.id != id).toList(),
    );
  }

  /// Holt alle Cloud-Trips für [uid] (eigene + Teilnahmen) und legt
  /// fehlende lokal an. Bestehende lokale Trips bleiben unangetastet —
  /// abgeglichen wird über `cloudTripId`. Fehler werden stumm geschluckt
  /// (Login soll nicht blockieren, wenn das Netz weg ist).
  ///
  /// Gibt die Anzahl neu importierter Trips zurück (für UI-Feedback).
  Future<int> restoreCloudTrips(String uid) async {
    if (!FirebaseBootstrap.isAvailable) return 0;
    try {
      final remote = await TripCloudShareService().fetchTripsForUser(uid);
      if (remote.isEmpty) return 0;

      final current = state.valueOrNull ?? const <Trip>[];
      final existingCloudIds = <String>{
        for (final t in current)
          if (t.cloudTripId != null) t.cloudTripId!,
      };

      final imported = <Trip>[];
      for (final r in remote) {
        if (existingCloudIds.contains(r.cloudId)) continue;
        final trip = TripCloudShareService().decodeForRestore(
          r.data,
          cloudId: r.cloudId,
          isOwner: r.isOwner,
        );
        await _db.insertTrip(trip);
        imported.add(trip);
      }
      if (imported.isNotEmpty) {
        state = AsyncData(
          [...imported, ...current]..sort((a, b) => a.date.compareTo(b.date)),
        );
      }
      return imported.length;
    } catch (_) {
      // Stumm — nicht blockieren beim Login.
      return 0;
    }
  }
}

final tripProvider = AsyncNotifierProvider<TripNotifier, List<Trip>>(
  TripNotifier.new,
);

/// Tagesvorhersage für einen geplanten Trip (lat/lng + Datum).
/// Nutzt Equatable-freie Parameter-Klasse, daher einfache Klasse statt record
/// mit `.family`.
final tripForecastProvider =
    FutureProvider.family<DailyForecast?, TripForecastKey>((ref, key) async {
      return WeatherService().fetchDailyForecast(key.lat, key.lng, key.date);
    });

class TripForecastKey {
  final double lat;
  final double lng;
  final DateTime date;
  const TripForecastKey({
    required this.lat,
    required this.lng,
    required this.date,
  });

  @override
  bool operator ==(Object other) =>
      other is TripForecastKey &&
      other.lat == lat &&
      other.lng == lng &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode => Object.hash(lat, lng, date.year, date.month, date.day);
}

// ─── Mission Provider ─────────────────────────────────────────────────────────

class MissionNotifier extends AsyncNotifier<List<Mission>> {
  @override
  Future<List<Mission>> build() async {
    await _db.seedMissions();
    final missions = await _db.getMissions();
    final processed = await _rolloverIfNeeded(missions);
    return _filterAndSort(processed);
  }

  /// Liefert nur die für die UI sichtbaren Missionen, sortiert „gut zuerst":
  /// 1. Bereits begonnene aktive Missionen (höchster %-Fortschritt zuerst)
  /// 2. Frische aktive Missionen
  /// 3. Abgeschlossene
  /// Innerhalb gleicher Stufe Reihenfolge: Daily → Weekly → Saisonal → Achievement.
  List<Mission> _filterAndSort(List<Mission> missions) {
    final activeDaily = MissionSeed.pickActiveDailyIds();
    final activeWeekly = MissionSeed.pickActiveWeeklyIds();
    final visible = missions.where((m) {
      switch (m.type) {
        case MissionType.daily:
          return activeDaily.contains(m.id);
        case MissionType.weekly:
          return activeWeekly.contains(m.id);
        case MissionType.seasonal:
        case MissionType.achievement:
          return true;
      }
    }).toList();

    int typeRank(MissionType t) => switch (t) {
      MissionType.daily => 0,
      MissionType.weekly => 1,
      MissionType.seasonal => 2,
      MissionType.achievement => 3,
    };

    int statusRank(Mission m) {
      if (m.isCompleted) return 2;
      if (m.progress > 0) return 0; // angefangen → ganz nach oben
      return 1;
    }

    visible.sort((a, b) {
      final s = statusRank(a).compareTo(statusRank(b));
      if (s != 0) return s;
      final t = typeRank(a.type).compareTo(typeRank(b.type));
      if (t != 0) return t;
      // Innerhalb: höherer Fortschritt zuerst (näher am Ziel = sichtbarer)
      final p = b.progressPercent.compareTo(a.progressPercent);
      if (p != 0) return p;
      return a.title.compareTo(b.title);
    });
    return visible;
  }

  /// Setzt abgelaufene Daily-/Weekly-/Saisonal-Missionen zurück und vergibt
  /// neue `expiresAt`. Achievement-Missionen bleiben unberührt.
  /// Daily/Weekly-Missionen, die im Pool nicht aktiv ausgewählt sind, werden
  /// ebenfalls in einen sauberen Ausgangszustand zurückgesetzt — so haben
  /// sie keinen alten Fortschritt, wenn sie an einem späteren Tag wieder
  /// vom Pool gezogen werden.
  /// Wird bei jedem `build()` und vor jedem `updateProgress` aufgerufen, damit
  /// sich Quests auch dann zurücksetzen, wenn die App über Mitternacht oder
  /// einen Wochenwechsel offen geblieben ist.
  Future<List<Mission>> _rolloverIfNeeded(List<Mission> missions) async {
    final now = DateTime.now();
    final todayEnd = MissionSeed.currentDayEnd(now);
    final weekEnd = MissionSeed.currentWeekEnd(now);
    final seasonEnd = MissionSeed.currentSeasonEnd(now);
    final activeDaily = MissionSeed.pickActiveDailyIds(now);
    final activeWeekly = MissionSeed.pickActiveWeeklyIds(now);
    final result = <Mission>[];
    for (final m in missions) {
      DateTime? newExpires;
      bool isInActiveSlot;
      switch (m.type) {
        case MissionType.daily:
          newExpires = todayEnd;
          isInActiveSlot = activeDaily.contains(m.id);
          break;
        case MissionType.weekly:
          newExpires = weekEnd;
          isInActiveSlot = activeWeekly.contains(m.id);
          break;
        case MissionType.seasonal:
          newExpires = seasonEnd;
          isInActiveSlot = true;
          break;
        case MissionType.achievement:
          result.add(m);
          continue;
      }
      final expired = m.expiresAt == null || now.isAfter(m.expiresAt!);
      // Inaktive Slot-Missionen mit altem Fortschritt zurücksetzen, damit
      // sie beim nächsten Auftauchen sauber bei 0 starten.
      final needsCleanReset =
          !isInActiveSlot && (m.progress > 0 || m.isCompleted);
      if (expired || needsCleanReset) {
        final reset = Mission(
          id: m.id,
          title: m.title,
          description: m.description,
          emoji: m.emoji,
          type: m.type,
          pointsReward: m.pointsReward,
          status: MissionStatus.active,
          progress: 0,
          goal: m.goal,
          completedAt: null,
          expiresAt: newExpires,
        );
        await _db.updateMission(reset);
        result.add(reset);
      } else {
        result.add(m);
      }
    }
    return result;
  }

  Future<void> updateProgress(String missionId, int newProgress) async {
    // Erst Rollover, damit ein neuer Tag/eine neue Woche eine zuvor
    // abgeschlossene Mission wieder „active" macht und der Fortschritt
    // sauber neu gezählt wird.
    final fromDb = await _db.getMissions();
    final processed = await _rolloverIfNeeded(fromDb);
    final missions = _filterAndSort(processed);
    state = AsyncData(missions);

    final idx = missions.indexWhere((m) => m.id == missionId);
    if (idx == -1) return; // ID ist heute/diese Woche nicht im aktiven Pool

    final mission = missions[idx];
    if (mission.isCompleted) return;

    final updated = mission.copyWith(
      progress: newProgress,
      status: newProgress >= mission.goal
          ? MissionStatus.completed
          : MissionStatus.active,
      completedAt: newProgress >= mission.goal ? DateTime.now() : null,
    );
    await _db.updateMission(updated);
    final next = [
      for (int i = 0; i < missions.length; i++)
        if (i == idx) updated else missions[i],
    ];
    state = AsyncData(_filterAndSort(next));
  }
}

final missionProvider = AsyncNotifierProvider<MissionNotifier, List<Mission>>(
  MissionNotifier.new,
);

// ─── Stats Provider ───────────────────────────────────────────────────────────

final catchStatsProvider = FutureProvider<CatchStats>((ref) async {
  final catches = await ref.watch(catchProvider.future);
  return CatchStats.from(catches);
});

class CatchStats {
  final int total;
  final Map<FishSpecies, int> perSpecies;
  final CatchEntry? personalBest;
  final String? topLure;
  final int totalPoints;

  const CatchStats({
    required this.total,
    required this.perSpecies,
    this.personalBest,
    this.topLure,
    required this.totalPoints,
  });

  factory CatchStats.from(List<CatchEntry> catches) {
    final perSpecies = <FishSpecies, int>{};
    final lureCount = <String, int>{};
    // Pro Köder die "Bestleistung" merken: maximale Länge, danach Gewicht.
    final lureBestLength = <String, double>{};
    final lureBestWeight = <String, int>{};
    CatchEntry? best;

    for (final c in catches) {
      perSpecies[c.species] = (perSpecies[c.species] ?? 0) + 1;
      final lure = c.lure;
      if (lure != null) {
        lureCount[lure] = (lureCount[lure] ?? 0) + 1;
        final len = c.lengthCm ?? 0;
        if (len > (lureBestLength[lure] ?? 0)) lureBestLength[lure] = len;
        final w = c.weightG ?? 0;
        if (w > (lureBestWeight[lure] ?? 0)) lureBestWeight[lure] = w;
      }
      // Globaler PB: längster Fang über alle Arten — Gewicht als Tiebreaker.
      if (best == null) {
        best = c;
      } else {
        final cs = (c.lengthCm ?? 0) * 10000 + (c.weightG ?? 0);
        final bs = (best.lengthCm ?? 0) * 10000 + (best.weightG ?? 0);
        if (cs > bs) best = c;
      }
    }

    // Tiebreaker: höchste Anzahl > größte Fischlänge > schwerstes Gewicht.
    String? topLure;
    if (lureCount.isNotEmpty) {
      final sorted = lureCount.keys.toList()
        ..sort((a, b) {
          final byCount = lureCount[b]!.compareTo(lureCount[a]!);
          if (byCount != 0) return byCount;
          final byLen = (lureBestLength[b] ?? 0).compareTo(
            lureBestLength[a] ?? 0,
          );
          if (byLen != 0) return byLen;
          return (lureBestWeight[b] ?? 0).compareTo(lureBestWeight[a] ?? 0);
        });
      topLure = sorted.first;
    }

    return CatchStats(
      total: catches.length,
      perSpecies: perSpecies,
      personalBest: best,
      topLure: topLure,
      totalPoints: catches.length * 50,
    );
  }
}

// ─── Mission-Logik (intern) ────────────────────────────────────────────────────

final _missionService = _MissionService();

class _MissionService {
  Future<void> onCatchAdded(
    CatchEntry entry,
    List<CatchEntry> catches,
    Ref ref,
  ) async {
    final missions = ref.read(missionProvider).valueOrNull ?? [];
    final notifier = ref.read(missionProvider.notifier);

    for (final m in missions) {
      if (m.isCompleted) continue;
      switch (m.id) {
        // ─── Daily ─────────────────────────────────────────────────────────
        case 'daily_first_cast':
          final todayCount = catches.where((c) => _isToday(c.caughtAt)).length;
          await notifier.updateProgress(m.id, todayCount);
        case 'daily_dawn_hunter':
          if (_isToday(entry.caughtAt) && entry.caughtAt.hour < 8) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_night_owl':
          if (_isToday(entry.caughtAt) && entry.caughtAt.hour >= 22) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_photo_proof':
          if (_isToday(entry.caughtAt) &&
              (entry.photoPath?.isNotEmpty ?? false)) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_spot_tagged':
          if (_isToday(entry.caughtAt) && entry.spotId != null) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_big_fish':
          if (_isToday(entry.caughtAt) && (entry.weightG ?? 0) >= 2000) {
            await notifier.updateProgress(m.id, 1);
          }

        // ─── Weekly ────────────────────────────────────────────────────────
        case 'weekly_triple_threat':
          final weekSpecies = catches
              .where((c) => _isThisWeek(c.caughtAt))
              .map((c) => c.species)
              .toSet()
              .length;
          await notifier.updateProgress(m.id, weekSpecies);
        case 'weekly_big_five':
          final weekCount = catches
              .where((c) => _isThisWeek(c.caughtAt))
              .length;
          await notifier.updateProgress(m.id, weekCount);
        case 'weekly_spot_tour':
          final spots = catches
              .where((c) => _isThisWeek(c.caughtAt) && c.spotId != null)
              .map((c) => c.spotId)
              .toSet()
              .length;
          await notifier.updateProgress(m.id, spots);
        case 'weekly_technique_master':
          final styles = catches
              .where((c) => _isThisWeek(c.caughtAt))
              .expand((c) => c.retrieveStyles)
              .toSet()
              .length;
          await notifier.updateProgress(m.id, styles);
        case 'weekly_total_weight':
          final totalG = catches
              .where((c) => _isThisWeek(c.caughtAt))
              .fold<int>(0, (s, c) => s + (c.weightG ?? 0));
          await notifier.updateProgress(m.id, totalG ~/ 1000);
        case 'weekly_dawn_streak':
          final count = catches
              .where((c) => _isThisWeek(c.caughtAt) && c.caughtAt.hour < 8)
              .length;
          await notifier.updateProgress(m.id, count);

        // ─── Seasonal ──────────────────────────────────────────────────────
        case 'season_zander_hunter':
          final count = catches
              .where(
                (c) =>
                    _isThisSeason(c.caughtAt) &&
                    c.species == FishSpecies.zander,
              )
              .length;
          await notifier.updateProgress(m.id, count);
        case 'season_pike_trophy':
          if (entry.species == FishSpecies.hecht &&
              (entry.lengthCm ?? 0) >= 80) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'season_perch_stack':
          final count = catches
              .where(
                (c) =>
                    _isThisSeason(c.caughtAt) &&
                    c.species == FishSpecies.barsch,
              )
              .length;
          await notifier.updateProgress(m.id, count);
        // ─── Achievements ──────────────────────────────────────────────────
        case 'ach_micro_jig':
          if (entry.species == FishSpecies.barsch &&
              (entry.lure?.toLowerCase().contains('micro') ?? false)) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_ten_catches':
          await notifier.updateProgress(m.id, catches.length);
        case 'ach_metric_master':
          if ((entry.lengthCm ?? 0) >= 100) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_heavyweight':
          if ((entry.weightG ?? 0) >= 5000) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_all_species':
          final distinct = catches
              .map((c) => c.species)
              .where((s) => s != FishSpecies.andere)
              .toSet()
              .length;
          await notifier.updateProgress(m.id, distinct);
        case 'ach_photo_collector':
          final n = catches
              .where((c) => (c.photoPath?.isNotEmpty ?? false))
              .length;
          await notifier.updateProgress(m.id, n);
        case 'ach_jig_specialist':
          final n = catches
              .where((c) => c.retrieveStyles.contains(RetrieveStyle.jig))
              .length;
          await notifier.updateProgress(m.id, n);
        case 'ach_century':
          await notifier.updateProgress(m.id, catches.length);

        // ─── Zusatz-Daily ──────────────────────────────────────────────────
        case 'daily_double':
          final n = catches.where((c) => _isToday(c.caughtAt)).length;
          await notifier.updateProgress(m.id, n);
        case 'daily_species_duo':
          final n = catches
              .where((c) => _isToday(c.caughtAt))
              .map((c) => c.species)
              .toSet()
              .length;
          await notifier.updateProgress(m.id, n);
        case 'daily_early_bird':
          if (_isToday(entry.caughtAt) && entry.caughtAt.hour < 6) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_detailed_log':
          if (_isToday(entry.caughtAt) &&
              (entry.lure?.isNotEmpty ?? false) &&
              (entry.lureColor?.isNotEmpty ?? false) &&
              entry.depthM != null) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_note_keeper':
          if (_isToday(entry.caughtAt) &&
              (entry.notes?.trim().isNotEmpty ?? false)) {
            await notifier.updateProgress(m.id, 1);
          }

        // ─── Zusatz-Weekly ─────────────────────────────────────────────────
        case 'weekly_marathon':
          final n = catches.where((c) => _isThisWeek(c.caughtAt)).length;
          await notifier.updateProgress(m.id, n);
        case 'weekly_five_days':
          final days = catches
              .where((c) => _isThisWeek(c.caughtAt))
              .map(
                (c) =>
                    DateTime(c.caughtAt.year, c.caughtAt.month, c.caughtAt.day),
              )
              .toSet()
              .length;
          await notifier.updateProgress(m.id, days);
        case 'weekly_pike_pack':
          final n = catches
              .where(
                (c) =>
                    _isThisWeek(c.caughtAt) && c.species == FishSpecies.hecht,
              )
              .length;
          await notifier.updateProgress(m.id, n);
        case 'weekly_notes_log':
          final n = catches
              .where(
                (c) =>
                    _isThisWeek(c.caughtAt) &&
                    (c.notes?.trim().isNotEmpty ?? false),
              )
              .length;
          await notifier.updateProgress(m.id, n);

        // ─── Zusatz-Seasonal ───────────────────────────────────────────────
        case 'season_wels':
          final n = catches
              .where(
                (c) =>
                    _isThisSeason(c.caughtAt) && c.species == FishSpecies.wels,
              )
              .length;
          await notifier.updateProgress(m.id, n);
        case 'season_forelle_trio':
          final n = catches
              .where(
                (c) =>
                    _isThisSeason(c.caughtAt) &&
                    c.species == FishSpecies.forelle,
              )
              .length;
          await notifier.updateProgress(m.id, n);
        case 'season_total_length':
          final total = catches
              .where((c) => _isThisSeason(c.caughtAt))
              .fold<double>(0, (s, c) => s + (c.lengthCm ?? 0));
          await notifier.updateProgress(m.id, total.toInt());
        case 'season_deep_spots':
          final n = catches
              .where((c) => _isThisSeason(c.caughtAt) && (c.depthM ?? 0) > 5)
              .length;
          await notifier.updateProgress(m.id, n);
        case 'season_ten_spots':
          final n = catches
              .where((c) => _isThisSeason(c.caughtAt) && c.spotId != null)
              .map((c) => c.spotId)
              .toSet()
              .length;
          await notifier.updateProgress(m.id, n);

        // ─── Zusatz-Achievements ───────────────────────────────────────────
        case 'ach_huchen':
          if (entry.species == FishSpecies.huchen) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_aal':
          if (entry.species == FishSpecies.aal) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_wels_trophy':
          if (entry.species == FishSpecies.wels &&
              (entry.lengthCm ?? 0) >= 100) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_all_retrieves':
          final styles = catches.expand((c) => c.retrieveStyles).toSet().length;
          await notifier.updateProgress(m.id, styles);
        case 'ach_lure_collector':
          final lures = catches
              .where((c) => (c.lure?.trim().isNotEmpty ?? false))
              .map((c) => c.lure!.trim().toLowerCase())
              .toSet()
              .length;
          await notifier.updateProgress(m.id, lures);

        // ─── Daily Extra 2 ─────────────────────────────────────────────────
        case 'daily_noon_strike':
          if (_isToday(entry.caughtAt) &&
              entry.caughtAt.hour >= 11 &&
              entry.caughtAt.hour < 14) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_drill_fight':
          if (_isToday(entry.caughtAt) && (entry.drillDurationSec ?? 0) > 60) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_precise_log':
          if (_isToday(entry.caughtAt) &&
              entry.weightG != null &&
              entry.lengthCm != null) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_nature_writer':
          if (_isToday(entry.caughtAt) &&
              (entry.notes?.trim().length ?? 0) >= 50) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_back_to_back':
          final today = catches.where((c) => _isToday(c.caughtAt)).toList()
            ..sort((a, b) => a.caughtAt.compareTo(b.caughtAt));
          var hit = false;
          for (var i = 1; i < today.length; i++) {
            if (today[i].caughtAt.difference(today[i - 1].caughtAt).inMinutes <=
                60) {
              hit = true;
              break;
            }
          }
          if (hit) await notifier.updateProgress(m.id, 1);

        // ─── Weekly Extra 2 ────────────────────────────────────────────────
        case 'weekly_lure_variety':
          final lures = catches
              .where(
                (c) =>
                    _isThisWeek(c.caughtAt) &&
                    (c.lure?.trim().isNotEmpty ?? false),
              )
              .map((c) => c.lure!.trim().toLowerCase())
              .toSet()
              .length;
          await notifier.updateProgress(m.id, lures);
        case 'weekly_slow_approach':
          final n = catches
              .where(
                (c) =>
                    _isThisWeek(c.caughtAt) &&
                    c.retrieveStyles.contains(RetrieveStyle.slow),
              )
              .length;
          await notifier.updateProgress(m.id, n);
        case 'weekly_dusk_dawn':
          final hasDawn = catches.any(
            (c) => _isThisWeek(c.caughtAt) && c.caughtAt.hour < 8,
          );
          final hasDusk = catches.any(
            (c) => _isThisWeek(c.caughtAt) && c.caughtAt.hour >= 20,
          );
          await notifier.updateProgress(
            m.id,
            (hasDawn ? 1 : 0) + (hasDusk ? 1 : 0),
          );
        case 'weekly_heavy_single':
          final hit = catches.any(
            (c) => _isThisWeek(c.caughtAt) && (c.weightG ?? 0) >= 3000,
          );
          if (hit) await notifier.updateProgress(m.id, 1);
        case 'weekly_color_variety':
          final colors = catches
              .where(
                (c) =>
                    _isThisWeek(c.caughtAt) &&
                    (c.lureColor?.trim().isNotEmpty ?? false),
              )
              .map((c) => c.lureColor!.trim().toLowerCase())
              .toSet()
              .length;
          await notifier.updateProgress(m.id, colors);

        // ─── Seasonal Extra 2 ──────────────────────────────────────────────
        case 'season_all_weekdays':
          final weekdays = catches
              .where((c) => _isThisSeason(c.caughtAt))
              .map((c) => c.caughtAt.weekday)
              .toSet()
              .length;
          await notifier.updateProgress(m.id, weekdays);
        case 'season_fifty_photos':
          final n = catches
              .where(
                (c) =>
                    _isThisSeason(c.caughtAt) &&
                    (c.photoPath?.isNotEmpty ?? false),
              )
              .length;
          await notifier.updateProgress(m.id, n);
        case 'season_night_fish':
          final n = catches
              .where((c) => _isThisSeason(c.caughtAt) && c.caughtAt.hour < 4)
              .length;
          await notifier.updateProgress(m.id, n);

        // ─── Achievement Extra 2 ───────────────────────────────────────────
        case 'ach_weight_sum_50kg':
          final totalG = catches.fold<int>(0, (s, c) => s + (c.weightG ?? 0));
          await notifier.updateProgress(m.id, totalG ~/ 1000);
        case 'ach_length_sum_10m':
          final total = catches.fold<double>(
            0,
            (s, c) => s + (c.lengthCm ?? 0),
          );
          await notifier.updateProgress(m.id, total.toInt());
        case 'ach_long_drill':
          if ((entry.drillDurationSec ?? 0) >= 300) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_color_collector':
          final colors = catches
              .where((c) => (c.lureColor?.trim().isNotEmpty ?? false))
              .map((c) => c.lureColor!.trim().toLowerCase())
              .toSet()
              .length;
          await notifier.updateProgress(m.id, colors);
        case 'ach_spot_regular':
          final counts = <String, int>{};
          for (final c in catches) {
            if (c.spotId != null) {
              counts[c.spotId!] = (counts[c.spotId!] ?? 0) + 1;
            }
          }
          final maxAtSpot = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
          await notifier.updateProgress(m.id, maxAtSpot);

        // ─── Erstfang je Hauptart ────────────────────────────────────────
        case 'ach_first_hecht':
          if (catches.any((c) => c.species == FishSpecies.hecht)) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_first_zander':
          if (catches.any((c) => c.species == FishSpecies.zander)) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_first_barsch':
          if (catches.any((c) => c.species == FishSpecies.barsch)) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_first_wels':
          if (catches.any((c) => c.species == FishSpecies.wels)) {
            await notifier.updateProgress(m.id, 1);
          }

        // ─── Hecht-Größen-Meilensteine ────────────────────────────────────
        case 'ach_pike_80':
          if (catches.any(
            (c) => c.species == FishSpecies.hecht && (c.lengthCm ?? 0) >= 80,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_pike_100':
          if (catches.any(
            (c) => c.species == FishSpecies.hecht && (c.lengthCm ?? 0) >= 100,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_pike_110':
          if (catches.any(
            (c) => c.species == FishSpecies.hecht && (c.lengthCm ?? 0) >= 110,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_pike_120':
          if (catches.any(
            (c) => c.species == FishSpecies.hecht && (c.lengthCm ?? 0) >= 120,
          )) {
            await notifier.updateProgress(m.id, 1);
          }

        // ─── Zander-Größen-Meilensteine ──────────────────────────────────
        case 'ach_zander_50':
          if (catches.any(
            (c) => c.species == FishSpecies.zander && (c.lengthCm ?? 0) >= 50,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_zander_60':
          if (catches.any(
            (c) => c.species == FishSpecies.zander && (c.lengthCm ?? 0) >= 60,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_zander_70':
          if (catches.any(
            (c) => c.species == FishSpecies.zander && (c.lengthCm ?? 0) >= 70,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_zander_80':
          if (catches.any(
            (c) => c.species == FishSpecies.zander && (c.lengthCm ?? 0) >= 80,
          )) {
            await notifier.updateProgress(m.id, 1);
          }

        // ─── Barsch-Größen-Meilensteine ───────────────────────────────────
        case 'ach_perch_30':
          if (catches.any(
            (c) => c.species == FishSpecies.barsch && (c.lengthCm ?? 0) >= 30,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_perch_40':
          if (catches.any(
            (c) => c.species == FishSpecies.barsch && (c.lengthCm ?? 0) >= 40,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_perch_50':
          if (catches.any(
            (c) => c.species == FishSpecies.barsch && (c.lengthCm ?? 0) >= 50,
          )) {
            await notifier.updateProgress(m.id, 1);
          }

        // ─── Wels-Größen-Meilensteine ────────────────────────────────────
        case 'ach_wels_150':
          if (catches.any(
            (c) => c.species == FishSpecies.wels && (c.lengthCm ?? 0) >= 150,
          )) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'ach_wels_200':
          if (catches.any(
            (c) => c.species == FishSpecies.wels && (c.lengthCm ?? 0) >= 200,
          )) {
            await notifier.updateProgress(m.id, 1);
          }

        // ─── Daily Köder-Typ ─────────────────────────────────────────────
        case 'daily_rubber_fish':
          if (_isToday(entry.caughtAt) &&
              _lureMatches(entry.lure, [
                'gummi',
                'shad',
                'twister',
                'slug',
                'grub',
              ])) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_spinner':
          if (_isToday(entry.caughtAt) &&
              _lureMatches(entry.lure, [
                'spinner',
                'mepps',
                'blue fox',
                'rooster',
              ])) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_wobbler':
          if (_isToday(entry.caughtAt) &&
              _lureMatches(entry.lure, [
                'wobbler',
                'crankbait',
                'rapala',
                'plug',
                'minnow',
              ])) {
            await notifier.updateProgress(m.id, 1);
          }
        case 'daily_blinker':
          if (_isToday(entry.caughtAt) &&
              _lureMatches(entry.lure, [
                'blinker',
                'löffel',
                'spoon',
                'abu',
                'toby',
              ])) {
            await notifier.updateProgress(m.id, 1);
          }
      }
    }
  }

  Future<void> onSpotAdded(List<FishingSpot> spots, Ref ref) async {
    final missions = ref.read(missionProvider).valueOrNull ?? [];
    final notifier = ref.read(missionProvider.notifier);
    for (final m in missions) {
      if (m.isCompleted) continue;
      if (m.id == 'ach_first_spot') {
        await notifier.updateProgress(m.id, spots.length.clamp(0, 1));
      } else if (m.id == 'ach_twenty_spots') {
        await notifier.updateProgress(m.id, spots.length);
      } else if (m.id == 'weekly_spot_creator') {
        final n = spots.where((s) => _isThisWeek(s.createdAt)).length;
        await notifier.updateProgress(m.id, n);
      }
    }
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  bool _isThisWeek(DateTime dt) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return dt.isAfter(start);
  }

  bool _isThisSeason(DateTime dt) {
    final now = DateTime.now();
    return dt.isAfter(_seasonStart(now)) && dt.isBefore(_seasonEnd(now));
  }

  /// Prüft ob [lure] (Freitext) einen der [keywords] enthält (case-insensitive).
  bool _lureMatches(String? lure, List<String> keywords) {
    if (lure == null || lure.trim().isEmpty) return false;
    final lower = lure.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }

  // Quartal: Q1=Jan–Mär, Q2=Apr–Jun, Q3=Jul–Sep, Q4=Okt–Dez
  DateTime _seasonStart(DateTime now) {
    final q = ((now.month - 1) ~/ 3) * 3 + 1; // erster Monat des Quartals
    return DateTime(now.year, q, 1);
  }

  DateTime _seasonEnd(DateTime now) {
    final q = ((now.month - 1) ~/ 3) * 3 + 3; // letzter Monat des Quartals
    final lastDay = DateUtils.getDaysInMonth(now.year, q);
    return DateTime(now.year, q, lastDay, 23, 59, 59);
  }
}
