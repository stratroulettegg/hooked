import 'package:intl/intl.dart';

import '../../../core/format/app_formats.dart';
import '../../models/catch_entry.dart';
import '../../models/trip.dart';
import 'notification_categories.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

/// Wertet die Daten der App aus und stößt — wo nötig — passende
/// Notifications an. Wird beim App-Start und bei Daten-Änderungen aufgerufen.
class NotificationScheduler {
  NotificationScheduler._();
  static final NotificationScheduler instance = NotificationScheduler._();

  final NotificationService _svc = NotificationService.instance;

  // ─── Trips ────────────────────────────────────────────────────────────────

  /// Plant Trip-Vorabend + Trip-Tag-Morgen für alle zukünftigen Trips.
  /// Bestehende Reminder werden vorher gecancelt, damit Datum/Name-Änderungen
  /// sauber durchgreifen.
  Future<void> rescheduleAllTrips(List<Trip> trips) async {
    if (!_svc.isReady) return;
    if (!NotificationPrefs.isEnabled(NotificationCategory.tripReminder)) {
      for (final t in trips) {
        await _svc.cancelTripReminders(t.id);
      }
      return;
    }
    final now = DateTime.now();
    for (final t in trips) {
      // Nur zukünftige & innerhalb der nächsten 90 Tage planen.
      final tripDay = DateTime(t.date.year, t.date.month, t.date.day);
      final today = DateTime(now.year, now.month, now.day);
      final diff = tripDay.difference(today).inDays;
      if (diff < 0 || diff > 90) {
        await _svc.cancelTripReminders(t.id);
        continue;
      }
      await _svc.scheduleTripReminders(
        tripId: t.id,
        tripName: t.name,
        tripDate: t.date,
        waterBodyName: t.waterBodyName,
      );
    }
  }

  Future<void> cancelTrip(String tripId) => _svc.cancelTripReminders(tripId);

  // ─── Reaktive Checks (App-Start) ──────────────────────────────────────────

  /// Hauptcheck — wertet alle Datenquellen aus und löst passende
  /// reaktive Notifications aus. Idempotent (nutzt LastTriggered-Marker).
  Future<void> runStartupChecks({
    required List<CatchEntry> catches,
    required List<Trip> trips,
  }) async {
    if (!_svc.isReady) return;

    await rescheduleAllTrips(trips);

    final now = DateTime.now();
    if (NotificationPrefs.isQuiet(now)) return;

    await _checkDocNudge(catches, now);
    await _checkStreakWarning(catches, trips, now);
    await _checkOnThisDay(catches, now);
    await _checkFirstWaterOfMonth(now);
    await _checkMonthlyRecap(catches, now);
    await _checkWeeklyRecap(catches, now);
  }

  // ─── Doku-Nudge ───────────────────────────────────────────────────────────

  Future<void> _checkDocNudge(List<CatchEntry> catches, DateTime now) async {
    // Folgetag, frühestens 18:00.
    if (now.hour < 18) return;
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final tomorrowStart = DateTime(now.year, now.month, now.day);
    final relevant = catches.where((c) {
      final d = c.caughtAt;
      return !d.isBefore(yesterday) && d.isBefore(tomorrowStart);
    }).toList();
    if (relevant.isEmpty) return;
    final missing = relevant.where((c) {
      final hasPhoto = c.photoPath != null && c.photoPath!.trim().isNotEmpty;
      final hasNotes = c.notes != null && c.notes!.trim().isNotEmpty;
      return !hasPhoto || !hasNotes;
    }).length;
    if (missing == 0) return;
    await _svc.showDocNudge(catchCountWithoutDoc: missing);
  }

  // ─── Streak-Schutz ────────────────────────────────────────────────────────

  Future<void> _checkStreakWarning(
    List<CatchEntry> catches,
    List<Trip> trips,
    DateTime now,
  ) async {
    // Nur abends prüfen — sonst zu nervig morgens.
    if (now.hour < 17) return;
    final today = DateTime(now.year, now.month, now.day);
    final waterDays = <DateTime>{};
    for (final c in catches) {
      final d = c.caughtAt;
      waterDays.add(DateTime(d.year, d.month, d.day));
    }
    for (final t in trips) {
      final d = t.date;
      // nur vergangene oder heutige Trips zählen
      final dd = DateTime(d.year, d.month, d.day);
      if (!dd.isAfter(today)) waterDays.add(dd);
    }
    // Streak: Anzahl aufeinanderfolgender Tage bis gestern (heute zählt nur,
    // wenn schon was eingetragen wurde — wenn nicht, ist Streak in Gefahr).
    if (waterDays.contains(today)) return; // heute schon ok
    int streak = 0;
    var cur = today.subtract(const Duration(days: 1));
    while (waterDays.contains(cur)) {
      streak++;
      cur = cur.subtract(const Duration(days: 1));
    }
    if (streak < 3) return; // erst ab 3 Tagen interessant
    await _svc.showStreakWarning(streakDays: streak);
  }

  // ─── On-This-Day ──────────────────────────────────────────────────────────

  Future<void> _checkOnThisDay(List<CatchEntry> catches, DateTime now) async {
    // Nur Sonntags zwischen 17 und 19.
    if (now.weekday != DateTime.sunday) return;
    if (now.hour < 17 || now.hour >= 19) return;

    final lastYear = DateTime(now.year - 1, now.month, now.day);
    final from = lastYear.subtract(const Duration(days: 3));
    final to = lastYear.add(const Duration(days: 3));
    final hits = catches.where((c) {
      return !c.caughtAt.isBefore(from) && !c.caughtAt.isAfter(to);
    }).toList();
    if (hits.isEmpty) return;
    // Stärksten Fang aussuchen (Gewicht > Länge)
    hits.sort((a, b) {
      final w = (b.weightG ?? 0).compareTo(a.weightG ?? 0);
      if (w != 0) return w;
      return (b.lengthCm ?? 0).compareTo(a.lengthCm ?? 0);
    });
    final best = hits.first;
    final dateStr = DateFormat('dd.MM.', 'de').format(best.caughtAt);
    final lengthPart = best.lengthCm != null
        ? ' ${AppNum.cm(best.lengthCm!)}'
        : '';
    final body =
        'Vor einem Jahr ($dateStr): ${best.species.displayName}$lengthPart. '
        'Wieder hin?';
    await _svc.showOnThisDay(body: body);
  }

  // ─── Erstes Wasser im neuen Monat ────────────────────────────────────────

  Future<void> _checkFirstWaterOfMonth(DateTime now) async {
    // Nur am 1. eines Monats vormittags.
    if (now.day != 1) return;
    if (now.hour < 9 || now.hour >= 12) return;
    await _svc.showFirstWaterOfMonth();
  }

  // ─── Monats-Recap ─────────────────────────────────────────────────────────

  Future<void> _checkMonthlyRecap(
    List<CatchEntry> catches,
    DateTime now,
  ) async {
    if (now.day != 1) return;
    if (now.hour < 19 || now.hour >= 21) return;
    // Vergangener Monat
    final prev = DateTime(now.year, now.month - 1, 1);
    final start = prev;
    final end = DateTime(prev.year, prev.month + 1, 1);
    final inMonth = catches.where((c) {
      return !c.caughtAt.isBefore(start) && c.caughtAt.isBefore(end);
    }).toList();
    if (inMonth.isEmpty) return;
    final speciesCount = inMonth.map((e) => e.species).toSet().length;
    final monthLabel = DateFormat('MMMM', 'de').format(prev);
    final body =
        '$monthLabel: ${inMonth.length} Fänge, $speciesCount Arten. '
        'Tap für Details.';
    await _svc.showMonthlyRecap(body: body);
  }

  // ─── Wochen-Recap ─────────────────────────────────────────────────────────

  Future<void> _checkWeeklyRecap(List<CatchEntry> catches, DateTime now) async {
    if (now.weekday != DateTime.sunday) return;
    if (now.hour < 19 || now.hour >= 21) return;
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));
    final weekEnd = today.add(const Duration(days: 1));
    final inWeek = catches.where((c) {
      return !c.caughtAt.isBefore(weekStart) && c.caughtAt.isBefore(weekEnd);
    }).toList();
    final daysWithCatch = inWeek
        .map((c) => DateTime(c.caughtAt.year, c.caughtAt.month, c.caughtAt.day))
        .toSet()
        .length;
    final body = inWeek.isEmpty
        ? 'Diese Woche: 0 Fänge — neuer Anlauf nächste Woche?'
        : 'Diese Woche: ${inWeek.length} Fänge an $daysWithCatch '
              '${daysWithCatch == 1 ? "Tag" : "Tagen"}. Tap für Details.';
    await _svc.showWeeklyRecap(body: body);
  }
}
