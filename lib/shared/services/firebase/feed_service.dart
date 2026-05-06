import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/catch_entry.dart';
import '../../models/fishing_spot.dart';
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
    final localPath = entry.photoPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        final ref = FirebaseStorage.instance.ref().child(
          'feedPhotos/${user.uid}/${entry.id}.jpg',
        );
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
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
    try {
      await _db.collection('feed').doc(catchId).delete();
    } catch (_) {}
    try {
      await FirebaseStorage.instance
          .ref()
          .child('feedPhotos/${user.uid}/$catchId.jpg')
          .delete();
    } catch (_) {
      // war evtl. nie hochgeladen
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
}
