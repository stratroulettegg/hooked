import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';

import '../../models/trip.dart';
import 'firebase_bootstrap.dart';

/// Fehler bei Cloud-Einladungen.
class TripInviteException implements Exception {
  final String message;
  const TripInviteException(this.message);
  @override
  String toString() => message;
}

/// Ergebnis einer erzeugten Einladung.
class TripInvite {
  final String token;
  final String tripId;
  final DateTime expiresAt;
  const TripInvite({
    required this.token,
    required this.tripId,
    required this.expiresAt,
  });
}

/// Teilnehmer eines geteilten Trips.
class TripParticipant {
  final String uid;
  final String? displayName;
  final String? photoURL;
  final String role; // 'owner' | 'member'
  final DateTime? joinedAt;
  const TripParticipant({
    required this.uid,
    this.displayName,
    this.photoURL,
    this.role = 'member',
    this.joinedAt,
  });

  bool get isOwner => role == 'owner';
}

/// Lädt/erzeugt Trip-Einladungen über Firestore.
///
/// Schema:
///   /sharedTrips/{tripId}  → komplette Trip-Daten + ownerUid
///   /invites/{token}       → { tripId, ownerUid, createdAt, expiresAt }
class TripCloudShareService {
  TripCloudShareService({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  /// ID der Firestore-Datenbank. Unser Projekt nutzt eine *named* DB
  /// namens `default` (nicht die implizite `(default)`).
  static const String databaseId = 'default';

  FirebaseFirestore get _db {
    if (!FirebaseBootstrap.isAvailable) {
      throw const TripInviteException(
        'Cloud-Einladungen sind nur mit Firebase-Konfiguration verfügbar.',
      );
    }
    return _firestore ??
        FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: databaseId,
        );
  }

  /// 8-stelliger, gut lesbarer Token (ohne 0/O/1/I).
  static String _generateToken() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(
      8,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Legt Trip + Einladung in Firestore an und gibt den Token zurück.
  /// Läuft nach 30 Tagen ab.
  ///
  /// Nebeneffekt: Der **lokale** Trip bekommt `cloudTripId = trip.id` —
  /// darum kümmert sich der Aufrufer, weil dieser Service keine lokale
  /// DB kennt.
  Future<TripInvite> createInvite({
    required Trip trip,
    required String ownerUid,
    Duration ttl = const Duration(days: 30),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final db = _db;
    final tripData = _encodeTrip(trip, ownerUid);
    final token = _generateToken();
    final now = DateTime.now().toUtc();
    final expires = now.add(ttl);

    try {
      // Beide Writes parallel. Kein get()-Kollisionscheck — bei 8 Zeichen
      // aus 32er-Alphabet (≈ 10¹² Kombinationen) praktisch ausgeschlossen.
      await Future.wait([
        db.collection('sharedTrips').doc(trip.id).set(tripData),
        db.collection('invites').doc(token).set({
          'tripId': trip.id,
          'ownerUid': ownerUid,
          'createdAt': Timestamp.fromDate(now),
          'expiresAt': Timestamp.fromDate(expires),
        }),
      ]).timeout(timeout);
    } on FirebaseException catch (e) {
      throw TripInviteException(
        'Firestore-Fehler (${e.code}): ${e.message ?? 'unbekannt'}. '
        'Ist Firestore im Firebase-Console aktiviert und sind die Rules '
        'ausgerollt?',
      );
    } on TimeoutException {
      throw const TripInviteException(
        'Firestore antwortet nicht. Prüfe deine Internetverbindung oder '
        'ob die Firestore-Datenbank im Firebase-Console angelegt ist.',
      );
    }

    return TripInvite(token: token, tripId: trip.id, expiresAt: expires);
  }

  /// Pusht Änderungen eines bereits geteilten Trips in die Cloud.
  /// `ownerUid` bleibt dabei unberührt — jeder authentifizierte Teilnehmer
  /// darf die Trip-Felder überschreiben (siehe firestore.rules).
  Future<void> pushUpdate(
    Trip trip, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cloudId = trip.cloudTripId;
    if (cloudId == null) {
      throw const TripInviteException(
        'Trip ist nicht mit der Cloud verknüpft.',
      );
    }
    final db = _db;
    final data = _encodeTrip(trip, '')
      ..remove('ownerUid') // Owner nicht überschreiben
      ..remove('createdAt') // Createzeit bleibt stehen
      ..['id'] =
          cloudId // Cloud-ID ist maßgeblich, nicht die lokale
      ..['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());
    try {
      await db
          .collection('sharedTrips')
          .doc(cloudId)
          .update(data)
          .timeout(timeout);
    } on FirebaseException catch (e) {
      throw TripInviteException(
        'Konnte Trip nicht synchronisieren (${e.code}): '
        '${e.message ?? 'unbekannt'}',
      );
    } on TimeoutException {
      throw const TripInviteException(
        'Firestore antwortet nicht. Änderungen wurden lokal gespeichert, '
        'Cloud-Sync später erneut versuchen.',
      );
    }
  }

  /// Holt den aktuellen Cloud-Stand eines bereits bekannten Trips.
  /// Liefert eine neue Trip-Instanz mit der **lokalen** ID und neuen
  /// deterministischen Stop-IDs.
  /// Gibt `null` zurück, wenn der Trip in der Cloud gelöscht wurde.
  Future<Trip?> fetchCloudTrip(
    Trip localTrip, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cloudId = localTrip.cloudTripId;
    if (cloudId == null) return localTrip;
    final db = _db;
    try {
      final doc = await db
          .collection('sharedTrips')
          .doc(cloudId)
          .get()
          .timeout(timeout);
      if (!doc.exists) return null;
      return _decodeTripInto(
        doc.data()!,
        localTripId: localTrip.id,
        cloudTripId: cloudId,
      );
    } on FirebaseException catch (e) {
      throw TripInviteException(
        'Konnte Cloud-Trip nicht laden (${e.code}): '
        '${e.message ?? 'unbekannt'}',
      );
    } on TimeoutException {
      throw const TripInviteException(
        'Firestore antwortet nicht. Lokal-Version wird angezeigt.',
      );
    }
  }

  /// Löst eine Einladung ein und liefert den geladenen Trip zurück.
  /// Der Trip wird **nicht** lokal gespeichert — das übernimmt der Aufrufer.
  /// Eingeladene erhalten eine **Read-only-Kopie**: sie bekommen eine neue
  /// lokale UUID, der Cloud-Link dient nur zum Pull-Refresh durch den Owner.
  Future<Trip> redeemInvite(
    String rawToken, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final db = _db;
    final token = rawToken.trim().toUpperCase();
    if (token.isEmpty) {
      throw const TripInviteException('Bitte einen Einladungscode eingeben.');
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      // Token in einer Transaction lesen + sofort löschen, damit ein
      // gleichzeitiger zweiter Redeem ins Leere läuft (Single-Use).
      final inviteRef = db.collection('invites').doc(token);
      final tripId = await db
          .runTransaction<String>((tx) async {
            final snap = await tx.get(inviteRef);
            if (!snap.exists) {
              throw const TripInviteException(
                'Code ungültig oder bereits eingelöst.',
              );
            }
            final data = snap.data()!;
            final id = data['tripId'] as String?;
            final ownerUid = data['ownerUid'] as String?;
            final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
            if (id == null) {
              throw const TripInviteException('Code ist ungültig.');
            }
            // Eigene Einladung darf nicht eingelöst werden — sonst wäre der
            // Single-Use-Token aus Versehen verbrannt und der eigentliche
            // Empfänger könnte ihn nicht mehr nutzen. Token bleibt erhalten.
            if (ownerUid != null &&
                currentUid != null &&
                ownerUid == currentUid) {
              throw const TripInviteException(
                'Das ist deine eigene Einladung — gib den Code an die Person '
                'weiter, die du einladen möchtest.',
              );
            }
            if (expiresAt != null &&
                expiresAt.isBefore(DateTime.now().toUtc())) {
              // Abgelaufen → trotzdem löschen, damit es niemanden mehr verwirrt.
              tx.delete(inviteRef);
              throw const TripInviteException('Code ist abgelaufen.');
            }
            tx.delete(inviteRef);
            return id;
          })
          .timeout(timeout);

      final tripDoc = await db
          .collection('sharedTrips')
          .doc(tripId)
          .get()
          .timeout(timeout);
      if (!tripDoc.exists) {
        throw const TripInviteException('Trip wurde vom Besitzer entfernt.');
      }
      return _decodeTrip(tripDoc.data()!);
    } on TripInviteException {
      rethrow;
    } on FirebaseException catch (e) {
      throw TripInviteException(
        'Firestore-Fehler (${e.code}): ${e.message ?? 'unbekannt'}',
      );
    } on TimeoutException {
      throw const TripInviteException(
        'Firestore antwortet nicht. Prüfe deine Internetverbindung.',
      );
    }
  }

  /// Extrahiert einen Token aus Rohtext.
  /// Akzeptiert: "ABCD1234" oder eingebettet in beliebigem Text.
  static String? extractToken(String input) {
    final cleaned = input.trim().toUpperCase();
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'([A-HJ-NP-Z2-9]{8})').firstMatch(cleaned);
    return match?.group(1);
  }

  // ── Teilnehmer ────────────────────────────────────────────────────────

  /// Trägt den aktuellen User als Teilnehmer eines Cloud-Trips ein
  /// (idempotent via merge). Aktualisiert auch displayName/photoURL,
  /// damit Profil-Änderungen sofort bei allen sichtbar werden.
  Future<void> ensureParticipant({
    required String cloudTripId,
    required User user,
    String role = 'member',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final db = _db;
    final ref = db
        .collection('sharedTrips')
        .doc(cloudTripId)
        .collection('participants')
        .doc(user.uid);
    try {
      await ref
          .set({
            'uid': user.uid,
            'displayName': user.displayName,
            'photoURL': user.photoURL,
            'role': role,
            'joinedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(timeout);
    } on FirebaseException {
      // Nicht kritisch — Teilnehmer-Liste ist Komfort, nicht essenziell.
      rethrow;
    } on TimeoutException {
      // ignore: stumm
    }
  }

  /// Entfernt den eigenen Teilnehmer-Eintrag aus einem Cloud-Trip
  /// ("Trip verlassen"). Idempotent — wenn der Eintrag nicht existiert,
  /// wird kein Fehler geworfen.
  Future<void> leaveSharedTrip({
    required String cloudTripId,
    required String uid,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final db = _db;
    try {
      await db
          .collection('sharedTrips')
          .doc(cloudTripId)
          .collection('participants')
          .doc(uid)
          .delete()
          .timeout(timeout);
    } on FirebaseException catch (e) {
      // not-found ist OK (z. B. mehrfacher Aufruf).
      if (e.code == 'not-found') return;
      throw TripInviteException(
        'Konnte Trip nicht verlassen (${e.code}): ${e.message ?? 'unbekannt'}',
      );
    } on TimeoutException {
      throw const TripInviteException(
        'Firestore antwortet nicht. Bitte später erneut versuchen.',
      );
    }
  }

  /// Löscht einen Cloud-Trip vollständig — inklusive aller Teilnehmer-
  /// Einträge. Darf nur vom Owner aufgerufen werden (Firestore-Rules
  /// erzwingen das ohnehin). Auch zugehörige offene Invite-Tokens für
  /// diesen Trip werden best-effort entfernt.
  Future<void> deleteSharedTrip(
    String cloudTripId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final db = _db;
    try {
      // 1) Teilnehmer-Subcollection in Batches löschen.
      final partsSnap = await db
          .collection('sharedTrips')
          .doc(cloudTripId)
          .collection('participants')
          .get()
          .timeout(timeout);
      if (partsSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (final d in partsSnap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit().timeout(timeout);
      }

      // 2) Offene Invite-Tokens für diesen Trip aufräumen (best effort).
      try {
        final invites = await db
            .collection('invites')
            .where('tripId', isEqualTo: cloudTripId)
            .get()
            .timeout(timeout);
        if (invites.docs.isNotEmpty) {
          final batch = db.batch();
          for (final d in invites.docs) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(timeout);
        }
      } catch (_) {
        // Invites-Aufräumen ist Komfort — nicht blockierend.
      }

      // 3) Den Trip selbst löschen.
      await db
          .collection('sharedTrips')
          .doc(cloudTripId)
          .delete()
          .timeout(timeout);
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return; // schon weg → OK
      throw TripInviteException(
        'Konnte Cloud-Trip nicht löschen (${e.code}): '
        '${e.message ?? 'unbekannt'}',
      );
    } on TimeoutException {
      throw const TripInviteException(
        'Firestore antwortet nicht. Bitte später erneut versuchen.',
      );
    }
  }

  /// Live-Stream aller Teilnehmer eines geteilten Trips.
  Stream<List<TripParticipant>> participantsStream(String cloudTripId) {
    final db = _db;
    return db
        .collection('sharedTrips')
        .doc(cloudTripId)
        .collection('participants')
        .snapshots()
        .map((qs) {
          final list = qs.docs.map((d) {
            final data = d.data();
            return TripParticipant(
              uid: (data['uid'] as String?) ?? d.id,
              displayName: data['displayName'] as String?,
              photoURL: data['photoURL'] as String?,
              role: (data['role'] as String?) ?? 'member',
              joinedAt: (data['joinedAt'] as Timestamp?)?.toDate().toLocal(),
            );
          }).toList();
          // Owner zuerst, dann nach Beitrittsdatum.
          list.sort((a, b) {
            if (a.isOwner && !b.isOwner) return -1;
            if (!a.isOwner && b.isOwner) return 1;
            final aJ = a.joinedAt;
            final bJ = b.joinedAt;
            if (aJ == null && bJ == null) return 0;
            if (aJ == null) return 1;
            if (bJ == null) return -1;
            return aJ.compareTo(bJ);
          });
          return list;
        });
  }

  /// Holt alle Cloud-Trips, die der angegebene User entweder besitzt
  /// (`ownerUid == uid`) oder bei denen er als Teilnehmer eingetragen ist.
  /// Wird beim Login auf einem neuen Gerät aufgerufen, um lokal fehlende
  /// Trips wiederherzustellen.
  ///
  /// Gibt eine Liste von `(Map firestoreData, bool isOwner)`-Tupeln zurück
  /// — der Aufrufer entscheidet, wie sie in lokale Trips übersetzt werden.
  Future<List<({Map<String, dynamic> data, String cloudId, bool isOwner})>>
  fetchTripsForUser(
    String uid, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final db = _db;
    try {
      // 1) Eigene Trips direkt aus sharedTrips abfragen.
      final ownedFuture = db
          .collection('sharedTrips')
          .where('ownerUid', isEqualTo: uid)
          .get()
          .timeout(timeout);

      // 2) Teilnahmen via Collection-Group-Query auf participants.
      final joinedFuture = db
          .collectionGroup('participants')
          .where('uid', isEqualTo: uid)
          .get()
          .timeout(timeout);

      final results = await Future.wait([ownedFuture, joinedFuture]);
      final ownedSnap = results[0];
      final joinedSnap = results[1];

      final out =
          <({Map<String, dynamic> data, String cloudId, bool isOwner})>[];
      final seen = <String>{};

      for (final d in ownedSnap.docs) {
        if (seen.add(d.id)) {
          out.add((data: d.data(), cloudId: d.id, isOwner: true));
        }
      }

      // Für jede Teilnehmer-Doc den Parent-Trip nachladen (parallel).
      final parentRefs = joinedSnap.docs
          .map((d) => d.reference.parent.parent)
          .whereType<DocumentReference<Map<String, dynamic>>>()
          .where((ref) => seen.add(ref.id))
          .toList();
      if (parentRefs.isNotEmpty) {
        final parents = await Future.wait(
          parentRefs.map((r) => r.get().timeout(timeout)),
        );
        for (final p in parents) {
          final data = p.data();
          if (data == null) continue;
          // Wenn ownerUid == uid hatten wir den Trip schon → defensive Prüfung.
          final isOwner = (data['ownerUid'] as String?) == uid;
          out.add((data: data, cloudId: p.id, isOwner: isOwner));
        }
      }
      return out;
    } on FirebaseException catch (e) {
      throw TripInviteException(
        'Konnte Cloud-Trips nicht laden (${e.code}): '
        '${e.message ?? 'unbekannt'}',
      );
    } on TimeoutException {
      throw const TripInviteException(
        'Firestore antwortet nicht. Cloud-Trips konnten nicht wiederhergestellt werden.',
      );
    }
  }

  /// Decodiert einen Firestore-Trip mit explizit vorgegebener lokaler ID.
  /// Wird vom Cloud-Trip-Restore genutzt: für Owner == cloudId, für Member
  /// eine neue UUID.
  Trip decodeForRestore(
    Map<String, dynamic> data, {
    required String cloudId,
    required bool isOwner,
  }) {
    final localId = isOwner ? cloudId : const Uuid().v4();
    return _decodeTripInto(data, localTripId: localId, cloudTripId: cloudId);
  }

  Map<String, dynamic> _encodeTrip(Trip trip, String ownerUid) {
    return {
      'id': trip.id,
      'name': trip.name,
      'date': Timestamp.fromDate(trip.date.toUtc()),
      'waterBodyName': trip.waterBodyName,
      'centerLat': trip.centerLat,
      'centerLng': trip.centerLng,
      'notes': trip.notes,
      'checklist': trip.checklist,
      'ownerUid': ownerUid,
      'createdAt': Timestamp.fromDate(trip.createdAt.toUtc()),
      'stops': trip.stops
          .map(
            (s) => {
              'id': s.id,
              'name': s.name,
              'lat': s.lat,
              'lng': s.lng,
              'orderIndex': s.orderIndex,
              'notes': s.notes,
            },
          )
          .toList(),
    };
  }

  Trip _decodeTrip(Map<String, dynamic> data) {
    // Neue lokale IDs vergeben, damit ein importierter Trip nicht mit einem
    // eigenen kollidiert. UUIDv4 — konsistent mit neu erstellten lokalen Trips.
    final newTripId = const Uuid().v4();
    final cloudId = data['id'] as String?;
    return _decodeTripInto(data, localTripId: newTripId, cloudTripId: cloudId);
  }

  /// Decodiert ein Firestore-Dokument in einen [Trip] mit explizit
  /// vorgegebener lokaler ID. Wird sowohl beim Initial-Import als auch beim
  /// Refresh verwendet.
  Trip _decodeTripInto(
    Map<String, dynamic> data, {
    required String localTripId,
    required String? cloudTripId,
  }) {
    final stopsRaw = (data['stops'] as List?) ?? const [];
    final stops = <TripStop>[];
    for (var i = 0; i < stopsRaw.length; i++) {
      final s = stopsRaw[i] as Map<String, dynamic>;
      stops.add(
        TripStop(
          id: '${localTripId}_s_$i',
          tripId: localTripId,
          name: (s['name'] as String?) ?? 'Spot',
          lat: (s['lat'] as num).toDouble(),
          lng: (s['lng'] as num).toDouble(),
          orderIndex: (s['orderIndex'] as num?)?.toInt() ?? i,
          notes: s['notes'] as String?,
        ),
      );
    }
    return Trip(
      id: localTripId,
      name: (data['name'] as String?) ?? 'Geteilter Trip',
      date: (data['date'] as Timestamp).toDate().toLocal(),
      waterBodyName: data['waterBodyName'] as String?,
      centerLat: (data['centerLat'] as num).toDouble(),
      centerLng: (data['centerLng'] as num).toDouble(),
      notes: data['notes'] as String?,
      checklist: ((data['checklist'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate().toLocal() ??
          DateTime.now(),
      stops: stops,
      cloudTripId: cloudTripId,
    );
  }
}
