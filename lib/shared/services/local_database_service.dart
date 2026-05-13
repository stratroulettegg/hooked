import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/catch_entry.dart';
import '../models/fishing_spot.dart';
import '../models/mission.dart';
import '../models/trip.dart';
import '../models/waterbody.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._();

  Database? _db;
  String? _activeUid;

  /// Aktiver UID-Slot (Debug/Telemetry).
  String? get activeUid => _activeUid;

  /// Schaltet die SQLite-Datei auf einen UID-spezifischen Pfad
  /// `apex_<uid>.db` um. Schließt eine ggf. offene Vorgänger-DB sauber
  /// und öffnet die neue lazy beim nächsten [database]-Zugriff.
  ///
  /// Migration: Wird beim ersten Aktivieren keine `apex_<uid>.db`-Datei
  /// gefunden, aber eine Legacy-`apex.db` aus der Pre-Multi-User-Zeit,
  /// wird die Legacy-Datei einmalig in den UID-Slot umbenannt.
  Future<void> activateForUid(String uid) async {
    if (_activeUid == uid && _db != null) return;
    final old = _db;
    _db = null;
    _activeUid = uid;
    try {
      await old?.close();
    } catch (_) {
      // Alte DB war evtl. korrupt — ignorieren.
    }
    // DB wird beim nächsten Zugriff lazy geöffnet (siehe [database]).
  }

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final uid = _activeUid;
    if (uid == null) {
      throw StateError(
        'LocalDatabaseService.activateForUid(uid) must be called before '
        'opening the database (typically in main() after auth bootstrap).',
      );
    }
    final dbPath = await getDatabasesPath();
    final target = p.join(dbPath, 'apex_$uid.db');
    final legacy = p.join(dbPath, 'apex.db');
    // Einmalige Legacy-Migration: Pre-Multi-User-DB in UID-Slot umbenennen.
    // Nur für echte UIDs — in den `__noauth__`-Staging-Slot wandert die
    // Legacy-DB *nicht*, sonst müssten wir später erneut migrieren und
    // SQLite-WAL/SHM-Sidecars können einen Filesystem-Rename direkt nach
    // db.close() auf iOS in einen `SQLITE_IOERR_WRITE` reissen.
    final targetExists = await databaseExists(target);
    if (!targetExists && uid != '__noauth__') {
      final legacyExists = await databaseExists(legacy);
      if (legacyExists) {
        try {
          await File(legacy).rename(target);
        } catch (_) {
          // Cross-FS / Permission → kopieren statt verschieben, Original
          // behalten, Daten bleiben rettbar.
          try {
            await File(legacy).copy(target);
          } catch (_) {
            // Auch das schiefgegangen → leere User-DB anlegen, weiter.
          }
        }
      }
    }
    return openDatabase(
      target,
      version: 9,
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
        if (oldVersion < 6) {
          await _createWaterbodyTables(db);
          await db.execute(
            'ALTER TABLE spots ADD COLUMN waterbody_id TEXT',
          );
          await _migrateSpotsToWaterbodies(db);
        }
        if (oldVersion < 7) {
          await _createSpinBansTable(db);
        }
        if (oldVersion < 8) {
          await _addSyncColumns(db);
        }
        if (oldVersion < 9) {
          await _addMissionsSyncColumns(db);
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
            share_water INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE spots (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            waterbody_id TEXT,
            water_body_name TEXT,
            depth_m REAL,
            structures TEXT,
            notes TEXT,
            photo_path TEXT,
            created_at TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
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
            expires_at TEXT,
            updated_at INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');

        await _createTripTables(db);
        await _createWaterDaysTable(db);
        await _createWaterbodyTables(db);
        await _addSyncColumns(db);
      },
    );
  }

  /// Migration v8: Sync-Metadaten für alle user-eigenen Tabellen.
  /// updated_at = LWW-Timestamp (ms epoch), deleted_at = Tombstone (nullable).
  Future<void> _addSyncColumns(Database db) async {
    const tables = ['catches', 'spots', 'waterbodies', 'trips', 'water_days'];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final t in tables) {
      // ALTER ist idempotent abgesichert: bei Neuanlage via onCreate werden
      // diese Spalten ebenfalls hinzugefügt (kein Schaden, da Tabelle leer).
      try {
        await db.execute(
          'ALTER TABLE $t ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {/* Spalte existiert bereits (z.B. Hot-Restart) */}
      try {
        await db.execute('ALTER TABLE $t ADD COLUMN deleted_at INTEGER');
      } catch (_) {/* dito */}
      // Backfill: existierende Zeilen bekommen einen Initial-Timestamp,
      // damit der erste Cloud-Push sie als „neu“ erkennt.
      await db.execute(
        'UPDATE $t SET updated_at = ? WHERE updated_at = 0',
        [now],
      );
    }
  }

  /// Migration v9: Sync-Metadaten für `missions` (Gameification-Fortschritt).
  Future<void> _addMissionsSyncColumns(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await db.execute(
        'ALTER TABLE missions ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {/* schon vorhanden */}
    try {
      await db.execute('ALTER TABLE missions ADD COLUMN deleted_at INTEGER');
    } catch (_) {/* dito */}
    await db.execute(
      'UPDATE missions SET updated_at = ? WHERE updated_at = 0',
      [now],
    );
  }

  Future<void> _createWaterbodyTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS waterbodies (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        center_lat REAL,
        center_lng REAL,
        region TEXT,
        notes TEXT,
        regulations_url TEXT,
        photo_path TEXT,
        allowed_species TEXT,
        created_at TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS closed_seasons (
        id TEXT PRIMARY KEY,
        waterbody_id TEXT NOT NULL,
        species TEXT NOT NULL,
        from_month INTEGER NOT NULL,
        from_day INTEGER NOT NULL,
        to_month INTEGER NOT NULL,
        to_day INTEGER NOT NULL,
        min_length_cm REAL,
        FOREIGN KEY (waterbody_id) REFERENCES waterbodies(id) ON DELETE CASCADE
      )
    ''');
    await _createSpinBansTable(db);
  }

  Future<void> _createSpinBansTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS spin_fishing_bans (
        id TEXT PRIMARY KEY,
        waterbody_id TEXT NOT NULL,
        from_month INTEGER NOT NULL,
        from_day INTEGER NOT NULL,
        to_month INTEGER NOT NULL,
        to_day INTEGER NOT NULL,
        notes TEXT,
        FOREIGN KEY (waterbody_id) REFERENCES waterbodies(id) ON DELETE CASCADE
      )
    ''');
  }

  /// Migration: Für jeden Spot mit gesetztem `water_body_name` ein Waterbody
  /// anlegen und die `waterbody_id` füllen. Spots, die denselben Namen
  /// teilen (case-insensitive trimmed), bekommen denselben Waterbody.
  Future<void> _migrateSpotsToWaterbodies(Database db) async {
    final rows = await db.query(
      'spots',
      columns: ['id', 'water_body_name', 'lat', 'lng'],
      where: 'water_body_name IS NOT NULL AND TRIM(water_body_name) != \'\'',
    );
    if (rows.isEmpty) return;
    final uuid = const Uuid();
    final nameToId = <String, String>{};
    final batch = db.batch();
    for (final r in rows) {
      final raw = (r['water_body_name'] as String).trim();
      final key = raw.toLowerCase();
      var wbId = nameToId[key];
      if (wbId == null) {
        wbId = uuid.v4();
        nameToId[key] = wbId;
        batch.insert('waterbodies', {
          'id': wbId,
          'name': raw,
          'type': WaterbodyType.sonstiges.name,
          'center_lat': r['lat'],
          'center_lng': r['lng'],
          'region': null,
          'notes': null,
          'regulations_url': null,
          'photo_path': null,
          'allowed_species': '',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      batch.update(
        'spots',
        {'waterbody_id': wbId},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _createWaterDaysTable(Database db) async {
    await db.execute('''
      CREATE TABLE water_days (
        date TEXT PRIMARY KEY,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
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
        cloud_trip_id TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
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

  /// Aktueller Sync-Timestamp in Millisekunden seit Epoch.
  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<List<CatchEntry>> getCatches() async {
    final db = await database;
    final rows = await db.query(
      'catches',
      where: 'deleted_at IS NULL',
      orderBy: 'caught_at DESC',
    );
    return rows.map(CatchEntry.fromMap).toList();
  }

  Future<void> insertCatch(CatchEntry entry) async {
    final db = await database;
    final map = entry.toMap()
      ..['updated_at'] = _now()
      ..['deleted_at'] = null;
    await db.insert(
      'catches',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCatch(CatchEntry entry) async {
    final db = await database;
    final map = entry.toMap()..['updated_at'] = _now();
    await db.update(
      'catches',
      map,
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteCatch(String id) async {
    final db = await database;
    // Soft-Delete: Tombstone setzen, damit Cloud-Sync das Löschen propagieren
    // kann. Echtes Purgen passiert später zentral via [purgeTombstones].
    final now = _now();
    await db.update(
      'catches',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── Spots ────────────────────────────────────────────────────────────────

  Future<List<FishingSpot>> getSpots() async {
    final db = await database;
    final rows = await db.query(
      'spots',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    final List<FishingSpot> spots = [];
    for (final row in rows) {
      final notes = await _getSeasonNotes(row['id'] as String);
      spots.add(FishingSpot.fromMap(row, seasonNotes: notes));
    }
    return spots;
  }

  Future<FishingSpot?> getSpot(String id) async {
    final db = await database;
    final rows = await db.query(
      'spots',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final notes = await _getSeasonNotes(id);
    return FishingSpot.fromMap(rows.first, seasonNotes: notes);
  }

  Future<void> insertSpot(FishingSpot spot) async {
    final db = await database;
    final map = spot.toMap()
      ..['updated_at'] = _now()
      ..['deleted_at'] = null;
    await db.insert(
      'spots',
      map,
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
    final map = spot.toMap()..['updated_at'] = _now();
    await db.update(
      'spots',
      map,
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
    final now = _now();
    await db.update(
      'spots',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    // season_notes hängen am Spot — wenn der Spot gelöscht ist, sind sie
    // praktisch verwaist. Wir entfernen sie hart, da sie Teil des Spots sind.
    await db.delete('season_notes', where: 'spot_id = ?', whereArgs: [id]);
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

  // ─── Waterbodies ──────────────────────────────────────────────────────────

  Future<List<Waterbody>> getWaterbodies() async {
    final db = await database;
    final rows = await db.query(
      'waterbodies',
      where: 'deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE',
    );
    final list = <Waterbody>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final cs = await _getClosedSeasons(id);
      final sb = await _getSpinBans(id);
      list.add(Waterbody.fromMap(row, closedSeasons: cs, spinBans: sb));
    }
    return list;
  }

  Future<Waterbody?> getWaterbody(String id) async {
    final db = await database;
    final rows = await db.query(
      'waterbodies',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final cs = await _getClosedSeasons(id);
    final sb = await _getSpinBans(id);
    return Waterbody.fromMap(rows.first, closedSeasons: cs, spinBans: sb);
  }

  Future<void> insertWaterbody(Waterbody wb) async {
    final db = await database;
    final map = wb.toMap()
      ..['updated_at'] = _now()
      ..['deleted_at'] = null;
    await db.insert(
      'waterbodies',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.delete(
      'closed_seasons',
      where: 'waterbody_id = ?',
      whereArgs: [wb.id],
    );
    for (final cs in wb.closedSeasons) {
      await db.insert('closed_seasons', cs.toMap());
    }
    await db.delete(
      'spin_fishing_bans',
      where: 'waterbody_id = ?',
      whereArgs: [wb.id],
    );
    for (final b in wb.spinBans) {
      await db.insert('spin_fishing_bans', b.toMap());
    }
  }

  Future<void> updateWaterbody(Waterbody wb) async {
    final db = await database;
    final map = wb.toMap()..['updated_at'] = _now();
    await db.update(
      'waterbodies',
      map,
      where: 'id = ?',
      whereArgs: [wb.id],
    );
    await db.delete(
      'closed_seasons',
      where: 'waterbody_id = ?',
      whereArgs: [wb.id],
    );
    for (final cs in wb.closedSeasons) {
      await db.insert('closed_seasons', cs.toMap());
    }
    await db.delete(
      'spin_fishing_bans',
      where: 'waterbody_id = ?',
      whereArgs: [wb.id],
    );
    for (final b in wb.spinBans) {
      await db.insert('spin_fishing_bans', b.toMap());
    }
  }

  Future<void> deleteWaterbody(String id) async {
    final db = await database;
    // Spots auf NULL setzen, damit die Spots erhalten bleiben.
    await db.update(
      'spots',
      {'waterbody_id': null, 'updated_at': _now()},
      where: 'waterbody_id = ?',
      whereArgs: [id],
    );
    final now = _now();
    await db.update(
      'waterbodies',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    // closed_seasons / spin_fishing_bans hängen am Waterbody — hart entfernen,
    // sie sind nur als Subdokumente sinnvoll.
    await db.delete(
      'closed_seasons',
      where: 'waterbody_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'spin_fishing_bans',
      where: 'waterbody_id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ClosedSeason>> _getClosedSeasons(String waterbodyId) async {
    final db = await database;
    final rows = await db.query(
      'closed_seasons',
      where: 'waterbody_id = ?',
      whereArgs: [waterbodyId],
      orderBy: 'from_month, from_day',
    );
    return rows.map(ClosedSeason.fromMap).toList();
  }

  Future<List<SpinFishingBan>> _getSpinBans(String waterbodyId) async {
    final db = await database;
    final rows = await db.query(
      'spin_fishing_bans',
      where: 'waterbody_id = ?',
      whereArgs: [waterbodyId],
      orderBy: 'from_month, from_day',
    );
    return rows.map(SpinFishingBan.fromMap).toList();
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
      if (existingIds.contains(m.id)) {
        // Nur Anzeigefelder aktualisieren (kein Fortschritt/Status überschreiben).
        // Bewusst KEIN updated_at-Bump — reine Display-Änderungen sollen keinen
        // Sync-Push auslösen und auch andere Geräte nicht überschreiben.
        batch.update(
          'missions',
          {'emoji': m.emoji, 'title': m.title, 'description': m.description},
          where: 'id = ?',
          whereArgs: [m.id],
        );
      } else {
        final map = m.toMap()..['updated_at'] = _now();
        batch.insert(
          'missions',
          map,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateMission(Mission mission) async {
    final db = await database;
    final map = mission.toMap()..['updated_at'] = _now();
    await db.update(
      'missions',
      map,
      where: 'id = ?',
      whereArgs: [mission.id],
    );
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  Future<Map<String, int>> getCatchCountPerSpecies() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT species, COUNT(*) as count FROM catches '
      'WHERE deleted_at IS NULL GROUP BY species',
    );
    return {for (final r in rows) r['species'] as String: r['count'] as int};
  }

  Future<List<Map<String, dynamic>>> getMonthlyCatchCounts() async {
    final db = await database;
    return db.rawQuery(
      "SELECT strftime('%Y-%m', caught_at) as month, COUNT(*) as count "
      "FROM catches WHERE deleted_at IS NULL "
      "GROUP BY month ORDER BY month DESC LIMIT 12",
    );
  }

  Future<Map<String, int>> getTopLures({int limit = 5}) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT lure, COUNT(*) as count FROM catches '
      'WHERE lure IS NOT NULL AND deleted_at IS NULL '
      'GROUP BY lure ORDER BY count DESC LIMIT ?',
      [limit],
    );
    return {for (final r in rows) r['lure'] as String: r['count'] as int};
  }

  // ─── Trips ────────────────────────────────────────────────────────────────

  Future<List<Trip>> getTrips() async {
    final db = await database;
    final rows = await db.query(
      'trips',
      where: 'deleted_at IS NULL',
      orderBy: 'date ASC',
    );
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
    final map = trip.toMap()
      ..['updated_at'] = _now()
      ..['deleted_at'] = null;
    await db.insert(
      'trips',
      map,
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
    final map = trip.toMap()..['updated_at'] = _now();
    await db.update(
      'trips',
      map,
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
    final now = _now();
    await db.update(
      'trips',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    // trip_stops sind reine Subdokumente — hart löschen.
    await db.delete('trip_stops', where: 'trip_id = ?', whereArgs: [id]);
  }

  // ─── Water Days (manuelle Einträge) ──────────────────────────────────────

  /// Liefert alle manuell markierten Tage als ISO-Strings (YYYY-MM-DD).
  Future<List<String>> getManualWaterDays() async {
    final db = await database;
    final rows = await db.query(
      'water_days',
      where: 'deleted_at IS NULL',
      orderBy: 'date DESC',
    );
    return rows.map((r) => r['date'] as String).toList();
  }

  Future<void> insertWaterDay(String dateIso, {String? note}) async {
    final db = await database;
    await db.insert('water_days', {
      'date': dateIso,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': _now(),
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWaterDay(String dateIso) async {
    final db = await database;
    final now = _now();
    await db.update(
      'water_days',
      {'deleted_at': now, 'updated_at': now},
      where: 'date = ?',
      whereArgs: [dateIso],
    );
  }

  // ─── Sync-Helpers ─────────────────────────────────────────────────────────

  /// Für Cloud-Sync: alle Zeilen einer sync-relevanten Tabelle, die nach
  /// [sinceMs] modifiziert wurden — inklusive Tombstones.
  Future<List<Map<String, Object?>>> getSyncDelta(
    String table, {
    required int sinceMs,
  }) async {
    final db = await database;
    return db.query(
      table,
      where: 'updated_at > ?',
      whereArgs: [sinceMs],
      orderBy: 'updated_at ASC',
    );
  }

  /// Höchster `updated_at`-Wert in einer Tabelle (auch Tombstones zählen).
  /// Wird vom Cloud-Sync genutzt, um den Push-Cursor zu setzen.
  Future<int> getMaxUpdatedAt(String table) async {
    final db = await database;
    final rows = await db.rawQuery('SELECT MAX(updated_at) AS m FROM $table');
    return (rows.first['m'] as int?) ?? 0;
  }

  /// Roher Upsert für Sync-Pull. Ersetzt die Zeile mit identischer ID.
  /// Sub-Tabellen (season_notes, closed_seasons, spin_fishing_bans, trip_stops)
  /// können separat als Liste mitgegeben werden.
  Future<void> upsertSyncRow(
    String table,
    Map<String, Object?> row, {
    String? subTable,
    String? parentColumn,
    List<Map<String, Object?>>? subRows,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (subTable != null && parentColumn != null) {
        final parentId = row['id'] ?? row['date'];
        if (parentId != null) {
          await txn.delete(
            subTable,
            where: '$parentColumn = ?',
            whereArgs: [parentId],
          );
          if (subRows != null) {
            for (final sub in subRows) {
              await txn.insert(
                subTable,
                sub,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      }
    });
  }

  /// Liefert alle Sub-Rows zu einer Parent-ID (für Sync-Push).
  Future<List<Map<String, Object?>>> getSubRows(
    String subTable,
    String parentColumn,
    String parentId,
  ) async {
    final db = await database;
    return db.query(
      subTable,
      where: '$parentColumn = ?',
      whereArgs: [parentId],
    );
  }

  /// Endgültiges Entfernen abgelaufener Tombstones. Sollte gelegentlich
  /// (z.B. einmal pro App-Start nach erfolgreichem Sync) aufgerufen werden.
  Future<void> purgeTombstones({
    Duration olderThan = const Duration(days: 30),
  }) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    const tables = ['catches', 'spots', 'waterbodies', 'trips', 'water_days', 'missions'];
    for (final t in tables) {
      await db.delete(
        t,
        where: 'deleted_at IS NOT NULL AND deleted_at < ?',
        whereArgs: [cutoff],
      );
    }
  }
}
