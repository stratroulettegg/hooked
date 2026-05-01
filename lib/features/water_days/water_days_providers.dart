import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/local_database_service.dart';

/// Repräsentiert einen einzelnen "Tag am Wasser" inklusive Quelle,
/// damit die UI z. B. zwischen automatischen und manuell markierten
/// Tagen unterscheiden kann.
enum WaterDaySource { catchEntry, trip, manual }

class WaterDay {
  WaterDay({required this.date, required this.sources});

  /// Datum auf 00:00 normalisiert.
  final DateTime date;
  final Set<WaterDaySource> sources;

  bool get isManualOnly =>
      sources.length == 1 && sources.contains(WaterDaySource.manual);
  bool get hasCatch => sources.contains(WaterDaySource.catchEntry);
  bool get hasTrip => sources.contains(WaterDaySource.trip);
  bool get isManual => sources.contains(WaterDaySource.manual);

  String get isoDate {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _iso(DateTime d) {
  final dd = _dateOnly(d);
  final y = dd.year.toString().padLeft(4, '0');
  final m = dd.month.toString().padLeft(2, '0');
  final day = dd.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime _fromIso(String iso) {
  final parts = iso.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

// ─── Manuelle Wassertage ────────────────────────────────────────────────────

class ManualWaterDaysNotifier extends AsyncNotifier<Set<String>> {
  final _db = LocalDatabaseService();

  @override
  Future<Set<String>> build() async {
    final list = await _db.getManualWaterDays();
    return list.toSet();
  }

  /// Markiert einen Tag manuell als "am Wasser". Idempotent.
  Future<void> add(DateTime date) async {
    final iso = _iso(date);
    await _db.insertWaterDay(iso);
    final cur = state.valueOrNull ?? <String>{};
    state = AsyncData({...cur, iso});
  }

  Future<void> remove(DateTime date) async {
    final iso = _iso(date);
    await _db.deleteWaterDay(iso);
    final cur = state.valueOrNull ?? <String>{};
    state = AsyncData({...cur}..remove(iso));
  }

  bool contains(DateTime date) {
    return (state.valueOrNull ?? const <String>{}).contains(_iso(date));
  }
}

final manualWaterDaysProvider =
    AsyncNotifierProvider<ManualWaterDaysNotifier, Set<String>>(
        ManualWaterDaysNotifier.new);

// ─── Jahresziel (lokal in SharedPreferences) ────────────────────────────────

class YearGoalNotifier extends AsyncNotifier<int> {
  static const _prefsKey = 'water_days.year_goal';
  static const _defaultGoal = 50;

  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsKey) ?? _defaultGoal;
  }

  Future<void> setGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, goal);
    state = AsyncData(goal);
  }
}

final yearGoalProvider =
    AsyncNotifierProvider<YearGoalNotifier, int>(YearGoalNotifier.new);

// ─── Aggregierte Wassertage (Catches + Trips + Manuell) ─────────────────────

/// Liefert alle Wassertage chronologisch absteigend, gemerged aus den
/// drei Quellen.
final waterDaysProvider = Provider<List<WaterDay>>((ref) {
  final catches = ref.watch(catchProvider).valueOrNull ?? const [];
  final trips = ref.watch(tripProvider).valueOrNull ?? const [];
  final manual = ref.watch(manualWaterDaysProvider).valueOrNull ?? const {};

  final map = <String, Set<WaterDaySource>>{};

  for (final c in catches) {
    map
        .putIfAbsent(_iso(c.caughtAt), () => <WaterDaySource>{})
        .add(WaterDaySource.catchEntry);
  }
  for (final t in trips) {
    map
        .putIfAbsent(_iso(t.date), () => <WaterDaySource>{})
        .add(WaterDaySource.trip);
  }
  for (final iso in manual) {
    map.putIfAbsent(iso, () => <WaterDaySource>{}).add(WaterDaySource.manual);
  }

  final list = map.entries
      .map((e) => WaterDay(date: _fromIso(e.key), sources: e.value))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return list;
});

class WaterDaysSummary {
  WaterDaysSummary({
    required this.year,
    required this.daysThisYear,
    required this.totalDays,
    required this.currentStreakDays,
    required this.currentStreakWeeks,
    required this.longestStreakDays,
    required this.firstDay,
    required this.lastDay,
  });

  final int year;
  final int daysThisYear;
  final int totalDays;

  /// Aufeinanderfolgende Tage am Wasser bis heute (inkl. heute oder gestern).
  final int currentStreakDays;

  /// Aufeinanderfolgende Kalenderwochen mit ≥1 Tag am Wasser bis aktuelle Woche.
  final int currentStreakWeeks;
  final int longestStreakDays;

  final DateTime? firstDay;
  final DateTime? lastDay;
}

final waterDaysSummaryProvider = Provider<WaterDaysSummary>((ref) {
  final days = ref.watch(waterDaysProvider);
  final now = DateTime.now();
  final today = _dateOnly(now);
  final year = today.year;

  if (days.isEmpty) {
    return WaterDaysSummary(
      year: year,
      daysThisYear: 0,
      totalDays: 0,
      currentStreakDays: 0,
      currentStreakWeeks: 0,
      longestStreakDays: 0,
      firstDay: null,
      lastDay: null,
    );
  }

  final daySet = days.map((d) => _dateOnly(d.date)).toSet();
  final daysThisYear = daySet.where((d) => d.year == year).length;

  // Längster Streak (über alle Zeiten).
  final sorted = daySet.toList()..sort();
  int longest = 0;
  int run = 0;
  DateTime? prev;
  for (final d in sorted) {
    if (prev != null && d.difference(prev).inDays == 1) {
      run += 1;
    } else {
      run = 1;
    }
    if (run > longest) longest = run;
    prev = d;
  }

  // Aktueller Tages-Streak: zähle rückwärts ab heute (oder gestern, falls heute
  // noch nicht markiert ist), solange jeder Tag enthalten ist.
  int currentDays = 0;
  DateTime cursor = daySet.contains(today)
      ? today
      : (daySet.contains(today.subtract(const Duration(days: 1)))
          ? today.subtract(const Duration(days: 1))
          : today);
  while (daySet.contains(cursor)) {
    currentDays += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  // Aktueller Wochen-Streak: rückwärts ab dieser Kalenderwoche, solange jede
  // Woche mindestens einen Wassertag enthält.
  DateTime weekStart(DateTime d) {
    // Montag als Wochenstart (DateTime.monday == 1).
    final delta = (d.weekday - DateTime.monday) % 7;
    return _dateOnly(d).subtract(Duration(days: delta));
  }

  bool weekHasDay(DateTime monday) {
    for (int i = 0; i < 7; i++) {
      if (daySet.contains(monday.add(Duration(days: i)))) return true;
    }
    return false;
  }

  int currentWeeks = 0;
  DateTime weekCursor = weekStart(today);
  // Wenn diese Woche leer ist, prüfen wir trotzdem ab letzter Woche, damit
  // Mo morgens kein Streak-Bruch zeigt.
  if (!weekHasDay(weekCursor)) {
    weekCursor = weekCursor.subtract(const Duration(days: 7));
  }
  while (weekHasDay(weekCursor)) {
    currentWeeks += 1;
    weekCursor = weekCursor.subtract(const Duration(days: 7));
  }

  return WaterDaysSummary(
    year: year,
    daysThisYear: daysThisYear,
    totalDays: daySet.length,
    currentStreakDays: currentDays,
    currentStreakWeeks: currentWeeks,
    longestStreakDays: longest,
    firstDay: sorted.first,
    lastDay: sorted.last,
  );
});
