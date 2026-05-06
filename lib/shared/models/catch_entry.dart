enum FishSpecies {
  hecht,
  zander,
  barsch,
  wels,
  forelle,
  huchen,
  aal,
  andere;

  String get displayName {
    switch (this) {
      case FishSpecies.hecht:
        return 'Hecht';
      case FishSpecies.zander:
        return 'Zander';
      case FishSpecies.barsch:
        return 'Barsch';
      case FishSpecies.wels:
        return 'Wels';
      case FishSpecies.forelle:
        return 'Forelle';
      case FishSpecies.huchen:
        return 'Huchen';
      case FishSpecies.aal:
        return 'Aal';
      case FishSpecies.andere:
        return 'Andere';
    }
  }

  String get emoji {
    switch (this) {
      case FishSpecies.hecht:
        return '🏆';
      case FishSpecies.zander:
        return '🎯';
      case FishSpecies.barsch:
        return '🟠';
      case FishSpecies.wels:
        return '🌊';
      case FishSpecies.forelle:
        return '❄️';
      case FishSpecies.huchen:
        return '⚔️';
      case FishSpecies.aal:
        return '🌀';
      case FishSpecies.andere:
        return '•';
    }
  }

  /// Pfad zum Lexikon-Bild der Art (oder null für [FishSpecies.andere]).
  /// Wird als Fallback verwendet, wenn ein Catch-Eintrag kein eigenes Foto hat.
  String? get imageAsset {
    switch (this) {
      case FishSpecies.hecht:
        return 'assets/fische/hecht.png';
      case FishSpecies.zander:
        return 'assets/fische/zander.png';
      case FishSpecies.barsch:
        return 'assets/fische/barsch.png';
      case FishSpecies.wels:
        return 'assets/fische/wels.png';
      case FishSpecies.forelle:
        return 'assets/fische/forelle.png';
      case FishSpecies.huchen:
        return 'assets/fische/huchen.png';
      case FishSpecies.aal:
        return 'assets/fische/aal.png';
      case FishSpecies.andere:
        return null;
    }
  }
}

enum RetrieveStyle {
  // Führungstechniken
  cranking,
  stopGo,
  speedVariation,
  faulenzen,
  jig,
  dragging,
  tumbling,
  twitch,
  jerking,
  walkTheDog,
  ripping,
  shaking,
  deadSticking,
  liftDrop,
  vertical,
  pelagic,
  // Rigs
  dropShot,
  texasRig,
  carolinaRig,
  nedRig,
  cheburashkaRig,
  freeRig,
  wackyRig,
  // Legacy (werden aus alten Einträgen weiter geparst)
  steady,
  slow,
  fast;

  String get displayName {
    switch (this) {
      case RetrieveStyle.cranking:
        return 'Einleiern';
      case RetrieveStyle.stopGo:
        return 'Stop & Go';
      case RetrieveStyle.speedVariation:
        return 'Tempowechsel';
      case RetrieveStyle.faulenzen:
        return 'Faulenzen';
      case RetrieveStyle.jig:
        return 'Klassisches Jiggen';
      case RetrieveStyle.dragging:
        return 'Schleifen';
      case RetrieveStyle.tumbling:
        return 'Übertaumeln / Zupfen';
      case RetrieveStyle.twitch:
        return 'Twitchen';
      case RetrieveStyle.jerking:
        return 'Jerken';
      case RetrieveStyle.walkTheDog:
        return 'Walk-the-Dog';
      case RetrieveStyle.ripping:
        return 'Rippen';
      case RetrieveStyle.shaking:
        return 'Shaking';
      case RetrieveStyle.deadSticking:
        return 'Dead Sticking';
      case RetrieveStyle.liftDrop:
        return 'Lift & Drop';
      case RetrieveStyle.vertical:
        return 'Vertikalangeln';
      case RetrieveStyle.pelagic:
        return 'Pelagisch';
      case RetrieveStyle.dropShot:
        return 'Drop-Shot-Rig';
      case RetrieveStyle.texasRig:
        return 'Texas-Rig';
      case RetrieveStyle.carolinaRig:
        return 'Carolina-Rig';
      case RetrieveStyle.nedRig:
        return 'Ned-Rig';
      case RetrieveStyle.cheburashkaRig:
        return 'Cheburashka-Rig';
      case RetrieveStyle.freeRig:
        return 'Free-Rig';
      case RetrieveStyle.wackyRig:
        return 'Wacky-Rig';
      case RetrieveStyle.steady:
        return 'Einleiern';
      case RetrieveStyle.slow:
        return 'Slow Roll';
      case RetrieveStyle.fast:
        return 'Fast Reel';
    }
  }
}

List<RetrieveStyle> _parseRetrieveStyles(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) {
        try {
          return RetrieveStyle.values.firstWhere((e) => e.name == s);
        } catch (_) {
          return null;
        }
      })
      .whereType<RetrieveStyle>()
      .toList();
}

class CatchEntry {
  final String id;
  final FishSpecies species;
  final int? weightG;
  final double? lengthCm;
  final double? lat;
  final double? lng;
  final double? depthM;
  final String? lure;
  final String? lureColor;
  final List<RetrieveStyle> retrieveStyles;
  final double? waterTempC;
  final double? airTempC;
  final String? weatherDesc;
  final String? photoPath;
  final String? notes;
  final String? spotId;
  final DateTime caughtAt;
  final int? drillDurationSec;

  /// In den Community-Feed teilen.
  final bool isShared;

  /// Beim Teilen auch den Gewässernamen mit aufnehmen.
  final bool shareWater;

  const CatchEntry({
    required this.id,
    required this.species,
    this.weightG,
    this.lengthCm,
    this.lat,
    this.lng,
    this.depthM,
    this.lure,
    this.lureColor,
    this.retrieveStyles = const [],
    this.waterTempC,
    this.airTempC,
    this.weatherDesc,
    this.photoPath,
    this.notes,
    this.spotId,
    required this.caughtAt,
    this.drillDurationSec,
    this.isShared = false,
    this.shareWater = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'species': species.name,
    'weight_g': weightG,
    'length_cm': lengthCm,
    'lat': lat,
    'lng': lng,
    'depth_m': depthM,
    'lure': lure,
    'lure_color': lureColor,
    'retrieve_style': retrieveStyles.isEmpty
        ? null
        : retrieveStyles.map((e) => e.name).join(','),
    'water_temp_c': waterTempC,
    'air_temp_c': airTempC,
    'weather_desc': weatherDesc,
    'photo_path': photoPath,
    'notes': notes,
    'spot_id': spotId,
    'caught_at': caughtAt.toIso8601String(),
    'drill_duration_sec': drillDurationSec,
    'is_shared': isShared ? 1 : 0,
    'share_water': shareWater ? 1 : 0,
  };

  factory CatchEntry.fromMap(Map<String, dynamic> map) => CatchEntry(
    id: map['id'] as String,
    species: FishSpecies.values.firstWhere((e) => e.name == map['species']),
    weightG: map['weight_g'] as int?,
    lengthCm: map['length_cm'] as double?,
    lat: map['lat'] as double?,
    lng: map['lng'] as double?,
    depthM: map['depth_m'] as double?,
    lure: map['lure'] as String?,
    lureColor: map['lure_color'] as String?,
    retrieveStyles: _parseRetrieveStyles(map['retrieve_style'] as String?),
    waterTempC: map['water_temp_c'] as double?,
    airTempC: map['air_temp_c'] as double?,
    weatherDesc: map['weather_desc'] as String?,
    photoPath: map['photo_path'] as String?,
    notes: map['notes'] as String?,
    spotId: map['spot_id'] as String?,
    caughtAt: DateTime.parse(map['caught_at'] as String),
    drillDurationSec: map['drill_duration_sec'] as int?,
    isShared: (map['is_shared'] as int? ?? 0) == 1,
    shareWater: (map['share_water'] as int? ?? 0) == 1,
  );

  CatchEntry copyWith({
    String? id,
    FishSpecies? species,
    int? weightG,
    double? lengthCm,
    double? lat,
    double? lng,
    double? depthM,
    String? lure,
    String? lureColor,
    List<RetrieveStyle>? retrieveStyles,
    double? waterTempC,
    double? airTempC,
    String? weatherDesc,
    String? photoPath,
    String? notes,
    String? spotId,
    DateTime? caughtAt,
    int? drillDurationSec,
    bool? isShared,
    bool? shareWater,
  }) => CatchEntry(
    id: id ?? this.id,
    species: species ?? this.species,
    weightG: weightG ?? this.weightG,
    lengthCm: lengthCm ?? this.lengthCm,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    depthM: depthM ?? this.depthM,
    lure: lure ?? this.lure,
    lureColor: lureColor ?? this.lureColor,
    retrieveStyles: retrieveStyles ?? this.retrieveStyles,
    waterTempC: waterTempC ?? this.waterTempC,
    airTempC: airTempC ?? this.airTempC,
    weatherDesc: weatherDesc ?? this.weatherDesc,
    photoPath: photoPath ?? this.photoPath,
    notes: notes ?? this.notes,
    spotId: spotId ?? this.spotId,
    caughtAt: caughtAt ?? this.caughtAt,
    drillDurationSec: drillDurationSec ?? this.drillDurationSec,
    isShared: isShared ?? this.isShared,
    shareWater: shareWater ?? this.shareWater,
  );
}
