/// Angelbilanz — reine Daten-Berechnung ohne Flutter-Abhängigkeiten.
///
/// Aus einer Liste von [CatchEntry]s wird ein [RevierStats]-Objekt berechnet,
/// das alle Kennzahlen für die Karten enthält.
library;

import 'dart:math' as math;
import '../../shared/models/catch_entry.dart';

enum RevierPeriod { month, year }

/// Eine einzelne Statistik-Karte, die auf dem Screen gezeigt wird.
/// [type] identifiziert den Karten-Typ (für das Widget-Mapping).
class RevierCard {
  const RevierCard(this.type, this.data);
  final RevierCardType type;
  final Map<String, dynamic> data;
}

enum RevierCardType {
  /// "Du hast X Fische gefangen" — Opener-Karte
  catchCount,

  /// Gesamtgewicht aller Fische
  totalWeight,

  /// Lieblingsart mit Fischbild
  topSpecies,

  /// Schwerster Einzelfang
  biggestCatch,

  /// Längster Einzelfang
  longestCatch,

  /// Aktivster Wochentag
  bestWeekday,

  /// Beste Tageszeit (Morgens/Mittags/Abends/Nachts)
  bestDaytime,

  /// Meistgenutzter Köder
  topLure,

  /// Beliebteste Abruftechnik
  topRetrieve,

  /// Spot mit den meisten Fängen
  topSpot,

  /// Angeltag-Streak
  streak,

  /// Durchschnittliche Drill-Dauer
  avgDrill,

  /// Kälteste / wärmste Wassertemperatur
  tempRange,

  /// Vergleich: Diese Periode vs. Vorperiode
  comparison,
}

class RevierStats {
  const RevierStats({
    required this.period,
    required this.label,
    required this.catches,
    required this.cards,
  });

  final RevierPeriod period;

  /// z. B. "Mai 2026" oder "2026"
  final String label;

  /// Alle Fänge im Zeitraum
  final List<CatchEntry> catches;

  /// Die zufällig ausgewählten Karten (6–10 Stück)
  final List<RevierCard> cards;

  bool get isEmpty => catches.isEmpty;

  /// Berechnet [RevierStats] für den gewählten Zeitraum.
  /// [seed] steuert die Zufallsauswahl — gleicher Seed = gleiche Karten.
  factory RevierStats.compute({
    required List<CatchEntry> all,
    required RevierPeriod period,
    required DateTime reference, // Monat/Jahr, für den die Bilanz gilt
    int? seed,
  }) {
    // 1) Fänge filtern
    final catches = all.where((c) {
      if (period == RevierPeriod.month) {
        return c.caughtAt.year == reference.year &&
            c.caughtAt.month == reference.month;
      } else {
        return c.caughtAt.year == reference.year;
      }
    }).toList()..sort((a, b) => a.caughtAt.compareTo(b.caughtAt));

    // Vorperiode für Vergleich
    final prevRef = period == RevierPeriod.month
        ? DateTime(reference.year, reference.month - 1)
        : DateTime(reference.year - 1);
    final prevCatches = all.where((c) {
      if (period == RevierPeriod.month) {
        return c.caughtAt.year == prevRef.year &&
            c.caughtAt.month == prevRef.month;
      } else {
        return c.caughtAt.year == prevRef.year;
      }
    }).length;

    final label = period == RevierPeriod.month
        ? _monthName(reference.month, reference.year)
        : '${reference.year}';

    if (catches.isEmpty) {
      return RevierStats(
        period: period,
        label: label,
        catches: const [],
        cards: const [],
      );
    }

    // 2) Alle möglichen Karten berechnen
    final pool = <RevierCard>[];

    // --- catchCount: immer dabei ---
    pool.add(
      RevierCard(RevierCardType.catchCount, {
        'count': catches.length,
        'prev': prevCatches,
      }),
    );

    // --- totalWeight ---
    final withWeight = catches.where((c) => c.weightG != null).toList();
    if (withWeight.length >= 3) {
      final totalG = withWeight.fold<int>(0, (s, c) => s + c.weightG!);
      pool.add(
        RevierCard(RevierCardType.totalWeight, {
          'totalG': totalG,
          'count': withWeight.length,
        }),
      );
    }

    // --- topSpecies ---
    final speciesCount = <FishSpecies, int>{};
    for (final c in catches) {
      speciesCount[c.species] = (speciesCount[c.species] ?? 0) + 1;
    }
    final topSpeciesEntry = speciesCount.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    pool.add(
      RevierCard(RevierCardType.topSpecies, {
        'species': topSpeciesEntry.key,
        'count': topSpeciesEntry.value,
        'total': catches.length,
      }),
    );

    // --- biggestCatch ---
    final withW = catches.where((c) => c.weightG != null).toList();
    if (withW.isNotEmpty) {
      final biggest = withW.reduce((a, b) => a.weightG! >= b.weightG! ? a : b);
      pool.add(
        RevierCard(RevierCardType.biggestCatch, {
          'entry': biggest,
          'weightG': biggest.weightG!,
        }),
      );
    }

    // --- longestCatch ---
    final withL = catches.where((c) => c.lengthCm != null).toList();
    if (withL.isNotEmpty) {
      final longest = withL.reduce(
        (a, b) => a.lengthCm! >= b.lengthCm! ? a : b,
      );
      pool.add(
        RevierCard(RevierCardType.longestCatch, {
          'entry': longest,
          'lengthCm': longest.lengthCm!,
        }),
      );
    }

    // --- bestWeekday ---
    if (catches.length >= 5) {
      final weekdayCounts = List<int>.filled(7, 0);
      for (final c in catches) {
        weekdayCounts[c.caughtAt.weekday - 1]++;
      }
      final maxCount = weekdayCounts.reduce(math.max);
      final bestWd = weekdayCounts.indexOf(maxCount) + 1; // 1=Mo
      pool.add(
        RevierCard(RevierCardType.bestWeekday, {
          'weekday': bestWd,
          'count': maxCount,
          'counts': weekdayCounts,
        }),
      );
    }

    // --- bestDaytime ---
    if (catches.length >= 4) {
      final slots = <String, int>{
        'Morgens (5–10 Uhr)': 0,
        'Vormittags (10–13 Uhr)': 0,
        'Mittags (13–16 Uhr)': 0,
        'Abends (16–21 Uhr)': 0,
        'Nachts (21–5 Uhr)': 0,
      };
      for (final c in catches) {
        final h = c.caughtAt.hour;
        if (h >= 5 && h < 10) {
          slots['Morgens (5–10 Uhr)'] = slots['Morgens (5–10 Uhr)']! + 1;
        } else if (h >= 10 && h < 13) {
          slots['Vormittags (10–13 Uhr)'] =
              slots['Vormittags (10–13 Uhr)']! + 1;
        } else if (h >= 13 && h < 16) {
          slots['Mittags (13–16 Uhr)'] = slots['Mittags (13–16 Uhr)']! + 1;
        } else if (h >= 16 && h < 21) {
          slots['Abends (16–21 Uhr)'] = slots['Abends (16–21 Uhr)']! + 1;
        } else {
          slots['Nachts (21–5 Uhr)'] = slots['Nachts (21–5 Uhr)']! + 1;
        }
      }
      final best = slots.entries.reduce((a, b) => a.value >= b.value ? a : b);
      pool.add(
        RevierCard(RevierCardType.bestDaytime, {
          'label': best.key,
          'count': best.value,
          'slots': slots,
        }),
      );
    }

    // --- topLure ---
    final lureCount = <String, int>{};
    for (final c in catches) {
      if (c.lure != null && c.lure!.isNotEmpty) {
        lureCount[c.lure!] = (lureCount[c.lure!] ?? 0) + 1;
      }
    }
    if (lureCount.isNotEmpty) {
      final topLure = lureCount.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      pool.add(
        RevierCard(RevierCardType.topLure, {
          'lure': topLure.key,
          'count': topLure.value,
          'total': catches.length,
        }),
      );
    }

    // --- topRetrieve ---
    final retrieveCount = <RetrieveStyle, int>{};
    for (final c in catches) {
      for (final r in c.retrieveStyles) {
        retrieveCount[r] = (retrieveCount[r] ?? 0) + 1;
      }
    }
    if (retrieveCount.isNotEmpty) {
      final topR = retrieveCount.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      pool.add(
        RevierCard(RevierCardType.topRetrieve, {
          'style': topR.key,
          'count': topR.value,
        }),
      );
    }

    // --- topSpot ---
    final spotCount = <String, int>{};
    for (final c in catches) {
      if (c.spotId != null) {
        spotCount[c.spotId!] = (spotCount[c.spotId!] ?? 0) + 1;
      }
    }
    if (spotCount.isNotEmpty) {
      final topSpot = spotCount.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      pool.add(
        RevierCard(RevierCardType.topSpot, {
          'spotId': topSpot.key,
          'count': topSpot.value,
        }),
      );
    }

    // --- streak ---
    if (catches.length >= 3) {
      final days =
          catches
              .map(
                (c) =>
                    DateTime(c.caughtAt.year, c.caughtAt.month, c.caughtAt.day),
              )
              .toSet()
              .toList()
            ..sort();
      int maxStreak = 1, cur = 1;
      for (int i = 1; i < days.length; i++) {
        if (days[i].difference(days[i - 1]).inDays == 1) {
          cur++;
          if (cur > maxStreak) maxStreak = cur;
        } else {
          cur = 1;
        }
      }
      if (maxStreak >= 2) {
        pool.add(
          RevierCard(RevierCardType.streak, {
            'days': maxStreak,
            'totalDays': days.length,
          }),
        );
      }
    }

    // --- avgDrill ---
    final withDrill = catches.where((c) => c.drillDurationSec != null).toList();
    if (withDrill.length >= 3) {
      final avg =
          withDrill.fold<int>(0, (s, c) => s + c.drillDurationSec!) ~/
          withDrill.length;
      pool.add(
        RevierCard(RevierCardType.avgDrill, {
          'avgSec': avg,
          'count': withDrill.length,
        }),
      );
    }

    // --- tempRange ---
    final withTemp = catches.where((c) => c.waterTempC != null).toList();
    if (withTemp.length >= 3) {
      final min = withTemp
          .map((c) => c.waterTempC!)
          .reduce((a, b) => a < b ? a : b);
      final max = withTemp
          .map((c) => c.waterTempC!)
          .reduce((a, b) => a > b ? a : b);
      if (max - min >= 2) {
        pool.add(
          RevierCard(RevierCardType.tempRange, {'minC': min, 'maxC': max}),
        );
      }
    }

    // --- comparison ---
    if (prevCatches > 0 || catches.isNotEmpty) {
      pool.add(
        RevierCard(RevierCardType.comparison, {
          'current': catches.length,
          'prev': prevCatches,
          'periodLabel': period == RevierPeriod.month
              ? _monthName(prevRef.month, prevRef.year)
              : '${prevRef.year}',
        }),
      );
    }

    // 3) Zufällig auswählen
    // catchCount ist immer erste Karte, topSpecies immer zweite wenn vorhanden.
    // Rest wird gemischt.
    final rng = math.Random(seed ?? DateTime.now().millisecondsSinceEpoch);
    final fixed = pool
        .where(
          (c) =>
              c.type == RevierCardType.catchCount ||
              c.type == RevierCardType.topSpecies,
        )
        .toList();
    final optional =
        pool
            .where(
              (c) =>
                  c.type != RevierCardType.catchCount &&
                  c.type != RevierCardType.topSpecies,
            )
            .toList()
          ..shuffle(rng);

    // 4–8 optionale Karten (je nach Datenlage)
    final maxOptional = math.min(optional.length, 7);
    final minOptional = math.min(optional.length, 3);
    final count =
        minOptional +
        (maxOptional > minOptional
            ? rng.nextInt(maxOptional - minOptional + 1)
            : 0);
    final selected = [...fixed, ...optional.take(count)];

    // Comparison ans Ende
    final comparison = selected
        .where((c) => c.type == RevierCardType.comparison)
        .toList();
    final rest = selected
        .where((c) => c.type != RevierCardType.comparison)
        .toList();
    final finalCards = [...rest, ...comparison];

    return RevierStats(
      period: period,
      label: label,
      catches: catches,
      cards: finalCards,
    );
  }

  static String _monthName(int month, int year) {
    const names = [
      '',
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];
    return '${names[month]} $year';
  }
}
