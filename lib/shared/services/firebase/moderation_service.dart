import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_bootstrap.dart';

/// Art des gemeldeten Objekts.
enum ReportTargetType { post, comment, user }

/// Service für Community-Moderation: Reports und Block-Listen.
///
/// Schema:
///   /reports/{auto}      —  unveränderliche Report-Dokumente (admin-only)
///   /userBlocks/{uid}    —  { blocked: [uid1, uid2, ...] } pro Nutzer
///
/// Reports werden client-seitig nur geschrieben; ausgewertet wird in der
/// Firebase Console (siehe firestore.rules → /reports/{reportId}).
class ModerationService {
  ModerationService({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  static const String databaseId = 'default';

  FirebaseFirestore get _db {
    return _firestore ??
        FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: databaseId,
        );
  }

  // ── Reports ────────────────────────────────────────────────────────────

  /// Meldet einen Feed-Post.
  Future<void> reportPost({
    required String postId,
    required String targetUid,
    required String reason,
  }) {
    return _createReport(
      targetType: ReportTargetType.post,
      targetUid: targetUid,
      reason: reason,
      extra: {'postId': postId},
    );
  }

  /// Meldet einen Kommentar zu einem Feed-Post.
  Future<void> reportComment({
    required String postId,
    required String commentId,
    required String targetUid,
    required String reason,
  }) {
    return _createReport(
      targetType: ReportTargetType.comment,
      targetUid: targetUid,
      reason: reason,
      extra: {'postId': postId, 'commentId': commentId},
    );
  }

  /// Meldet einen Nutzer (z. B. aus einer Profilansicht heraus).
  Future<void> reportUser({required String targetUid, required String reason}) {
    return _createReport(
      targetType: ReportTargetType.user,
      targetUid: targetUid,
      reason: reason,
    );
  }

  Future<void> _createReport({
    required ReportTargetType targetType,
    required String targetUid,
    required String reason,
    Map<String, Object?> extra = const {},
  }) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Bitte zuerst anmelden.');
    }
    // Defensiv: Maximallänge für `reason` erzwingen — die Rules
    // begrenzen ohnehin auf < 500 Zeichen, hier kürzen wir freundlich.
    final trimmed = reason.trim();
    final clipped = trimmed.length > 480
        ? '${trimmed.substring(0, 480)}…'
        : trimmed;

    await _db.collection('reports').add({
      'reporterUid': user.uid,
      'targetType': targetType.name,
      'targetUid': targetUid,
      'reason': clipped,
      'createdAt': FieldValue.serverTimestamp(),
      ...extra,
    });
  }

  // ── Block-Liste ────────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _myBlockDoc(String uid) =>
      _db.collection('userBlocks').doc(uid);

  /// Stream der UIDs, die der eingeloggte Nutzer blockiert hat. Reagiert
  /// live auf Auth-Wechsel; ohne Login wird ein leeres Set gestreamt.
  Stream<Set<String>> watchBlockedUids() {
    if (!FirebaseBootstrap.isAvailable) {
      return Stream<Set<String>>.value(const <String>{});
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<Set<String>>.value(const <String>{});
      }
      return _myBlockDoc(user.uid)
          .snapshots()
          .map((snap) {
            final list =
                (snap.data()?['blocked'] as List?)?.cast<String>() ??
                const <String>[];
            return list.toSet();
          })
          .handleError((Object _, StackTrace __) {});
    });
  }

  /// Blockiert den angegebenen Nutzer (idempotent).
  Future<void> blockUser(String targetUid) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (targetUid == user.uid) return; // sich selbst blocken ist sinnlos
    await _myBlockDoc(user.uid).set({
      'blocked': FieldValue.arrayUnion([targetUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Hebt den Block für den angegebenen Nutzer auf (idempotent).
  Future<void> unblockUser(String targetUid) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _myBlockDoc(user.uid).set({
      'blocked': FieldValue.arrayRemove([targetUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  // \u2500\u2500 Rate-Limit-Hinweise (vom Server gesetzt) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  /// Stream der Rate-Limit-Hinweise f\u00fcr den eingeloggten User.
  /// Liefert (kind, atMs) sobald der Server das Limit f\u00fcr den User
  /// blockiert hat. Wird vom Client genutzt, um eine Snackbar
  /// anzuzeigen.
  Stream<RateLimitHit?> watchRateLimitHits() {
    if (!FirebaseBootstrap.isAvailable) {
      return Stream<RateLimitHit?>.value(null);
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream<RateLimitHit?>.value(null);
      return _db
          .collection('userMeta')
          .doc(user.uid)
          .snapshots()
          .map<RateLimitHit?>((snap) {
            final data = snap.data();
            if (data == null) return null;
            final kind = data['lastBlockedKind'] as String?;
            final ts = data['lastBlockedAt'];
            if (kind == null || ts is! Timestamp) return null;
            return RateLimitHit(kind: kind, at: ts.toDate());
          })
          .handleError((Object _, StackTrace __) {});
    });
  }
}

/// Server-seitiger Rate-Limit-Treffer (siehe Cloud Functions).
class RateLimitHit {
  final String kind; // 'posts' | 'comments' | 'reports'
  final DateTime at;
  const RateLimitHit({required this.kind, required this.at});
}
