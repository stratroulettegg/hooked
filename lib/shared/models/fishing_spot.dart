enum StructureType {
  steilhang,
  plateau,
  einlauf,
  bruecke,
  hindernis,
  vegetation,
  sandbank,
  tiefloch;

  String get displayName {
    switch (this) {
      case StructureType.steilhang: return 'Steilhang';
      case StructureType.plateau: return 'Plateau';
      case StructureType.einlauf: return 'Einlauf';
      case StructureType.bruecke: return 'Brücke';
      case StructureType.hindernis: return 'Unterwasser-Hindernis';
      case StructureType.vegetation: return 'Vegetation / Kraut';
      case StructureType.sandbank: return 'Sandbank';
      case StructureType.tiefloch: return 'Tiefloch';
    }
  }
}

class FishingSpot {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String? waterBodyName;
  final double? depthM;
  final List<StructureType> structures;
  final String? notes;
  final String? photoPath;
  final DateTime createdAt;
  final List<SeasonNote> seasonNotes;

  const FishingSpot({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.waterBodyName,
    this.depthM,
    this.structures = const [],
    this.notes,
    this.photoPath,
    required this.createdAt,
    this.seasonNotes = const [],
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lng': lng,
    'water_body_name': waterBodyName,
    'depth_m': depthM,
    'structures': structures.map((e) => e.name).join(','),
    'notes': notes,
    'photo_path': photoPath,
    'created_at': createdAt.toIso8601String(),
  };

  factory FishingSpot.fromMap(Map<String, dynamic> map, {List<SeasonNote> seasonNotes = const []}) => FishingSpot(
    id: map['id'] as String,
    name: map['name'] as String,
    lat: map['lat'] as double,
    lng: map['lng'] as double,
    waterBodyName: map['water_body_name'] as String?,
    depthM: map['depth_m'] as double?,
    structures: (map['structures'] as String?)
        ?.split(',')
        .where((s) => s.isNotEmpty)
        .map((s) => StructureType.values.firstWhere((e) => e.name == s))
        .toList() ?? [],
    notes: map['notes'] as String?,
    photoPath: map['photo_path'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    seasonNotes: seasonNotes,
  );

  FishingSpot copyWith({
    String? id,
    String? name,
    double? lat,
    double? lng,
    String? waterBodyName,
    double? depthM,
    List<StructureType>? structures,
    String? notes,
    String? photoPath,
    DateTime? createdAt,
    List<SeasonNote>? seasonNotes,
  }) => FishingSpot(
    id: id ?? this.id,
    name: name ?? this.name,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    waterBodyName: waterBodyName ?? this.waterBodyName,
    depthM: depthM ?? this.depthM,
    structures: structures ?? this.structures,
    notes: notes ?? this.notes,
    photoPath: photoPath ?? this.photoPath,
    createdAt: createdAt ?? this.createdAt,
    seasonNotes: seasonNotes ?? this.seasonNotes,
  );
}

enum Season { spring, summer, autumn, winter }

extension SeasonExt on Season {
  String get displayName {
    switch (this) {
      case Season.spring: return 'Frühling';
      case Season.summer: return 'Sommer';
      case Season.autumn: return 'Herbst';
      case Season.winter: return 'Winter';
    }
  }

  static Season current() {
    final month = DateTime.now().month;
    if (month >= 3 && month <= 5) return Season.spring;
    if (month >= 6 && month <= 8) return Season.summer;
    if (month >= 9 && month <= 11) return Season.autumn;
    return Season.winter;
  }
}

class SeasonNote {
  final String id;
  final String spotId;
  final Season season;
  final String? depthNote;
  final String? tacticNote;

  const SeasonNote({
    required this.id,
    required this.spotId,
    required this.season,
    this.depthNote,
    this.tacticNote,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'spot_id': spotId,
    'season': season.name,
    'depth_note': depthNote,
    'tactic_note': tacticNote,
  };

  factory SeasonNote.fromMap(Map<String, dynamic> map) => SeasonNote(
    id: map['id'] as String,
    spotId: map['spot_id'] as String,
    season: Season.values.firstWhere((e) => e.name == map['season']),
    depthNote: map['depth_note'] as String?,
    tacticNote: map['tactic_note'] as String?,
  );
}
