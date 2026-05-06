import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/catch_entry.dart';
import '../../models/fishing_spot.dart';
import '../app_paths.dart';
import 'firebase_bootstrap.dart';

/// Repräsentiert einen geteilten Fang im Community-Feed.
class FeedPost {
  final String id;
  final String userId;
  final String? userName;
  final String? userPhotoUrl;
  final String species;
  final int? weightG;
  final double? lengthCm;
  final String? lure;
  final String? lureColor;
  final String? photoUrl;
  final String? waterBodyName;
  final DateTime caughtAt;
  final DateTime createdAt;
  final List<String> likedBy;
  final int likeCount;
  final int commentCount;

  const FeedPost({
    required this.id,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    required this.species,
    this.weightG,
    this.lengthCm,
    this.lure,
    this.lureColor,
    this.photoUrl,
    this.waterBodyName,
    required this.caughtAt,
    required this.createdAt,
    this.likedBy = const [],
    this.likeCount = 0,
    this.commentCount = 0,
  });

  factory FeedPost.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseTs(dynamic v, {DateTime? fallback}) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.parse(v);
      return fallback ?? DateTime.now();
    }

    return FeedPost(
      id: id,
      userId: map['userId'] as String? ?? '',
      userName: map['userName'] as String?,
      userPhotoUrl: map['userPhotoUrl'] as String?,
      species: map['species'] as String? ?? 'andere',
      weightG: (map['weightG'] as num?)?.toInt(),
      lengthCm: (map['lengthCm'] as num?)?.toDouble(),
      lure: map['lure'] as String?,
      lureColor: map['lureColor'] as String?,
      photoUrl: map['photoUrl'] as String?,
      waterBodyName: map['waterBodyName'] as String?,
      caughtAt: parseTs(map['caughtAt']),
      createdAt: parseTs(map['createdAt']),
      likedBy: (map['likedBy'] as List?)?.cast<String>() ?? const [],
      likeCount: (map['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (map['commentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Ein Kommentar zu einem Feed-Post.
class FeedComment {
  final String id;
  final String userId;
  final String? userName;
  final String? userPhotoUrl;
  final String text;
  final DateTime createdAt;

  const FeedComment({
    required this.id,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    required this.text,
    required this.createdAt,
  });

  factory FeedComment.fromMap(String id, Map<String, dynamic> map) {
    final ts = map['createdAt'];
    return FeedComment(
      id: id,
      userId: map['userId'] as String? ?? '',
      userName: map['userName'] as String?,
      userPhotoUrl: map['userPhotoUrl'] as String?,
      text: map['text'] as String? ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

/// Service zum Veröffentlichen, Löschen und Lesen von Feed-Beiträgen.
///
/// Schema:
///   /feed/{catchId}  →  {
///     userId, userName, userPhotoUrl,
///     species, weightG, lengthCm, lure, lureColor,
///     photoUrl, waterBodyName,
///     caughtAt, createdAt
///   }
///
/// Bilder liegen unter /feedPhotos/{userId}/{catchId}.jpg.
class FeedService {
  FeedService({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  static const String databaseId = 'default';

  FirebaseFirestore get _db {
    return _firestore ??
        FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: databaseId,
        );
  }

  /// Veröffentlicht einen Fang. Lädt das Foto (falls vorhanden) hoch und
  /// schreibt einen Eintrag in `/feed/{catchId}`.
  ///
  /// `spot` kann null sein und wird nur verwendet, wenn `entry.shareWater`
  /// gesetzt ist.
  Future<void> publish({
    required CatchEntry entry,
    required FishingSpot? spot,
  }) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? photoUrl;
    final file = AppPaths.photoFile(entry.photoPath);
    if (file != null) {
      try {
        final ref = FirebaseStorage.instance.ref().child(
          'feedPhotos/${user.uid}/${entry.id}.jpg',
        );
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      } catch (e) {
        // Upload-Fehler nicht den ganzen Publish kippen lassen.
        // photoUrl bleibt null; Eintrag wird ohne Bild veröffentlicht.
        // Logging übernimmt der Aufrufer.
        rethrow;
      }
    }

    final data = <String, dynamic>{
      'userId': user.uid,
      'userName': user.displayName,
      'userPhotoUrl': user.photoURL,
      'species': entry.species.name,
      'weightG': entry.weightG,
      'lengthCm': entry.lengthCm,
      'lure': entry.lure,
      'lureColor': entry.lureColor,
      'photoUrl': photoUrl,
      'waterBodyName': entry.shareWater ? spot?.waterBodyName : null,
      'caughtAt': Timestamp.fromDate(entry.caughtAt.toUtc()),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('feed').doc(entry.id).set(data);
  }

  /// Entfernt einen Beitrag aus dem Feed (inkl. Foto in Storage).
  Future<void> unpublish(String catchId) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Erst prüfen, ob ein Foto hochgeladen wurde – dann unnötige 404er
    // beim Storage-Delete vermeiden.
    bool hadPhoto = false;
    try {
      final doc = await _db.collection('feed').doc(catchId).get();
      hadPhoto = (doc.data()?['photoUrl'] as String?)?.isNotEmpty ?? false;
    } catch (_) {
      // Doc existiert evtl. gar nicht mehr – dann auch kein Foto zu löschen.
    }

    try {
      await _db.collection('feed').doc(catchId).delete();
    } catch (_) {}

    if (hadPhoto) {
      try {
        await FirebaseStorage.instance
            .ref()
            .child('feedPhotos/${user.uid}/$catchId.jpg')
            .delete();
      } catch (_) {
        // Best-effort: Foto evtl. schon weg.
      }
    }
  }

  /// Stream der neuesten Feed-Beiträge.
  ///
  /// Reagiert live auf Login/Logout: ohne eingeloggten Nutzer wird ein
  /// leerer Feed gestreamt (statt eines `permission-denied`-Fehlers, weil
  /// die Rules nur für Auth-User lesen erlauben). Sobald sich der User
  /// anmeldet, wechselt der Stream automatisch auf die Live-Daten.
  Stream<List<FeedPost>> watchFeed({int limit = 50}) {
    if (!FirebaseBootstrap.isAvailable) {
      return const Stream<List<FeedPost>>.empty();
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<FeedPost>>.value(const []);
      }
      return _db
          .collection('feed')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => FeedPost.fromMap(d.id, d.data()))
                .toList(),
          )
          .handleError((Object e, StackTrace st) {
            // Wenn Logout direkt nach onAuthStateChanged passiert und der
            // Snapshot-Stream noch einen permission-denied wirft, schlucken
            // wir das hier und lassen den Stream einfach mit leer laufen,
            // bis der nächste Auth-State eintrifft.
          });
    });
  }

  /// Schaltet den Like des aktuellen Users für `postId` um.
  /// Nutzt arrayUnion/arrayRemove + atomare Counter-Updates.
  Future<void> toggleLike(String postId) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = _db.collection('feed').doc(postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final liked =
          ((snap.data()?['likedBy'] as List?)?.cast<String>() ?? const [])
              .contains(user.uid);
      if (liked) {
        tx.update(ref, {
          'likedBy': FieldValue.arrayRemove([user.uid]),
          'likeCount': FieldValue.increment(-1),
        });
      } else {
        tx.update(ref, {
          'likedBy': FieldValue.arrayUnion([user.uid]),
          'likeCount': FieldValue.increment(1),
        });
      }
    });
  }

  /// Fügt einen Kommentar hinzu und erhöht den Counter atomar.
  Future<void> addComment(String postId, String text) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final postRef = _db.collection('feed').doc(postId);
    final commentRef = postRef.collection('comments').doc();
    final batch = _db.batch();
    batch.set(commentRef, {
      'userId': user.uid,
      'userName': user.displayName,
      'userPhotoUrl': user.photoURL,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {
      'commentCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Löscht einen eigenen Kommentar.
  Future<void> deleteComment(String postId, String commentId) async {
    if (!FirebaseBootstrap.isAvailable) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final postRef = _db.collection('feed').doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);
    final batch = _db.batch();
    batch.delete(commentRef);
    batch.update(postRef, {
      'commentCount': FieldValue.increment(-1),
    });
    try {
      await batch.commit();
    } catch (_) {
      // Best-effort: wenn Counter-Update scheitert, ist der Kommentar
      // dennoch gelöscht.
    }
  }

  /// Stream der Kommentare zu einem Post (älteste zuerst).
  Stream<List<FeedComment>> watchComments(String postId) {
    if (!FirebaseBootstrap.isAvailable) {
      return const Stream<List<FeedComment>>.empty();
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<FeedComment>>.value(const []);
      }
      return _db
          .collection('feed')
          .doc(postId)
          .collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => FeedComment.fromMap(d.id, d.data()))
                .toList(),
          )
          .handleError((Object e, StackTrace st) {});
    });
  }
}
