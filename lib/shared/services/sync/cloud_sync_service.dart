import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local_database_service.dart';
import 'photo_sync_service.dart';

/// Status des Cloud-Sync für UI-Indikatoren.
enum SyncState { idle, syncing, error, offline }

/// Snapshot aus dem [CloudSyncService.statusStream].
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.lastSuccessAt,
    this.errorMessage,
    this.lastPullApplied = 0,
  });

  final SyncState state;
  final DateTime? lastSuccessAt;
  final String? errorMessage;

  /// Anzahl Remote-Zeilen, die im letzten erfolgreichen Sync
  /// tatsächlich in die lokale DB übernommen wurden. Dient dem
  /// Orchestrator als Trigger, ob die Daten-Provider invalidiert
  /// werden müssen — sonst Endlos-Loop, weil das Invalidate selbst
  /// einen neuen Sync auslöst.
  final int lastPullApplied;

  SyncStatus copyWith({
    SyncState? state,
    DateTime? lastSuccessAt,
    String? errorMessage,
    int? lastPullApplied,
  }) => SyncStatus(
    state: state ?? this.state,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    errorMessage: errorMessage,
    lastPullApplied: lastPullApplied ?? this.lastPullApplied,
  );

  static const idle = SyncStatus(state: SyncState.idle);
}

/// Konfiguration einer sync-fähigen Tabelle.
///
/// Eltern-Tabelle wird per LWW gespiegelt. Optional kann eine Sub-Tabelle
/// (z.B. `trip_stops` zu `trips`) mitgesynced werden — sie wird beim
/// Eltern-Upsert komplett ersetzt (keine eigenen Tombstones nötig).
class _SyncTableSpec {
  const _SyncTableSpec({
    required this.table,
    required this.idColumn,
    this.subTable,
    this.subParentColumn,
  });

  final String table;
  final String idColumn;
  final String? subTable;
  final String? subParentColumn;
}

/// Spiegelt die lokalen sqflite-Tabellen für den eingeloggten Pro-User
/// nach Firestore und zurück. Last-Write-Wins via `updated_at`,
/// Soft-Delete via `deleted_at`.
class CloudSyncService {
  CloudSyncService({
    LocalDatabaseService? db,
    FirebaseFirestore? firestore,
    PhotoSyncService? photoSync,
  }) : _db = db ?? LocalDatabaseService(),
       _firestore =
           firestore ??
           FirebaseFirestore.instanceFor(
             app: Firebase.app(),
             databaseId: syncDatabaseId,
           ),
       _photoSync = photoSync ?? PhotoSyncService(db: db);

  /// ID der Firestore-Datenbank in diesem Projekt. Hier ist es eine
  /// benannte DB namens `default` (nicht die spezielle `(default)`-DB).
  static const String syncDatabaseId = 'default';

  final LocalDatabaseService _db;
  final FirebaseFirestore _firestore;
  final PhotoSyncService _photoSync;

  static const _tables = <_SyncTableSpec>[
    _SyncTableSpec(table: 'catches', idColumn: 'id'),
    _SyncTableSpec(
      table: 'spots',
      idColumn: 'id',
      subTable: 'season_notes',
      subParentColumn: 'spot_id',
    ),
    _SyncTableSpec(
      table: 'waterbodies',
      idColumn: 'id',
      // Wir packen closed_seasons + spin_fishing_bans gemeinsam in das
      // Firestore-Doc ab — siehe _pushRow / _applyRemoteRow.
    ),
    _SyncTableSpec(
      table: 'trips',
      idColumn: 'id',
      subTable: 'trip_stops',
      subParentColumn: 'trip_id',
    ),
    _SyncTableSpec(table: 'water_days', idColumn: 'date'),
    _SyncTableSpec(table: 'missions', idColumn: 'id'),
  ];

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = SyncStatus.idle;
  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get status => _status;

  Timer? _debounce;
  bool _running = false;

  void dispose() {
    _debounce?.cancel();
    _statusController.close();
  }

  /// Plant einen Sync nach kurzer Wartezeit ein. Mehrfach-Aufrufe
  /// während des Debounce-Fensters werden zu einem Sync zusammengefasst.
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => unawaited(syncNow()));
  }

  /// Erzwingt einen vollständigen Re-Upload aller lokalen Daten. Setzt die
  /// Push-Cursor in `meta/sync` zurück auf 0 und stempelt alle lokalen
  /// Zeilen mit dem aktuellen Timestamp, sodass sie als „neu" erkannt
  /// werden. Anschließend wird ein Sync angestoßen.
  ///
  /// Sinnvoll als Debug-/Recovery-Aktion, wenn der Cloud-Stand aus
  /// irgendeinem Grund hinter dem lokalen zurückbleibt.
  Future<void> forceFullResync() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final spec in _tables) {
      await db.update(spec.table, {'updated_at': now});
    }
    final userDoc = _firestore.collection('users').doc(user.uid);
    final reset = <String, Object?>{};
    for (final spec in _tables) {
      reset['push_${spec.table}'] = 0;
    }
    await userDoc.collection('meta').doc('sync').set(
      reset,
      SetOptions(merge: true),
    );
    await syncNow();
  }

  /// Erzwingt einen vollständigen Re-Pull aller Remote-Daten. Setzt die
  /// **lokalen** Pull-Cursor (per UID) auf 0 zurück, sodass beim nächsten
  /// Sync alle Firestore-Docs erneut nach SQLite gespiegelt werden. Die
  /// Cloud-Daten selbst bleiben unverändert.
  ///
  /// Sinnvoll auf einem zweit-/neu-installierten Gerät, das die lokal
  /// gespeicherten Cursor verloren hat oder aus anderem Grund nichts mehr
  /// pullt.
  Future<void> forceFullRepull() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    for (final spec in _tables) {
      await prefs.remove(_pullCursorKey(user.uid, spec.table));
    }
    await syncNow();
  }

  /// Führt einen kompletten Pull+Push-Zyklus aus. Nimmt automatisch das
  /// derzeit eingeloggte Firebase-User-Konto. Wenn kein User eingeloggt
  /// ist oder der Sync gerade läuft, ist der Aufruf ein No-Op.
  Future<void> syncNow() async {
    if (_running) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _emit(_status.copyWith(state: SyncState.offline));
      return;
    }
    _running = true;
    _emit(_status.copyWith(state: SyncState.syncing, errorMessage: null));
    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      // Pull zuerst, dann Push — vermeidet dass ein lokaler Push die
      // Remote-Updates desselben Cycles überschreibt, wenn dazwischen
      // Daten lokal entstanden.
      final pulled = await _pullAll(userDoc);
      await _pushAll(userDoc);
      // Wartet, bis alle gepushten Writes serverseitig bestätigt sind.
      // Ohne dies returnt `batch.commit()` bereits aus dem lokalen
      // Offline-Cache und der Status springt fälschlich auf „Erfolg",
      // obwohl der Server die Daten nie erhalten hat.
      try {
        await _firestore
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        throw Exception(
          'Server hat die Schreibvorgänge nicht innerhalb von 30 s '
          'bestätigt — vermutlich keine Verbindung zur Cloud-Datenbank. '
          'Prüfe Internetverbindung und App-Check-Token.',
        );
      }
      // Fotos: Daten-Docs sind durch — jetzt die Bilder. Fehler hier
      // kippen den Sync nicht (Bilder sind eventually consistent).
      final photoReport = await _photoSync.syncAll();
      if (kDebugMode && photoReport.errors > 0) {
        // ignore: avoid_print
        print(
          '[CloudSync] photos: '
          'uploaded=${photoReport.uploaded} '
          'downloaded=${photoReport.downloaded} '
          'errors=${photoReport.errors}',
        );
      }
      await _db.purgeTombstones();
      final now = DateTime.now();
      _emit(
        SyncStatus(
          state: SyncState.idle,
          lastSuccessAt: now,
          lastPullApplied: pulled,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('CloudSync error: $e\n$st');
      }
      _emit(
        _status.copyWith(state: SyncState.error, errorMessage: e.toString()),
      );
    } finally {
      _running = false;
    }
  }

  // ─── Pull ──────────────────────────────────────────────────────────────

  Future<int> _pullAll(
    DocumentReference<Map<String, dynamic>> userDoc,
  ) async {
    var applied = 0;
    final uid = userDoc.id;
    for (final spec in _tables) {
      // WICHTIG: Pull-Cursor liegt lokal (per UID), nicht in Firestore-Meta.
      // Firestore-Meta wird zwischen Geräten geteilt — wenn Gerät 1 nach
      // einem Push den eigenen Cursor weiterstellt, würde Gerät 2 nichts
      // mehr pullen, weil die Query `updated_at > lastPull` leer wäre.
      final lastPull = await _readLocalPullCursor(uid, spec.table);
      Query<Map<String, dynamic>> q = userDoc
          .collection(spec.table)
          .where('updated_at', isGreaterThan: lastPull)
          .orderBy('updated_at')
          .limit(500);
      while (true) {
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        for (final doc in snap.docs) {
          if (await _applyRemoteRow(spec, doc.data())) applied++;
        }
        final newest = snap.docs.last.data()['updated_at'];
        if (newest is int) {
          await _writeLocalPullCursor(uid, spec.table, newest);
        }
        if (snap.docs.length < 500) break;
        q = q.startAfterDocument(snap.docs.last);
      }
    }
    return applied;
  }

  /// Wendet eine Remote-Row lokal an. Liefert `true`, wenn die Row
  /// tatsächlich gespeichert wurde (d.h. neuer als die lokale Version).
  Future<bool> _applyRemoteRow(
    _SyncTableSpec spec,
    Map<String, dynamic> remote,
  ) async {
    // Firestore-Felder bestehen aus dem Original-DB-Row plus optional
    // `_sub` (Sub-Rows) bzw. weitere Subdoc-Listen für waterbodies.
    final raw = Map<String, Object?>.from(remote);
    final subRows = (raw.remove('_sub') as List?)
        ?.map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    final closedSeasons = (raw.remove('_closed_seasons') as List?)
        ?.map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    final spinBans = (raw.remove('_spin_bans') as List?)
        ?.map((e) => Map<String, Object?>.from(e as Map))
        .toList();

    // LWW: nur anwenden, wenn remote.updated_at > local.updated_at.
    final remoteUpdatedAt = (raw['updated_at'] as int?) ?? 0;
    final localUpdatedAt = await _localUpdatedAt(spec, raw[spec.idColumn]);
    if (localUpdatedAt >= remoteUpdatedAt) return false;

    await _db.upsertSyncRow(
      spec.table,
      raw,
      subTable: spec.subTable,
      parentColumn: spec.subParentColumn,
      subRows: subRows,
    );
    // Spezialfall waterbodies: beide Sub-Tabellen zurückspielen.
    if (spec.table == 'waterbodies') {
      final id = raw['id'];
      if (id != null) {
        await _db.upsertSyncRow(
          spec.table,
          raw,
          subTable: 'closed_seasons',
          parentColumn: 'waterbody_id',
          subRows: closedSeasons,
        );
        await _db.upsertSyncRow(
          spec.table,
          raw,
          subTable: 'spin_fishing_bans',
          parentColumn: 'waterbody_id',
          subRows: spinBans,
        );
      }
    }
    return true;
  }

  Future<int> _localUpdatedAt(_SyncTableSpec spec, Object? id) async {
    if (id == null) return 0;
    final db = await _db.database;
    final rows = await db.query(
      spec.table,
      columns: ['updated_at'],
      where: '${spec.idColumn} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['updated_at'] as int?) ?? 0;
  }

  // ─── Push ──────────────────────────────────────────────────────────────

  Future<void> _pushAll(DocumentReference<Map<String, dynamic>> userDoc) async {
    for (final spec in _tables) {
      final lastPush = await _readMeta(userDoc, 'push_${spec.table}');
      final delta = await _db.getSyncDelta(spec.table, sinceMs: lastPush);
      if (delta.isEmpty) continue;
      // Firestore-Batches max 500 Operationen.
      var maxUpdatedAt = lastPush;
      for (var i = 0; i < delta.length; i += 400) {
        final chunk = delta.sublist(
          i,
          (i + 400).clamp(0, delta.length),
        );
        final batch = _firestore.batch();
        for (final row in chunk) {
          final doc = await _buildRemoteDoc(spec, row);
          final ref = userDoc.collection(spec.table).doc('${row[spec.idColumn]}');
          batch.set(ref, doc);
          final ts = row['updated_at'];
          if (ts is int && ts > maxUpdatedAt) maxUpdatedAt = ts;
        }
        await batch.commit();
      }
      await _writeMeta(userDoc, 'push_${spec.table}', maxUpdatedAt);
    }
  }

  Future<Map<String, dynamic>> _buildRemoteDoc(
    _SyncTableSpec spec,
    Map<String, Object?> row,
  ) async {
    final out = <String, dynamic>{...row};
    final id = row[spec.idColumn]?.toString();
    if (id == null) return out;
    if (spec.subTable != null && spec.subParentColumn != null) {
      out['_sub'] = await _db.getSubRows(spec.subTable!, spec.subParentColumn!, id);
    }
    if (spec.table == 'waterbodies') {
      out['_closed_seasons'] = await _db.getSubRows(
        'closed_seasons',
        'waterbody_id',
        id,
      );
      out['_spin_bans'] = await _db.getSubRows(
        'spin_fishing_bans',
        'waterbody_id',
        id,
      );
    }
    return out;
  }

  // ─── Meta ──────────────────────────────────────────────────────────────

  Future<int> _readMeta(
    DocumentReference<Map<String, dynamic>> userDoc,
    String key,
  ) async {
    final snap = await userDoc.collection('meta').doc('sync').get();
    final data = snap.data();
    if (data == null) return 0;
    return (data[key] as int?) ?? 0;
  }

  Future<void> _writeMeta(
    DocumentReference<Map<String, dynamic>> userDoc,
    String key,
    int value,
  ) async {
    await userDoc
        .collection('meta')
        .doc('sync')
        .set({key: value}, SetOptions(merge: true));
  }

  // ─── Lokaler Pull-Cursor (per UID) ──────────────────────────────────────

  String _pullCursorKey(String uid, String table) =>
      'cloud_sync.pull_cursor.$uid.$table';

  Future<int> _readLocalPullCursor(String uid, String table) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pullCursorKey(uid, table)) ?? 0;
  }

  Future<void> _writeLocalPullCursor(
    String uid,
    String table,
    int value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pullCursorKey(uid, table), value);
  }

  void _emit(SyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}
