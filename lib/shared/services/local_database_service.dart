import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/catch_entry.dart';
import '../models/fishing_spot.dart';
import '../models/mission.dart';
import '../models/trip.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'apex.db'),
      version: 5,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTripTables(db);
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE trips ADD COLUMN cloud_trip_id TEXT');
        }
        if (oldVersion < 4) {
          await _createWaterDaysTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE catches ADD COLUMN is_shared INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE catches ADD COLUMN share_water INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE catches (
            id TEXT PRIMARY KEY,
            species TEXT NOT NULL,
            weight_g INTEGER,
            length_cm REAL,
            lat REAL,
            lng REAL,
            depth_m REAL,
            lure TEXT,
            lure_color TEXT,
            retrieve_style TEXT,
            water_temp_c REAL,
            air_temp_c REAL,
            weather_desc TEXT,
            photo_path TEXT,
            notes TEXT,
            spot_id TEXT,
            caught_at TEXT NOT NULL,
            drill_duration_sec INTEGER,
            is_shared INTEGER NOT NULL DEFAULT 0,
            share_water INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE spots (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            water_body_name TEXT,
            depth_m REAL,
            structures TEXT,
            notes TEXT,
            photo_path TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE season_notes (
            id TEXT PRIMARY KEY,
            spot_id TEXT NOT NULL,
            season TEXT NOT NULL,
            depth_note TEXT,
            tactic_note TEXT,
            FOREIGN KEY (spot_id) REFERENCES spots(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE missions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            emoji TEXT NOT NULL,
            type TEXT NOT NULL,
            points_reward INTEGER NOT NULL,
            status TEXT NOT NULL,
            progress INTEGER NOT NULL DEFAULT 0,
            goal INTEGER NOT NULL,
            completed_at TEXT,
            expires_at TEXT
          )
        ''');

        await _createTripTables(db);
        await _createWaterDaysTable(db);
      },
    );
  }

  Future<void> _createWaterDaysTable(Database db) async {
    await db.execute('''
      CREATE TABLE water_days (
        date TEXT PRIMARY KEY,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createTripTables(Database db) async {
    await db.execute('''
      CREATE TABLE trips (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        date TEXT NOT NULL,
        water_body_name TEXT,
        center_lat REAL NOT NULL,
        center_lng REAL NOT NULL,
        notes TEXT,
        checklist TEXT,
        created_at TEXT NOT NULL,
        cloud_trip_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE trip_stops (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        name TEXT NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        spot_id TEXT,
        order_index INTEGER NOT NULL,
        notes TEXT,
        FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
      )
    ''');
  }

  // ─── Catches ─────────────────────────────────────────────────────────────

  Future<List<CatchEntry>> getCatches() async {
    final db = await database;
    final rows = await db.query('catches', orderBy: 'caught_at DESC');
    return rows.map(CatchEntry.fromMap).toList();
  }

  Future<void> insertCatch(CatchEntry entry) async {
    final db = await database;
    await db.insert(
      'catches',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCatch(CatchEntry entry) async {
    final db = await database;
    await db.update(
      'catches',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteCatch(String id) async {
    final db = await database;
    await db.delete('catches', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Spots ────────────────────────────────────────────────────────────────

  Future<List<FishingSpot>> getSpots() async {
    final db = await database;
    final rows = await db.query('spots', orderBy: 'created_at DESC');
    final List<FishingSpot> spots = [];
    for (final row in rows) {
      final notes = await _getSeasonNotes(row['id'] as String);
      spots.add(FishingSpot.fromMap(row, seasonNotes: notes));
    }
    return spots;
  }

  Future<FishingSpot?> getSpot(String id) async {
    final db = await database;
    final rows = await db.query('spots', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final notes = await _getSeasonNotes(id);
    return FishingSpot.fromMap(rows.first, seasonNotes: notes);
  }

  Future<void> insertSpot(FishingSpot spot) async {
    final db = await database;
    await db.insert(
      'spots',
      spot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (final sn in spot.seasonNotes) {
      await db.insert(
        'season_notes',
        sn.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> updateSpot(FishingSpot spot) async {
    final db = await database;
    await db.update(
      'spots',
      spot.toMap(),
      where: 'id = ?',
      whereArgs: [spot.id],
    );
    await db.delete('season_notes', where: 'spot_id = ?', whereArgs: [spot.id]);
    for (final sn in spot.seasonNotes) {
      await db.insert(
        'season_notes',
        sn.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> deleteSpot(String id) async {
    final db = await database;
    await db.delete('spots', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SeasonNote>> _getSeasonNotes(String spotId) async {
    final db = await database;
    final rows = await db.query(
      'season_notes',
      where: 'spot_id = ?',
      whereArgs: [spotId],
    );
    return rows.map(SeasonNote.fromMap).toList();
  }

  // ─── Missions ─────────────────────────────────────────────────────────────

  Future<List<Mission>> getMissions() async {
    final db = await database;
    final rows = await db.query('missions');
    return rows.map(Mission.fromMap).toList();
  }

  Future<void> seedMissions() async {
    final db = await database;
    // Nur fehlende Missionen einspielen — so werden neue Seeds auch bei
    // bestehenden Nutzern ergänzt, ohne vorhandenen Fortschritt zu überschreiben.
    final existing = await db.query('missions', columns: ['id']);
    final existingIds = existing.map((r) => r['id'] as String).toSet();
    final batch = db.batch();
    for (final m in MissionSeed.defaultMissions()) {
      if (existingIds.contains(m.id)) continue;
      batch.insert(
        'missions',
        m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateMission(Mission mission) async {
    final db = await database;
    await db.update(
      'missions',
      mission.toMap(),
      where: 'id = ?',
      whereArgs: [mission.id],
    );
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  Future<Map<String, int>> getCatchCountPerSpecies() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT species, COUNT(*) as count FROM catches GROUP BY species',
    );
    return {for (final r in rows) r['species'] as String: r['count'] as int};
  }

  Future<List<Map<String, dynamic>>> getMonthlyCatchCounts() async {
    final db = await database;
    return db.rawQuery(
      "SELECT strftime('%Y-%m', caught_at) as month, COUNT(*) as count "
      "FROM catches GROUP BY month ORDER BY month DESC LIMIT 12",
    );
  }

  Future<Map<String, int>> getTopLures({int limit = 5}) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT lure, COUNT(*) as count FROM catches WHERE lure IS NOT NULL '
      'GROUP BY lure ORDER BY count DESC LIMIT ?',
      [limit],
    );
    return {for (final r in rows) r['lure'] as String: r['count'] as int};
  }

  // ─── Trips ────────────────────────────────────────────────────────────────

  Future<List<Trip>> getTrips() async {
    final db = await database;
    final rows = await db.query('trips', orderBy: 'date ASC');
    final List<Trip> trips = [];
    for (final row in rows) {
      final stops = await _getTripStops(row['id'] as String);
      trips.add(Trip.fromMap(row, stops: stops));
    }
    return trips;
  }

  Future<List<TripStop>> _getTripStops(String tripId) async {
    final db = await database;
    final rows = await db.query(
      'trip_stops',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'order_index ASC',
    );
    return rows.map(TripStop.fromMap).toList();
  }

  Future<void> insertTrip(Trip trip) async {
    final db = await database;
    await db.insert(
      'trips',
      trip.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (final s in trip.stops) {
      await db.insert(
        'trip_stops',
        s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> updateTrip(Trip trip) async {
    final db = await database;
    await db.update(
      'trips',
      trip.toMap(),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
    await db.delete('trip_stops', where: 'trip_id = ?', whereArgs: [trip.id]);
    for (final s in trip.stops) {
      await db.insert(
        'trip_stops',
        s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> deleteTrip(String id) async {
    final db = await database;
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Water Days (manuelle Einträge) ──────────────────────────────────────

  /// Liefert alle manuell markierten Tage als ISO-Strings (YYYY-MM-DD).
  Future<List<String>> getManualWaterDays() async {
    final db = await database;
    final rows = await db.query('water_days', orderBy: 'date DESC');
    return rows.map((r) => r['date'] as String).toList();
  }

  Future<void> insertWaterDay(String dateIso, {String? note}) async {
    final db = await database;
    await db.insert('water_days', {
      'date': dateIso,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> deleteWaterDay(String dateIso) async {
    final db = await database;
    await db.delete('water_days', where: 'date = ?', whereArgs: [dateIso]);
  }
}
