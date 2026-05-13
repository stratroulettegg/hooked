import 'catch_entry.dart';

/// Typ eines Gewässers.
enum WaterbodyType {
  see,
  fluss,
  kanal,
  teich,
  hafen,
  meer,
  sonstiges;

  String get displayName {
    switch (this) {
      case WaterbodyType.see:
        return 'See';
      case WaterbodyType.fluss:
        return 'Fluss';
      case WaterbodyType.kanal:
        return 'Kanal';
      case WaterbodyType.teich:
        return 'Teich';
      case WaterbodyType.hafen:
        return 'Hafen';
      case WaterbodyType.meer:
        return 'Meer / Bodden';
      case WaterbodyType.sonstiges:
        return 'Sonstiges';
    }
  }
}

/// Schonzeit / Mindestmaß für eine Fischart an einem Gewässer.
///
/// Datums-Modell: nur Monat+Tag (kein Jahr), damit die Schonzeit jedes Jahr
/// gleich gilt. `from` kann auch nach `to` liegen — dann läuft die Sperre
/// über den Jahreswechsel (z. B. Hecht 1.2.–30.4.).
class ClosedSeason {
  final String id;
  final String waterbodyId;
  final FishSpecies species;
  final int fromMonth;
  final int fromDay;
  final int toMonth;
  final int toDay;
  final double? minLengthCm;

  const ClosedSeason({
    required this.id,
    required this.waterbodyId,
    required this.species,
    required this.fromMonth,
    required this.fromDay,
    required this.toMonth,
    required this.toDay,
    this.minLengthCm,
  });

  /// Liegt das Datum innerhalb der Schonzeit?
  bool isClosedOn(DateTime date) {
    final start = DateTime(date.year, fromMonth, fromDay);
    final end = DateTime(date.year, toMonth, toDay, 23, 59, 59);
    if (!start.isAfter(end)) {
      return !date.isBefore(start) && !date.isAfter(end);
    }
    // Range über Jahreswechsel: gültig wenn ≥ start ODER ≤ end
    return !date.isBefore(start) || !date.isAfter(end);
  }

  String get rangeLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(fromDay)}.${two(fromMonth)} – ${two(toDay)}.${two(toMonth)}';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'waterbody_id': waterbodyId,
    'species': species.name,
    'from_month': fromMonth,
    'from_day': fromDay,
    'to_month': toMonth,
    'to_day': toDay,
    'min_length_cm': minLengthCm,
  };

  factory ClosedSeason.fromMap(Map<String, dynamic> map) => ClosedSeason(
    id: map['id'] as String,
    waterbodyId: map['waterbody_id'] as String,
    species: FishSpecies.values.firstWhere(
      (e) => e.name == map['species'],
      orElse: () => FishSpecies.andere,
    ),
    fromMonth: map['from_month'] as int,
    fromDay: map['from_day'] as int,
    toMonth: map['to_month'] as int,
    toDay: map['to_day'] as int,
    minLengthCm: (map['min_length_cm'] as num?)?.toDouble(),
  );

  ClosedSeason copyWith({
    String? id,
    String? waterbodyId,
    FishSpecies? species,
    int? fromMonth,
    int? fromDay,
    int? toMonth,
    int? toDay,
    double? minLengthCm,
  }) => ClosedSeason(
    id: id ?? this.id,
    waterbodyId: waterbodyId ?? this.waterbodyId,
    species: species ?? this.species,
    fromMonth: fromMonth ?? this.fromMonth,
    fromDay: fromDay ?? this.fromDay,
    toMonth: toMonth ?? this.toMonth,
    toDay: toDay ?? this.toDay,
    minLengthCm: minLengthCm ?? this.minLengthCm,
  );
}

/// Spinnfischverbot an einem Gewässer — z. B. zum Schutz von Salmoniden
/// während der Laichzeit. Datums-Modell wie [ClosedSeason]: nur Monat+Tag,
/// `from` darf nach `to` liegen (Range über Jahreswechsel).
class SpinFishingBan {
  final String id;
  final String waterbodyId;
  final int fromMonth;
  final int fromDay;
  final int toMonth;
  final int toDay;

  /// Optionale Begründung / Hinweis („Salmoniden-Schutz“, „Schonbezirk“, …).
  final String? notes;

  const SpinFishingBan({
    required this.id,
    required this.waterbodyId,
    required this.fromMonth,
    required this.fromDay,
    required this.toMonth,
    required this.toDay,
    this.notes,
  });

  bool isActiveOn(DateTime date) {
    final start = DateTime(date.year, fromMonth, fromDay);
    final end = DateTime(date.year, toMonth, toDay, 23, 59, 59);
    if (!start.isAfter(end)) {
      return !date.isBefore(start) && !date.isAfter(end);
    }
    return !date.isBefore(start) || !date.isAfter(end);
  }

  /// Ganzjähriges Verbot? (1.1. – 31.12.)
  bool get isYearRound =>
      fromMonth == 1 && fromDay == 1 && toMonth == 12 && toDay == 31;

  String get rangeLabel {
    if (isYearRound) return 'Ganzjährig';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(fromDay)}.${two(fromMonth)} – ${two(toDay)}.${two(toMonth)}';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'waterbody_id': waterbodyId,
    'from_month': fromMonth,
    'from_day': fromDay,
    'to_month': toMonth,
    'to_day': toDay,
    'notes': notes,
  };

  factory SpinFishingBan.fromMap(Map<String, dynamic> map) => SpinFishingBan(
    id: map['id'] as String,
    waterbodyId: map['waterbody_id'] as String,
    fromMonth: map['from_month'] as int,
    fromDay: map['from_day'] as int,
    toMonth: map['to_month'] as int,
    toDay: map['to_day'] as int,
    notes: map['notes'] as String?,
  );

  SpinFishingBan copyWith({
    String? id,
    String? waterbodyId,
    int? fromMonth,
    int? fromDay,
    int? toMonth,
    int? toDay,
    String? notes,
  }) => SpinFishingBan(
    id: id ?? this.id,
    waterbodyId: waterbodyId ?? this.waterbodyId,
    fromMonth: fromMonth ?? this.fromMonth,
    fromDay: fromDay ?? this.fromDay,
    toMonth: toMonth ?? this.toMonth,
    toDay: toDay ?? this.toDay,
    notes: notes ?? this.notes,
  );
}

/// Ein Gewässer (See, Fluss …) — semantisch übergeordnet zu [FishingSpot].
class Waterbody {
  final String id;
  final String name;
  final WaterbodyType type;

  /// Mittelpunkt — optional, bspw. wenn das Gewässer keine konkrete Karte
  /// braucht.
  final double? centerLat;
  final double? centerLng;

  /// Bundesland / Region — wird in Zukunft für Schonzeit-Defaults genutzt.
  final String? region;

  final String? notes;
  final String? regulationsUrl;
  final String? photoPath;

  /// Im Gewässer vorkommende / erlaubte Fischarten (User-gepflegt).
  final List<FishSpecies> allowedSpecies;

  final DateTime createdAt;

  /// Wird geladen aus separater Tabelle.
  final List<ClosedSeason> closedSeasons;

  /// Spinnfischverbote (Datums-Ranges) — ebenfalls separate Tabelle.
  final List<SpinFishingBan> spinBans;

  const Waterbody({
    required this.id,
    required this.name,
    required this.type,
    this.centerLat,
    this.centerLng,
    this.region,
    this.notes,
    this.regulationsUrl,
    this.photoPath,
    this.allowedSpecies = const [],
    required this.createdAt,
    this.closedSeasons = const [],
    this.spinBans = const [],
  });

  /// Kurz-Label „See · Bodensee" / „Fluss · Donau (BY)".
  String get subtitle {
    final parts = <String>[type.displayName];
    if (region != null && region!.trim().isNotEmpty) parts.add(region!.trim());
    return parts.join(' · ');
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type.name,
    'center_lat': centerLat,
    'center_lng': centerLng,
    'region': region,
    'notes': notes,
    'regulations_url': regulationsUrl,
    'photo_path': photoPath,
    'allowed_species': allowedSpecies.map((e) => e.name).join(','),
    'created_at': createdAt.toIso8601String(),
  };

  factory Waterbody.fromMap(
    Map<String, dynamic> map, {
    List<ClosedSeason> closedSeasons = const [],
    List<SpinFishingBan> spinBans = const [],
  }) => Waterbody(
    id: map['id'] as String,
    name: map['name'] as String,
    type: WaterbodyType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => WaterbodyType.sonstiges,
    ),
    centerLat: (map['center_lat'] as num?)?.toDouble(),
    centerLng: (map['center_lng'] as num?)?.toDouble(),
    region: map['region'] as String?,
    notes: map['notes'] as String?,
    regulationsUrl: map['regulations_url'] as String?,
    photoPath: map['photo_path'] as String?,
    allowedSpecies:
        (map['allowed_species'] as String?)
            ?.split(',')
            .where((s) => s.isNotEmpty)
            .map(
              (s) => FishSpecies.values.firstWhere(
                (e) => e.name == s,
                orElse: () => FishSpecies.andere,
              ),
            )
            .toList() ??
        const [],
    createdAt: DateTime.parse(map['created_at'] as String),
    closedSeasons: closedSeasons,
    spinBans: spinBans,
  );

  Waterbody copyWith({
    String? id,
    String? name,
    WaterbodyType? type,
    double? centerLat,
    double? centerLng,
    String? region,
    String? notes,
    String? regulationsUrl,
    String? photoPath,
    List<FishSpecies>? allowedSpecies,
    DateTime? createdAt,
    List<ClosedSeason>? closedSeasons,
    List<SpinFishingBan>? spinBans,
  }) => Waterbody(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    centerLat: centerLat ?? this.centerLat,
    centerLng: centerLng ?? this.centerLng,
    region: region ?? this.region,
    notes: notes ?? this.notes,
    regulationsUrl: regulationsUrl ?? this.regulationsUrl,
    photoPath: photoPath ?? this.photoPath,
    allowedSpecies: allowedSpecies ?? this.allowedSpecies,
    createdAt: createdAt ?? this.createdAt,
    closedSeasons: closedSeasons ?? this.closedSeasons,
    spinBans: spinBans ?? this.spinBans,
  );

  /// Hilfsfunktion: Gibt es eine aktive Schonzeit für [species] am [date]?
  ClosedSeason? closedSeasonFor(FishSpecies species, DateTime date) {
    for (final cs in closedSeasons) {
      if (cs.species == species && cs.isClosedOn(date)) return cs;
    }
    return null;
  }

  /// Hilfsfunktion: Aktives Spinnfischverbot am [date]?
  SpinFishingBan? activeSpinBanOn(DateTime date) {
    for (final b in spinBans) {
      if (b.isActiveOn(date)) return b;
    }
    return null;
  }
}
