import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/user_progress.dart';
import '../../core/constants/app_constants.dart';

class UserRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  UserRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _auth = auth;

  String? get currentUserId => _auth.currentUser?.uid;

  // ── AppUser ────────────────────────────────────────────────────────────

  Future<AppUser?> getCurrentUser() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final doc =
        await _firestore.collection(AppConstants.colUsers).doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  Stream<AppUser?> watchCurrentUser() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? AppUser.fromFirestore(snap) : null);
  }

  Future<void> createUser(AppUser user) async {
    await _firestore
        .collection(AppConstants.colUsers)
        .doc(user.uid)
        .set(user.toMap());
  }

  Future<void> updateUser(AppUser user) async {
    await _firestore
        .collection(AppConstants.colUsers)
        .doc(user.uid)
        .update(user.toMap());
  }

  /// Fügt XP hinzu und prüft Level-Up atomisch per Transaction.
  Future<AppUser> addXp(int xp) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('No authenticated user');
    final ref = _firestore.collection(AppConstants.colUsers).doc(uid);

    return _firestore.runTransaction<AppUser>((tx) async {
      final snap = await tx.get(ref);
      final user = AppUser.fromFirestore(snap);
      final updated = user.copyWith(xp: user.xp + xp);
      tx.update(ref, {'xp': updated.xp});
      return updated;
    });
  }

  /// Streak aktualisieren: wenn letztes Login gestern, +1; heute, gleich; sonst reset.
  Future<void> updateStreak() async {
    final uid = currentUserId;
    if (uid == null) return;
    final ref = _firestore.collection(AppConstants.colUsers).doc(uid);

    await _firestore.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final user = AppUser.fromFirestore(snap);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastActive = user.lastActive != null
          ? DateTime(
              user.lastActive!.year,
              user.lastActive!.month,
              user.lastActive!.day,
            )
          : null;

      int newStreak = user.streak;
      if (lastActive == null) {
        newStreak = 1;
      } else if (today == lastActive) {
        return; // heute schon gezählt
      } else if (today.difference(lastActive).inDays == 1) {
        newStreak++;
      } else {
        newStreak = 1;
      }

      tx.update(ref, {
        'streak': newStreak,
        'last_active': Timestamp.now(),
      });
    });
  }

  // ── UserProgress ───────────────────────────────────────────────────────

  Future<Map<String, UserProgress>> getUserProgress(String bundesland) async {
    final uid = currentUserId;
    if (uid == null) return {};

    final snapshot = await _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .collection(AppConstants.colUserProgress)
        .where('bundesland', isEqualTo: bundesland)
        .get();

    return {
      for (final doc in snapshot.docs)
        doc.id: UserProgress.fromFirestore(doc),
    };
  }

  Future<void> saveProgress(UserProgress progress) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .collection(AppConstants.colUserProgress)
        .doc(progress.questionId)
        .set(progress.toMap(), SetOptions(merge: true));
  }

  Future<void> saveProgressBatch(List<UserProgress> progressList) async {
    final uid = currentUserId;
    if (uid == null) return;

    final batch = _firestore.batch();
    final base = _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .collection(AppConstants.colUserProgress);

    for (final p in progressList) {
      batch.set(base.doc(p.questionId), p.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
  }
}

// ── Riverpod-Provider ──────────────────────────────────────────────────────

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(userRepositoryProvider).watchCurrentUser();
});
