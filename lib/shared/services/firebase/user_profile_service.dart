import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/catch_entry.dart';
import '../moderation/community_words.dart';
import 'firebase_bootstrap.dart';

/// Öffentliches User-Profil — wird in `userProfiles/{uid}` gespeichert und
/// dient als Quelle für „Profil ansehen", Follow-Listen und Suche.
///
/// **Hinweis zu Followern**: Counter werden bewusst NICHT im Doc gespeichert
/// (Manipulationsschutz). Stats kommen via `count()`-Aggregation aus den
/// Subcollections `followers/` und `following/`.
class UserProfile {
  final String uid;
  final String? handle;
  final String? displayName;
  final String? photoUrl;
  final String? steckbrief;
  final List<FishSpecies> targetSpecies;
  final DateTime? updatedAt;
  final DateTime? createdAt;
  final DateTime? handleChangedAt;

  const UserProfile({
    required this.uid,
    this.handle,
    this.displayName,
    this.photoUrl,
    this.steckbrief,
    this.targetSpecies = const [],
    this.updatedAt,
    this.createdAt,
    this.handleChangedAt,
  });

  factory UserProfile.empty(String uid) => UserProfile(uid: uid);

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    final speciesRaw =
        (map['targetSpecies'] as List?)?.cast<String>() ?? const [];
    DateTime? toDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return UserProfile(
      uid: uid,
      handle: map['handle'] as String?,
      displayName: map['displayName'] as String?,
      photoUrl: map['photoUrl'] as String?,
      steckbrief: map['steckbrief'] as String?,
      targetSpecies: speciesRaw
          .map(
            (s) => FishSpecies.values.firstWhere(
              (e) => e.name == s,
              orElse: () => FishSpecies.andere,
            ),
          )
          .toList(),
      updatedAt: toDate(map['updatedAt']),
      createdAt: toDate(map['createdAt']),
      handleChangedAt: toDate(map['handleChangedAt']),
    );
  }

  /// True, wenn das Pflicht-Setup (Handle + Display-Name) abgeschlossen ist.
  bool get hasCompletedSetup {
    final h = handle?.trim() ?? '';
    final n = displayName?.trim() ?? '';
    return h.isNotEmpty && n.isNotEmpty;
  }
}

/// Ergebnis einer Handle-Validierung.
class HandleValidationError {
  final String code;
  final String message;
  const HandleValidationError(this.code, this.message);
}

/// Reine Format-Validierung für Handles. Gibt `null` zurück, wenn alles ok ist.
/// **Eindeutigkeit** wird hier NICHT geprüft (das macht der Server).
HandleValidationError? validateHandleFormat(String raw) {
  final h = raw.trim().toLowerCase();
  if (h.isEmpty) {
    return const HandleValidationError('empty', 'Bitte einen Benutzernamen wählen.');
  }
  if (h.length < 3) {
    return const HandleValidationError('too_short', 'Mindestens 3 Zeichen.');
  }
  if (h.length > 24) {
    return const HandleValidationError('too_long', 'Höchstens 24 Zeichen.');
  }
  final re = RegExp(r'^[a-z0-9._]+$');
  if (!re.hasMatch(h)) {
    return const HandleValidationError(
      'bad_chars',
      'Nur Kleinbuchstaben, Zahlen, Punkt und Unterstrich erlaubt.',
    );
  }
  if (h.startsWith('.') || h.startsWith('_') || h.endsWith('.') || h.endsWith('_')) {
    return const HandleValidationError(
      'bad_edges',
      'Darf nicht mit . oder _ beginnen oder enden.',
    );
  }
  if (h.contains('..') || h.contains('__')) {
    return const HandleValidationError(
      'bad_double',
      'Keine doppelten . oder _.',
    );
  }
  const reserved = <String>{
    'admin', 'administrator', 'hooked', 'support', 'system', 'null',
    'me', 'self', 'root', 'official', 'moderator', 'mod', 'team',
    'help', 'staff', 'fischer', 'angler',
  };
  if (reserved.contains(h)) {
    return const HandleValidationError(
      'reserved',
      'Dieser Benutzername ist reserviert.',
    );
  }
  if (findBannedWord(h) != null) {
    return const HandleValidationError(
      'banned',
      'Dieser Benutzername verstößt gegen unsere Community-Regeln.',
    );
  }
  return null;
}

/// Display-Name-Validierung fürs Setup-Formular.
String? validateDisplayName(String raw) {
  final n = raw.trim();
  if (n.length < 2) return 'Mindestens 2 Zeichen.';
  if (n.length > 40) return 'Höchstens 40 Zeichen.';
  if (findBannedWord(n) != null) {
    return 'Dieser Name verstößt gegen unsere Community-Regeln.';
  }
  return null;
}

/// Steckbrief-Validierung. Leerer Text ist erlaubt.
String? validateSteckbrief(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.length > 280) return 'Höchstens 280 Zeichen.';
  if (findBannedWord(s) != null) {
    return 'Dein Steckbrief verstößt gegen unsere Community-Regeln.';
  }
  return null;
}

/// Service für UserProfile-CRUD und das Follow-System.
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  static const String databaseId = 'default';
  static const int _maxSteckbrief = 280;
  static const int _maxTargetSpecies = 20;

  FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: databaseId,
  );

  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) =>
      _db.collection('userProfiles').doc(uid);

  DocumentReference<Map<String, dynamic>> _handleDoc(String handle) =>
      _db.collection('handles').doc(handle);

  /// Prüft, ob ein Handle (Format geprüft) frei ist. Liest `handles/{h}`.
  /// Liefert `null`, wenn frei – sonst die belegende UID.
  Future<String?> getHandleOwner(String rawHandle) async {
    if (!FirebaseBootstrap.isAvailable) return null;
    final h = rawHandle.trim().toLowerCase();
    if (h.isEmpty) return null;
    try {
      final snap = await _handleDoc(h).get();
      if (!snap.exists) return null;
      return snap.data()?['uid'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Convenience: True wenn frei oder bereits dem aufrufenden User gehört.
  Future<bool> isHandleAvailable(String rawHandle) async {
    final me = FirebaseAuth.instance.currentUser;
    final owner = await getHandleOwner(rawHandle);
    return owner == null || owner == me?.uid;
  }

  /// Reserviert ein Handle für den eingeloggten User über die Cloud Function
  /// `claimHandle`. Atomar serverseitig (alter Handle wird freigegeben).
  /// Wirft eine `Exception` mit lesbarer Message bei Fehler.
  Future<void> claimHandle(String rawHandle) async {
    if (!FirebaseBootstrap.isAvailable) {
      throw Exception('Keine Verbindung zum Server.');
    }
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw Exception('Nicht angemeldet.');
    final h = rawHandle.trim().toLowerCase();
    final formatErr = validateHandleFormat(h);
    if (formatErr != null) throw Exception(formatErr.message);

    final functions = FirebaseFunctions.instanceFor(
      app: Firebase.app(),
      region: 'europe-west3',
    );
    try {
      await functions.httpsCallable('claimHandle').call({'handle': h});
    } on FirebaseFunctionsException catch (e) {
      // Server liefert lesbare Messages über `code`.
      switch (e.code) {
        case 'already-exists':
          throw Exception('Dieser Benutzername ist bereits vergeben.');
        case 'invalid-argument':
          throw Exception(e.message ?? 'Ungültiger Benutzername.');
        case 'failed-precondition':
          throw Exception(
            e.message ??
                'Du kannst deinen Benutzernamen nur alle 30 Tage ändern.',
          );
        case 'unauthenticated':
          throw Exception('Bitte erneut anmelden.');
        default:
          throw Exception(e.message ?? 'Fehler beim Speichern.');
      }
    }
  }

  /// Löst ein Handle zur UID auf (z. B. für `@handle`-Mentions später).
  Future<String?> resolveHandle(String rawHandle) async {
    return getHandleOwner(rawHandle);
  }

  /// Stream eines Profils — `null`, wenn noch keins existiert.
  Stream<UserProfile?> watchProfile(String uid) {
    if (!FirebaseBootstrap.isAvailable) return const Stream.empty();
    return _profileDoc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return UserProfile.fromMap(uid, snap.data() ?? const {});
    });
  }

  /// Einmaliges Lesen.
  Future<UserProfile?> getProfile(String uid) async {
    if (!FirebaseBootstrap.isAvailable) return null;
    final snap = await _profileDoc(uid).get();
    if (!snap.exists) return null;
    return UserProfile.fromMap(uid, snap.data() ?? const {});
  }

  /// Stellt sicher, dass für den eingeloggten User ein Profil-Doc existiert
  /// und der gespiegelte `displayName`/`photoUrl` aktuell ist.
  ///
  /// Wird beim App-Start nach erfolgreicher Auth aufgerufen, damit Bestands-
  /// User sofort von anderen gefunden werden können — und damit Name/Avatar
  /// in fremden Profilen nicht veralten, wenn der User sie über
  /// `/profile/edit` ändert.
  Future<void> ensureMyProfileExists() async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = _profileDoc(user.uid);
    try {
      final snap = await ref.get();
      if (snap.exists) {
        final data = snap.data() ?? const {};
        final mirrorChanged =
            data['displayName'] != user.displayName ||
            data['photoUrl'] != user.photoURL;
        if (!mirrorChanged) return;
        await ref.set({
          'displayName': user.displayName,
          'photoUrl': user.photoURL,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }
      await ref.set({
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
        'steckbrief': null,
        'targetSpecies': const <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort — Offline / Permission-Race-Conditions schweigend
      // schlucken; nächster App-Start versucht es erneut.
    }
  }

  /// Speichert/erstellt das eigene Profil. Nur der eingeloggte User darf
  /// sein eigenes Profil schreiben (Firestore-Rules).
  Future<void> upsertOwnProfile({
    required String? displayName,
    required String? photoUrl,
    required String? steckbrief,
    required List<FishSpecies> targetSpecies,
  }) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final trimmed = steckbrief?.trim();
    final cleanSteckbrief = (trimmed == null || trimmed.isEmpty)
        ? null
        : (trimmed.length > _maxSteckbrief
              ? trimmed.substring(0, _maxSteckbrief)
              : trimmed);
    final clampedSpecies = targetSpecies
        .toSet()
        .take(_maxTargetSpecies)
        .toList();

    final ref = _profileDoc(user.uid);
    final exists = (await ref.get()).exists;
    final data = <String, dynamic>{
      'displayName': displayName,
      'photoUrl': photoUrl,
      'steckbrief': cleanSteckbrief,
      'targetSpecies': clampedSpecies.map((e) => e.name).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!exists) 'createdAt': FieldValue.serverTimestamp(),
    };
    await ref.set(data, SetOptions(merge: true));
  }

  /// Partial-Update: schreibt nur Anzeigename, Foto-URL und Steckbrief —
  /// `targetSpecies` und `handle` bleiben unangetastet. Wird vom
  /// Profile-Setup-Screen genutzt, damit ein Re-Setup keine bereits
  /// gewählten Zielfische überschreibt.
  Future<void> updateProfileBasics({
    required String? displayName,
    required String? photoUrl,
    required String? steckbrief,
  }) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final trimmed = steckbrief?.trim();
    final cleanSteckbrief = (trimmed == null || trimmed.isEmpty)
        ? null
        : (trimmed.length > _maxSteckbrief
              ? trimmed.substring(0, _maxSteckbrief)
              : trimmed);

    final ref = _profileDoc(user.uid);
    final exists = (await ref.get()).exists;
    await ref.set({
      'displayName': displayName,
      'photoUrl': photoUrl,
      'steckbrief': cleanSteckbrief,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream: folge ich `targetUid`?
  Stream<bool> watchIsFollowing(String targetUid) {
    if (!FirebaseBootstrap.isAvailable) return Stream.value(false);
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid == targetUid) return Stream.value(false);
    return _profileDoc(
      targetUid,
    ).collection('followers').doc(me.uid).snapshots().map((s) => s.exists);
  }

  /// Folgt `targetUid` oder entfolgt — atomar via Batch.
  /// Wirft `StateError('blocked')`, wenn `targetUid` in der Block-Liste ist.
  /// Liefert `true`, wenn jetzt gefolgt wird, `false` wenn entfolgt.
  Future<bool> toggleFollow(
    String targetUid, {
    Set<String> blockedUids = const {},
  }) async {
    if (!FirebaseBootstrap.isAvailable) return false;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid == targetUid) return false;
    if (blockedUids.contains(targetUid)) {
      throw StateError('blocked');
    }

    final followerDoc = _profileDoc(
      targetUid,
    ).collection('followers').doc(me.uid);
    final followingDoc = _profileDoc(
      me.uid,
    ).collection('following').doc(targetUid);

    final exists = (await followerDoc.get()).exists;
    final batch = _db.batch();
    if (exists) {
      batch.delete(followerDoc);
      batch.delete(followingDoc);
    } else {
      final now = FieldValue.serverTimestamp();
      batch.set(followerDoc, {'createdAt': now});
      batch.set(followingDoc, {'createdAt': now});
    }
    await batch.commit();
    return !exists;
  }

  /// Stream der UIDs, denen `uid` folgt.
  Stream<Set<String>> watchFollowing(String uid) {
    if (!FirebaseBootstrap.isAvailable) return Stream.value(const <String>{});
    return _profileDoc(uid)
        .collection('following')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  /// Stream der Follower-UIDs eines Users.
  Stream<Set<String>> watchFollowers(String uid) {
    if (!FirebaseBootstrap.isAvailable) return Stream.value(const <String>{});
    return _profileDoc(uid)
        .collection('followers')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  /// Liefert Follower-Anzahl via `count()`-Aggregation. Ein Read pro Aufruf,
  /// unabhängig von der tatsächlichen Anzahl der Follower.
  Future<int> getFollowerCount(String uid) async {
    if (!FirebaseBootstrap.isAvailable) return 0;
    try {
      final agg = await _profileDoc(uid).collection('followers').count().get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Liefert Following-Anzahl via `count()`-Aggregation.
  Future<int> getFollowingCount(String uid) async {
    if (!FirebaseBootstrap.isAvailable) return 0;
    try {
      final agg = await _profileDoc(uid).collection('following').count().get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
