/// Trip-Planer Modelle.
///
/// Ein [Trip] ist ein geplanter Angel-Ausflug auf ein bestimmtes Datum und an
/// ein bestimmtes Gewässer. Er enthält eine geordnete Liste von [TripStop]s
/// (Spots, die man auf dem Trip abfahren möchte) sowie optional eine
/// Packliste und Notizen.
library;

import '../../core/format/app_formats.dart';

class Trip {
  final String id;
  final String name;
  final DateTime date;
  final String? waterBodyName;
  final double centerLat;
  final double centerLng;
  final String? notes;
  final List<String> checklist;
  final DateTime createdAt;
  final List<TripStop> stops;

  /// Wenn gesetzt: Dieser Trip ist mit einem Firestore-Dokument
  /// (`/sharedTrips/{cloudTripId}`) verknüpft. Änderungen werden bei
  /// jedem Save in die Cloud gepusht; beim Öffnen der Trip-Seite oder
  /// per Pull-Down aktualisiert.
  final String? cloudTripId;

  const Trip({
    required this.id,
    required this.name,
    required this.date,
    this.waterBodyName,
    required this.centerLat,
    required this.centerLng,
    this.notes,
    this.checklist = const [],
    required this.createdAt,
    this.stops = const [],
    this.cloudTripId,
  });

  bool get isUpcoming {
    final today = DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day);
    final tripDay = DateTime(date.year, date.month, date.day);
    return !tripDay.isBefore(cutoff);
  }

  int get daysUntil {
    final today = DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day);
    final tripDay = DateTime(date.year, date.month, date.day);
    return tripDay.difference(cutoff).inDays;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'water_body_name': waterBodyName,
    'center_lat': centerLat,
    'center_lng': centerLng,
    'notes': notes,
    'checklist': checklist.join('\u0001'),
    'created_at': createdAt.toIso8601String(),
    'cloud_trip_id': cloudTripId,
  };

  factory Trip.fromMap(
    Map<String, dynamic> map, {
    List<TripStop> stops = const [],
  }) {
    final raw = map['checklist'] as String?;
    final items = (raw == null || raw.isEmpty)
        ? const <String>[]
        : raw.split('\u0001').where((e) => e.isNotEmpty).toList();
    return Trip(
      id: map['id'] as String,
      name: map['name'] as String,
      date: DateTime.parse(map['date'] as String),
      waterBodyName: map['water_body_name'] as String?,
      centerLat: (map['center_lat'] as num).toDouble(),
      centerLng: (map['center_lng'] as num).toDouble(),
      notes: map['notes'] as String?,
      checklist: items,
      createdAt: DateTime.parse(map['created_at'] as String),
      stops: stops,
      cloudTripId: map['cloud_trip_id'] as String?,
    );
  }

  Trip copyWith({
    String? id,
    String? name,
    DateTime? date,
    String? waterBodyName,
    double? centerLat,
    double? centerLng,
    String? notes,
    List<String>? checklist,
    DateTime? createdAt,
    List<TripStop>? stops,
    String? cloudTripId,
    bool clearCloudTripId = false,
  }) => Trip(
    id: id ?? this.id,
    name: name ?? this.name,
    date: date ?? this.date,
    waterBodyName: waterBodyName ?? this.waterBodyName,
    centerLat: centerLat ?? this.centerLat,
    centerLng: centerLng ?? this.centerLng,
    notes: notes ?? this.notes,
    checklist: checklist ?? this.checklist,
    createdAt: createdAt ?? this.createdAt,
    stops: stops ?? this.stops,
    cloudTripId: clearCloudTripId ? null : (cloudTripId ?? this.cloudTripId),
  );
}

class TripStop {
  final String id;
  final String tripId;
  final String name;
  final double lat;
  final double lng;
  final String? spotId;
  final int orderIndex;
  final String? notes;

  const TripStop({
    required this.id,
    required this.tripId,
    required this.name,
    required this.lat,
    required this.lng,
    this.spotId,
    required this.orderIndex,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'trip_id': tripId,
    'name': name,
    'lat': lat,
    'lng': lng,
    'spot_id': spotId,
    'order_index': orderIndex,
    'notes': notes,
  };

  factory TripStop.fromMap(Map<String, dynamic> map) => TripStop(
    id: map['id'] as String,
    tripId: map['trip_id'] as String,
    name: map['name'] as String,
    lat: (map['lat'] as num).toDouble(),
    lng: (map['lng'] as num).toDouble(),
    spotId: map['spot_id'] as String?,
    orderIndex: map['order_index'] as int,
    notes: map['notes'] as String?,
  );

  TripStop copyWith({
    String? id,
    String? tripId,
    String? name,
    double? lat,
    double? lng,
    String? spotId,
    int? orderIndex,
    String? notes,
  }) => TripStop(
    id: id ?? this.id,
    tripId: tripId ?? this.tripId,
    name: name ?? this.name,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    spotId: spotId ?? this.spotId,
    orderIndex: orderIndex ?? this.orderIndex,
    notes: notes ?? this.notes,
  );
}

/// Tageswetter-Vorhersage für einen geplanten Trip.
class DailyForecast {
  final DateTime date;
  final double? tempMinC;
  final double? tempMaxC;
  final double? precipitationSumMm;
  final double? precipitationProbabilityMaxPct;
  final double? windSpeedMaxKmh;
  final double? windDirectionDominantDeg;
  final int? weatherCode;
  final DateTime? sunrise;
  final DateTime? sunset;
  final double? pressureHpaMean;

  /// Druckänderung über den Tag (Ende – Anfang in hPa).
  final double? pressureTrendHpa24h;

  const DailyForecast({
    required this.date,
    this.tempMinC,
    this.tempMaxC,
    this.precipitationSumMm,
    this.precipitationProbabilityMaxPct,
    this.windSpeedMaxKmh,
    this.windDirectionDominantDeg,
    this.weatherCode,
    this.sunrise,
    this.sunset,
    this.pressureHpaMean,
    this.pressureTrendHpa24h,
  });

  String get conditionLabel {
    final code = weatherCode;
    if (code == null) return 'Unbekannt';
    if (code == 0) return 'Klar';
    if (code == 1) return 'Heiter';
    if (code == 2) return 'Leicht bewölkt';
    if (code == 3) return 'Bedeckt';
    if (code <= 49) return 'Nebel';
    if (code <= 69) return 'Regen';
    if (code <= 79) return 'Schnee';
    if (code <= 99) return 'Gewitter';
    return 'Unbekannt';
  }

  String get conditionEmoji {
    final code = weatherCode;
    if (code == null) return '❓';
    if (code == 0) return '☀️';
    if (code == 1) return '🌤';
    if (code == 2) return '⛅';
    if (code == 3) return '☁️';
    if (code <= 49) return '🌫';
    if (code <= 69) return '🌧';
    if (code <= 79) return '❄️';
    if (code <= 99) return '⛈';
    return '❓';
  }

  String get windDirectionLabel {
    final deg = windDirectionDominantDeg;
    if (deg == null) return '–';
    const dirs = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    return dirs[((deg + 22.5) / 45).floor() % 8];
  }

  /// Drucktendenz als Kurztext (Schwellen grob für 24-h-Differenz).
  String get pressureTrendLabel =>
      PressureTrend.label(pressureTrendHpa24h, t: PressureTrend.twentyFourHour);

  /// Drucktendenz als Pfeil.
  String get pressureTrendArrow =>
      PressureTrend.arrow(pressureTrendHpa24h, t: PressureTrend.twentyFourHour);
}
