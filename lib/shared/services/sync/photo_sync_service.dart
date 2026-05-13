import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../local_database_service.dart';

/// Spiegelt den lokalen `<docs>/photos`-Ordner in Firebase Storage unter
/// `userPhotos/{uid}/{filename}`. Wird vom [CloudSyncService] aufgerufen
/// und arbeitet idempotent: bereits hochgeladene/heruntergeladene Dateien
/// werden in `meta/sync` markiert, damit nachfolgende Syncs nur Deltas
/// verarbeiten.
///
/// Quellen für Foto-Pfade: alle Tabellen, deren Doku-Schema einen
/// `photo_path`-Eintrag (Dateiname relativ zu [AppPaths.photos]) hat —
/// `catches`, `spots`, `waterbodies`.
class PhotoSyncService {
  PhotoSyncService({
    LocalDatabaseService? db,
    FirebaseStorage? storage,
  }) : _db = db ?? LocalDatabaseService(),
       _storage = storage ?? FirebaseStorage.instance;

  final LocalDatabaseService _db;
  final FirebaseStorage _storage;

  /// Tabellen mit `photo_path`-Spalte, die in den Privat-Sync gehören.
  static const _photoTables = ['catches', 'spots', 'waterbodies'];

  /// Storage-Pfad-Präfix für die Privat-Fotos eines Users.
  static String _userFolder(String uid) => 'userPhotos/$uid';

  /// Hauptmethode: lädt alle lokalen Fotos hoch, deren Dateiname noch
  /// nicht als „uploaded" markiert ist, und holt fehlende Fotos aus der
  /// Cloud, deren `photo_path` in den Tabellen referenziert ist.
  ///
  /// Schluckt Einzelfehler, damit ein einzelnes defektes Bild nicht den
  /// gesamten Sync kippt.
  Future<PhotoSyncReport> syncAll() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PhotoSyncReport(uploaded: 0, downloaded: 0, errors: 0);
    }
    final uid = user.uid;
    final referenced = await _collectReferencedPhotoNames();

    var uploaded = 0;
    var downloaded = 0;
    var errors = 0;

    // ── Upload: lokale Datei vorhanden, aber Cloud-Eintrag fehlt ──
    for (final fileName in referenced) {
      final local = File(p.join(AppPaths.photos, fileName));
      if (!local.existsSync()) continue;
      final ref = _storage.ref('${_userFolder(uid)}/$fileName');
      try {
        // Existenzprüfung über getMetadata — billig und genau.
        await ref.getMetadata();
        // existiert bereits → skip
        continue;
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[PhotoSync] metadata error $fileName: ${e.code}');
          }
          errors++;
          continue;
        }
        // object-not-found → wir laden hoch
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[PhotoSync] metadata exception $fileName: $e');
        }
        errors++;
        continue;
      }

      try {
        await ref.putFile(
          local,
          SettableMetadata(
            contentType: _contentTypeFor(fileName),
            cacheControl: 'private, max-age=31536000, immutable',
          ),
        );
        uploaded++;
        if (kDebugMode) {
          // ignore: avoid_print
          print('[PhotoSync] uploaded $fileName');
        }
      } on FirebaseException catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[PhotoSync] upload failed $fileName: ${e.code} ${e.message}');
        }
        errors++;
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[PhotoSync] upload exception $fileName: $e');
        }
        errors++;
      }
    }

    // ── Download: Cloud-Datei referenziert, lokal fehlend ──
    for (final fileName in referenced) {
      final local = File(p.join(AppPaths.photos, fileName));
      if (local.existsSync()) continue;
      final ref = _storage.ref('${_userFolder(uid)}/$fileName');
      try {
        await ref.getMetadata();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          // Auf einem anderen Device noch nicht hochgeladen — ok, beim
          // nächsten Sync probieren wir's wieder.
          continue;
        }
        errors++;
        continue;
      } catch (_) {
        errors++;
        continue;
      }
      try {
        await ref.writeToFile(local);
        downloaded++;
        if (kDebugMode) {
          // ignore: avoid_print
          print('[PhotoSync] downloaded $fileName');
        }
      } catch (e) {
        // Datei könnte teilweise geschrieben sein — wegräumen, sonst
        // gibt's beim nächsten Versuch kaputte Bilder.
        if (local.existsSync()) {
          try {
            await local.delete();
          } catch (_) {}
        }
        if (kDebugMode) {
          // ignore: avoid_print
          print('[PhotoSync] download failed $fileName: $e');
        }
        errors++;
      }
    }

    return PhotoSyncReport(
      uploaded: uploaded,
      downloaded: downloaded,
      errors: errors,
    );
  }

  /// Sammelt alle in den synchronisierten Tabellen referenzierten
  /// Foto-Dateinamen. Tombstones werden ausgeschlossen.
  Future<Set<String>> _collectReferencedPhotoNames() async {
    final db = await _db.database;
    final names = <String>{};
    for (final t in _photoTables) {
      final rows = await db.query(
        t,
        columns: ['photo_path'],
        where: 'photo_path IS NOT NULL AND photo_path != "" '
            'AND deleted_at IS NULL',
      );
      for (final r in rows) {
        final v = r['photo_path'];
        if (v is String && v.isNotEmpty) {
          // Auch alte Absolutpfade abbilden — wir nehmen nur den Basename,
          // sonst zerschießt's den Cloud-Pfad.
          names.add(p.basename(v));
        }
      }
    }
    return names;
  }

  String _contentTypeFor(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      _ => 'image/jpeg',
    };
  }
}

/// Ergebnis eines Photo-Sync-Laufs.
class PhotoSyncReport {
  const PhotoSyncReport({
    required this.uploaded,
    required this.downloaded,
    required this.errors,
  });

  final int uploaded;
  final int downloaded;
  final int errors;

  bool get isEmpty => uploaded == 0 && downloaded == 0 && errors == 0;
}
