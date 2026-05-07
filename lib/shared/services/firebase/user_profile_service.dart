import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/catch_entry.dart';
import 'firebase_bootstrap.dart';

/// Öffentliches User-Profil — wird in `userProfiles/{uid}` gespeichert und
/// dient als Quelle für „Profil ansehen", Follow-Listen und Suche.
///
/// **Hinweis zu Followern**: Counter werden bewusst NICHT im Doc gespeichert
/// (Manipulationsschutz). Stats kommen via `count()`-Aggregation aus den
/// Subcollections `followers/` und `following/`.
class UserProfile {
  final String uid;
  final String? displayName;
  final String? photoUrl;
  final String? steckbrief;
  final List<FishSpecies> targetSpecies;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const UserProfile({
    required this.uid,
    this.displayName,
    this.photoUrl,
    this.steckbrief,
    this.targetSpecies = const [],
    this.updatedAt,
    this.createdAt,
  });

  factory UserProfile.empty(String uid) => UserProfile(uid: uid);

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    final speciesRaw =
        (map['targetSpecies'] as List?)?.cast<String>() ?? const [];
    DateTime? toDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return UserProfile(
      uid: uid,
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
    );
  }
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
