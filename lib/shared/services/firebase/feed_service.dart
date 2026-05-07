import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../models/catch_entry.dart';
import '../../models/fishing_spot.dart';
import '../../utils/image_compression.dart';
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
  final bool hidden;

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
    this.hidden = false,
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
      hidden: map['hidden'] == true,
    );
  }
}

/// Ein Kommentar zu einem Feed-Post. `parentId` ist gesetzt, wenn der
/// Kommentar eine Antwort auf einen anderen Kommentar ist.
class FeedComment {
  final String id;
  final String userId;
  final String? userName;
  final String? userPhotoUrl;
  final String text;
  final DateTime createdAt;
  final String? parentId;

  const FeedComment({
    required this.id,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    required this.text,
    required this.createdAt,
    this.parentId,
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
      parentId: map['parentId'] as String?,
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
    // Community-Posts erfordern ein eigenes Foto. Ohne hochladbares Bild
    // wird der Post stillschweigend nicht ver\u00f6ffentlicht \u2014 die UI
    // verhindert das bereits, hier ist es eine letzte Sicherung gegen
    // Race-Conditions (z.\u202fB. Datei in der Zwischenzeit gel\u00f6scht).
    if (file == null) return;
    try {
      // Vor Upload auf max 1920px / q=82 herunterskalieren — spart bis zu
      // 70% Storage-Egress, ohne Sichtbarkeitsverlust auf Mobile-Displays.
      final bytes = await compressForUpload(file, maxEdge: 1920, quality: 82);
      final ref = FirebaseStorage.instance.ref().child(
        'feedPhotos/${user.uid}/${entry.id}.jpg',
      );
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      photoUrl = await ref.getDownloadURL();
    } catch (e) {
      // Upload-Fehler nicht den ganzen Publish kippen lassen.
      // photoUrl bleibt null; Eintrag wird ohne Bild ver\u00f6ffentlicht.
      // Logging \u00fcbernimmt der Aufrufer.
      rethrow;
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
    } catch (e) {
      debugPrint('feed delete doc: $e');
    }

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
            (snap) =>
                snap.docs.map((d) => FeedPost.fromMap(d.id, d.data())).toList(),
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
  /// `parentId` markiert den Kommentar als Antwort auf einen anderen.
  Future<void> addComment(
    String postId,
    String text, {
    String? parentId,
  }) async {
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
      if (parentId != null) 'parentId': parentId,
    });
    batch.update(postRef, {'commentCount': FieldValue.increment(1)});
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
    batch.update(postRef, {'commentCount': FieldValue.increment(-1)});
    try {
      await batch.commit();
    } catch (_) {
      // Best-effort: wenn Counter-Update scheitert, ist der Kommentar
      // dennoch gelöscht.
    }
  }

  /// Stream der eigenen Feed-Posts (alle, ohne Limit). Wird im Hintergrund
  /// aktiv abonniert, damit "Meine Fänge" Live-Counter zeigt.
  Stream<List<FeedPost>> watchMyFeed() {
    if (!FirebaseBootstrap.isAvailable) {
      return const Stream<List<FeedPost>>.empty();
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<FeedPost>>.value(const []);
      }
      return _db
          .collection('feed')
          .where('userId', isEqualTo: user.uid)
          .snapshots()
          .map(
            (snap) =>
                snap.docs.map((d) => FeedPost.fromMap(d.id, d.data())).toList(),
          )
          .handleError((Object e, StackTrace st) {});
    });
  }

  /// Stream der Posts eines bestimmten Users (z. B. für Public-Profile).
  Stream<List<FeedPost>> watchUserFeed(String userId, {int limit = 60}) {
    if (!FirebaseBootstrap.isAvailable) {
      return const Stream<List<FeedPost>>.empty();
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<FeedPost>>.value(const []);
      }
      return _db
          .collection('feed')
          .where('userId', isEqualTo: userId)
          .snapshots()
          .map((snap) {
            final list =
                snap.docs
                    .map((d) => FeedPost.fromMap(d.id, d.data()))
                    .where((p) => !p.hidden)
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list.take(limit).toList();
          })
          .handleError((Object e, StackTrace st) {});
    });
  }

  /// Stream der neuen Posts gefolgter User seit `since`. Wird für die
  /// Bell-Badge in der AppBar verwendet.
  ///
  /// Nutzt Firestores `whereIn` (max 30 IDs pro Query) — bei mehr Follows
  /// werden parallele Sub-Queries angestoßen und client-seitig gemerged.
  /// Das ist linear in der Anzahl der 30er-Chunks: bis ~150 Follows
  /// (=5 Sub-Queries) bleibt das problemlos. Für virale Power-User wäre
  /// ein Cloud-Function-Fanout das nächste Upgrade.
  Stream<List<FeedPost>> watchFollowingFeedSince(
    Set<String> followingUids,
    DateTime since, {
    int limitPerChunk = 30,
  }) {
    if (!FirebaseBootstrap.isAvailable || followingUids.isEmpty) {
      return Stream<List<FeedPost>>.value(const []);
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<FeedPost>>.value(const []);
      }
      // 30er-Chunks (Firestore whereIn-Limit).
      final chunks = <List<String>>[];
      final list = followingUids.where((u) => u != user.uid).toList();
      for (var i = 0; i < list.length; i += 30) {
        chunks.add(list.sublist(i, (i + 30).clamp(0, list.length)));
      }
      if (chunks.isEmpty) {
        return Stream<List<FeedPost>>.value(const []);
      }
      // Mehrere Streams in einem Multi-Stream zusammenfassen — wir
      // halten je Chunk den letzten Snapshot und mergen bei Updates.
      final controller = StreamController<List<FeedPost>>.broadcast();
      final latest = List<List<FeedPost>>.filled(chunks.length, const []);
      final subs = <StreamSubscription>[];
      void emit() {
        final merged = <String, FeedPost>{};
        for (final list in latest) {
          for (final p in list) {
            if (p.hidden) continue;
            if (!p.createdAt.isAfter(since)) continue;
            merged[p.id] = p;
          }
        }
        final all = merged.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(all);
      }

      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final query = _db
            .collection('feed')
            .where('userId', whereIn: chunk)
            .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
            .orderBy('createdAt', descending: true)
            .limit(limitPerChunk);
        final sub = query.snapshots().listen(
          (snap) {
            latest[i] = snap.docs
                .map((d) => FeedPost.fromMap(d.id, d.data()))
                .toList();
            emit();
          },
          onError: (Object e, StackTrace st) {
            // Permission-denied bei Logout o.ä. — Chunk leer halten.
            latest[i] = const [];
            emit();
          },
        );
        subs.add(sub);
      }
      controller.onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };
      return controller.stream;
    });
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
