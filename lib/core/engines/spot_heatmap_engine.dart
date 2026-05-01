import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';

/// Tageszeit-Buckets für die Heatmap-Filterung.
enum DaytimeBucket {
  morning, // 5–10
  midday, // 10–14
  afternoon, // 14–18
  evening, // 18–22
  night; // 22–5

  String get displayName {
    switch (this) {
      case DaytimeBucket.morning:
        return 'Morgen';
      case DaytimeBucket.midday:
        return 'Mittag';
      case DaytimeBucket.afternoon:
        return 'Nachmittag';
      case DaytimeBucket.evening:
        return 'Abend';
      case DaytimeBucket.night:
        return 'Nacht';
    }
  }

  static DaytimeBucket of(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 10) return DaytimeBucket.morning;
    if (h >= 10 && h < 14) return DaytimeBucket.midday;
    if (h >= 14 && h < 18) return DaytimeBucket.afternoon;
    if (h >= 18 && h < 22) return DaytimeBucket.evening;
    return DaytimeBucket.night;
  }
}

/// Filterkonfiguration für die Spot-Heatmap. Leere Sets bedeuten "alle".
class HeatmapFilter {
  final Set<FishSpecies> species;
  final Set<Season> seasons;
  final Set<DaytimeBucket> daytimes;
  final int? lastDays; // null = unbegrenzt

  const HeatmapFilter({
    this.species = const {},
    this.seasons = const {},
    this.daytimes = const {},
    this.lastDays,
  });

  bool get isActive =>
      species.isNotEmpty ||
      seasons.isNotEmpty ||
      daytimes.isNotEmpty ||
      lastDays != null;

  HeatmapFilter copyWith({
    Set<FishSpecies>? species,
    Set<Season>? seasons,
    Set<DaytimeBucket>? daytimes,
    int? lastDays,
    bool clearLastDays = false,
  }) {
    return HeatmapFilter(
      species: species ?? this.species,
      seasons: seasons ?? this.seasons,
      daytimes: daytimes ?? this.daytimes,
      lastDays: clearLastDays ? null : (lastDays ?? this.lastDays),
    );
  }

  bool matches(CatchEntry c, {DateTime? now}) {
    if (species.isNotEmpty && !species.contains(c.species)) return false;
    if (seasons.isNotEmpty && !seasons.contains(_seasonOf(c.caughtAt))) {
      return false;
    }
    if (daytimes.isNotEmpty &&
        !daytimes.contains(DaytimeBucket.of(c.caughtAt))) {
      return false;
    }
    if (lastDays != null) {
      final ref = now ?? DateTime.now();
      final cutoff = ref.subtract(Duration(days: lastDays!));
      if (c.caughtAt.isBefore(cutoff)) return false;
    }
    return true;
  }
}

Season _seasonOf(DateTime d) {
  final m = d.month;
  if (m >= 3 && m <= 5) return Season.spring;
  if (m >= 6 && m <= 8) return Season.summer;
  if (m >= 9 && m <= 11) return Season.autumn;
  return Season.winter;
}

/// Eine Heatmap-Zelle (gerasterte Geo-Region) mit aggregiertem Score.
class HeatmapCell {
  final LatLng center;
  final int catchCount;
  final double avgLengthCm;
  final int totalWeightG;

  /// Normalisierter Score 0..1 (relativ zur stärksten Zelle in dieser Map).
  final double score;

  /// Roher Score-Wert (vor Normalisierung) — nützlich für Tooltips.
  final double rawScore;

  final List<CatchEntry> catches;

  const HeatmapCell({
    required this.center,
    required this.catchCount,
    required this.avgLengthCm,
    required this.totalWeightG,
    required this.score,
    required this.rawScore,
    required this.catches,
  });

  /// Dominante Art in dieser Zelle (höchste Anzahl).
  FishSpecies get dominantSpecies {
    final counts = <FishSpecies, int>{};
    for (final c in catches) {
      counts[c.species] = (counts[c.species] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

/// Ergebnis einer Heatmap-Berechnung.
class SpotHeatmap {
  final List<HeatmapCell> cells;
  final int totalCatches; // gefiltert + verortet
  final int withoutLocation; // konnten nicht verortet werden
  final double maxRawScore;

  const SpotHeatmap({
    required this.cells,
    required this.totalCatches,
    required this.withoutLocation,
    required this.maxRawScore,
  });

  static const empty = SpotHeatmap(
    cells: [],
    totalCatches: 0,
    withoutLocation: 0,
    maxRawScore: 0,
  );

  bool get isEmpty => cells.isEmpty;
}

/// Berechnet eine rasterisierte Heatmap aus Fängen.
///
/// `gridSizeMeters` definiert die Kantenlänge der Zellen (default ~120 m,
/// passt für Ufer-/Bootsangelei). Score = catchCount × (1 + avgLen/100), so dass
/// größere Fische stärker gewichten.
SpotHeatmap computeSpotHeatmap({
  required List<CatchEntry> catches,
  required List<FishingSpot> spots,
  HeatmapFilter filter = const HeatmapFilter(),
  double gridSizeMeters = 120,
  DateTime? now,
}) {
  if (catches.isEmpty) return SpotHeatmap.empty;

  // Spot-Lookup für Catches ohne eigene Koordinaten.
  final spotById = <String, FishingSpot>{for (final s in spots) s.id: s};

  final binMembers = <_CellKey, List<CatchEntry>>{};
  final binCenters = <_CellKey, LatLng>{};

  int withoutLocation = 0;
  int matched = 0;

  final latStep = gridSizeMeters / 111000.0;

  for (final c in catches) {
    final ll = _resolveLatLng(c, spotById);
    if (ll == null) {
      withoutLocation++;
      continue;
    }
    if (!filter.matches(c, now: now)) continue;
    matched++;

    final lngStep =
        gridSizeMeters /
        (111000.0 *
            math.cos(ll.latitude * math.pi / 180).abs().clamp(0.01, 1.0));
    final i = (ll.latitude / latStep).floor();
    final j = (ll.longitude / lngStep).floor();
    final key = _CellKey(i, j);
    binMembers.putIfAbsent(key, () => []).add(c);
    binCenters.putIfAbsent(
      key,
      () => LatLng((i + 0.5) * latStep, (j + 0.5) * lngStep),
    );
  }

  if (binMembers.isEmpty) {
    return SpotHeatmap(
      cells: const [],
      totalCatches: 0,
      withoutLocation: withoutLocation,
      maxRawScore: 0,
    );
  }

  // Raw-Scores berechnen.
  final raw = <_RawCell>[];
  double maxScore = 0;
  for (final entry in binMembers.entries) {
    final list = entry.value;
    final lengths = list
        .where((c) => c.lengthCm != null)
        .map((c) => c.lengthCm!)
        .toList();
    final weights = list
        .where((c) => c.weightG != null)
        .map((c) => c.weightG!)
        .fold<int>(0, (a, b) => a + b);
    final avgLen = lengths.isEmpty
        ? 0.0
        : lengths.reduce((a, b) => a + b) / lengths.length;
    final score = list.length * (1 + avgLen / 100);
    if (score > maxScore) maxScore = score;
    raw.add(
      _RawCell(
        center: binCenters[entry.key]!,
        count: list.length,
        avgLen: avgLen,
        totalWeight: weights,
        score: score,
        catches: list,
      ),
    );
  }

  final cells =
      raw
          .map(
            (r) => HeatmapCell(
              center: r.center,
              catchCount: r.count,
              avgLengthCm: r.avgLen,
              totalWeightG: r.totalWeight,
              score: maxScore == 0 ? 0 : r.score / maxScore,
              rawScore: r.score,
              catches: r.catches,
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.score.compareTo(b.score),
        ); // schwache Zellen unten zeichnen

  return SpotHeatmap(
    cells: cells,
    totalCatches: matched,
    withoutLocation: withoutLocation,
    maxRawScore: maxScore,
  );
}

LatLng? _resolveLatLng(CatchEntry c, Map<String, FishingSpot> spotById) {
  if (c.lat != null && c.lng != null) {
    return LatLng(c.lat!, c.lng!);
  }
  final sid = c.spotId;
  if (sid != null) {
    final s = spotById[sid];
    if (s != null) return LatLng(s.lat, s.lng);
  }
  return null;
}

class _CellKey {
  final int i;
  final int j;
  const _CellKey(this.i, this.j);

  @override
  bool operator ==(Object other) =>
      other is _CellKey && other.i == i && other.j == j;

  @override
  int get hashCode => Object.hash(i, j);
}

class _RawCell {
  final LatLng center;
  final int count;
  final double avgLen;
  final int totalWeight;
  final double score;
  final List<CatchEntry> catches;
  const _RawCell({
    required this.center,
    required this.count,
    required this.avgLen,
    required this.totalWeight,
    required this.score,
    required this.catches,
  });
}
