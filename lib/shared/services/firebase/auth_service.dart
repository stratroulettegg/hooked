import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../utils/image_compression.dart';
import '../local_db_anchor.dart';
import 'firebase_bootstrap.dart';

/// Ergebnis eines Auth-Versuchs.
class AuthResult {
  final User? user;
  final String? errorCode;
  final String? errorMessage;

  const AuthResult.success(this.user) : errorCode = null, errorMessage = null;
  const AuthResult.failure(this.errorCode, this.errorMessage) : user = null;

  bool get isSuccess => errorCode == null;
}

/// Wrapper um FirebaseAuth mit den drei Providern Apple, Google, E-Mail.
///
/// Alle Methoden pr\u00fcfen [FirebaseBootstrap.isAvailable] und liefern eine
/// aussagekr\u00e4ftige Fehlermeldung, falls Firebase noch nicht konfiguriert ist.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<User?> authStateChanges() {
    if (!FirebaseBootstrap.isAvailable) return const Stream.empty();
    return _auth.authStateChanges();
  }

  User? get currentUser =>
      FirebaseBootstrap.isAvailable ? _auth.currentUser : null;

  // \u2500\u2500\u2500 Google \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  Future<AuthResult> signInWithGoogle() async {
    if (!FirebaseBootstrap.isAvailable) return _notConfigured();
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return const AuthResult.failure('cancelled', 'Anmeldung abgebrochen');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _signInOrLink(credential);
      return AuthResult.success(cred.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(e.code, _readableMessage(e));
    } catch (e) {
      return AuthResult.failure('unknown', e.toString());
    }
  }

  // \u2500\u2500\u2500 Apple \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  bool get isAppleSupported {
    return Platform.isIOS || Platform.isMacOS;
  }

  Future<AuthResult> signInWithApple() async {
    if (!FirebaseBootstrap.isAvailable) return _notConfigured();
    if (!isAppleSupported) {
      return const AuthResult.failure(
        'unsupported',
        'Apple Sign-In ist nur auf iOS/macOS verf\u00fcgbar.',
      );
    }
    try {
      // Nonce f\u00fcr Replay-Schutz; Firebase erwartet den rohen Nonce.
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCred = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauth = OAuthProvider('apple.com').credential(
        idToken: appleCred.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCred.authorizationCode,
      );
      final cred = await _signInOrLink(oauth);

      // Apple liefert den Namen nur beim allerersten Login \u2014 jetzt persistieren.
      final displayName = [
        appleCred.givenName,
        appleCred.familyName,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      if (displayName.isNotEmpty &&
          (cred.user?.displayName == null || cred.user!.displayName!.isEmpty)) {
        await cred.user?.updateDisplayName(displayName);
        await cred.user?.reload();
      }
      return AuthResult.success(_auth.currentUser);
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('Apple Sign-In failed: code=${e.code.name} msg=${e.message}');
      // canceled → still still rendern, sonst freundliche Meldung.
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthResult.failure('cancelled', 'Anmeldung abgebrochen.');
      }
      final friendly = switch (e.code) {
        AuthorizationErrorCode.notHandled =>
          'Apple konnte die Anmeldung nicht verarbeiten. Bitte später erneut versuchen.',
        AuthorizationErrorCode.failed =>
          'Apple-Anmeldung fehlgeschlagen. Stelle sicher, dass „Mit Apple anmelden" für diese App aktiviert ist (Entwickler-Konto + App-ID-Capability).',
        AuthorizationErrorCode.invalidResponse =>
          'Ungültige Antwort von Apple. Bitte erneut versuchen.',
        AuthorizationErrorCode.unknown =>
          'Apple-Anmeldung fehlgeschlagen (Code 1000). Häufige Ursachen: fehlendes Entitlement im Build, Apple-ID nicht eingerichtet oder Capability im Apple-Developer-Portal nicht aktiv.',
        _ => e.message,
      };
      return AuthResult.failure(e.code.name, friendly);
    } on FirebaseAuthException catch (e) {
      debugPrint('Apple→Firebase failed: code=${e.code} msg=${e.message}');
      return AuthResult.failure(e.code, _readableMessage(e));
    } catch (e, st) {
      debugPrint('Apple Sign-In unknown error: $e\n$st');
      return AuthResult.failure('unknown', e.toString());
    }
  }

  // ─── Profil bearbeiten ────────────────────────────────────────────────

  /// Aktualisiert Anzeigename und/oder Profilbild des aktuellen Users.
  /// Bild wird zu Firebase Storage unter `profilePhotos/{uid}.jpg` hochgeladen
  /// und die resultierende URL als `photoURL` im Auth-Profil gespeichert.
  Future<AuthResult> updateProfile({
    String? displayName,
    File? photoFile,
    bool removePhoto = false,
  }) async {
    if (!FirebaseBootstrap.isAvailable) return _notConfigured();
    final user = _auth.currentUser;
    if (user == null) {
      return const AuthResult.failure('no-user', 'Nicht angemeldet');
    }
    try {
      if (displayName != null) {
        final trimmed = displayName.trim();
        await user.updateDisplayName(trimmed.isEmpty ? null : trimmed);
      }
      if (photoFile != null) {
        // Profilbild auf 512px / q=85 reduzieren — reicht für Avatare,
        // spart Storage- und Egress-Kosten.
        final bytes = await compressForUpload(
          photoFile,
          maxEdge: 512,
          quality: 85,
        );
        final ref = FirebaseStorage.instance
            .ref()
            .child('profilePhotos')
            .child('${user.uid}.jpg');
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        final url = await ref.getDownloadURL();
        await user.updatePhotoURL(url);
      } else if (removePhoto) {
        try {
          await FirebaseStorage.instance
              .ref()
              .child('profilePhotos')
              .child('${user.uid}.jpg')
              .delete();
        } catch (_) {
          // war evtl. nie hochgeladen → ignorieren
        }
        await user.updatePhotoURL(null);
      }
      await user.reload();
      return AuthResult.success(_auth.currentUser);
    } on FirebaseException catch (e) {
      return AuthResult.failure(e.code, e.message ?? 'Unbekannter Fehler');
    } catch (e) {
      return AuthResult.failure('unknown', e.toString());
    }
  }

  // ─── Logout / Account löschen ─────────────────────────────────────────

  Future<void> signOut() async {
    if (!FirebaseBootstrap.isAvailable) return;
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('auth GoogleSignIn signOut: $e');
    }
    await _auth.signOut();
    // Bewusst KEIN signInAnonymously() hier — ein frischer Anon-Login
    // würde sofort einen neuen UID-DB-Slot aktivieren und damit die
    // lokal vorhandenen Daten des soeben abgemeldeten Users „verstecken"
    // (apex_<oldUid>.db ↔ apex_<neueUid>.db). Stattdessen bleibt der
    // letzte DB-Slot aktiv, lokale Fänge/Spots/Trips bleiben sichtbar
    // und beim erneuten Login mit demselben Account liefert Firebase
    // wieder die gleiche UID → DB matcht. Beim nächsten Cold-Start
    // legt `FirebaseBootstrap.ensureSignedIn()` ggf. eine neue anonyme
    // Session an.
  }

  /// Löscht den Account des aktuellen Users vollständig (DSGVO Art. 17 +
  /// Apple-Guideline 5.1.1(v)). Die Cloud-Function `deleteUserAccount`
  /// räumt erst alle Cloud-Daten (Feed-Posts, Kommentare, Storage-Fotos,
  /// Reports, SharedTrips, userMeta/userBlocks) ab und löscht dann den
  /// Auth-User per Admin SDK. Danach signt der Client lokal aus.
  Future<AuthResult> deleteAccount() async {
    if (!FirebaseBootstrap.isAvailable) return _notConfigured();
    final user = _auth.currentUser;
    if (user == null) {
      return const AuthResult.failure('no-user', 'Nicht angemeldet');
    }
    Object? caughtError;
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'europe-west3',
      ).httpsCallable('deleteUserAccount');
      await callable.call<Map<String, dynamic>>();
    } catch (e) {
      // Race-Condition: die Cloud-Function löscht den Auth-User
      // serverseitig, dadurch wird unser ID-Token ungültig BEVOR die
      // HTTP-Antwort durchkommt. Ergebnis: typischerweise
      // `unauthenticated` oder `internal`, obwohl serverseitig alles
      // erfolgreich war. Wir verifizieren unten per reload().
      caughtError = e;
    }

    // Verifizieren: existiert der User serverseitig noch?
    final gone = await _userIsGone(user);
    await _signOutLocal();
    // Nach erfolgreicher Löschung sofort eine neue anonyme Session
    // anlegen, damit die App nahtlos im Anon-Modus weiterläuft —
    // sonst bleibt der Auth-State auf `null` hängen, bis der User
    // die App neu startet.
    if (caughtError == null || gone) {
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        debugPrint('post-delete signInAnonymously failed: $e');
      }
      return const AuthResult.success(null);
    }

    if (caughtError is FirebaseFunctionsException) {
      return AuthResult.failure(
        caughtError.code,
        caughtError.message ?? 'Account-Löschung fehlgeschlagen.',
      );
    }
    if (caughtError is FirebaseAuthException) {
      return AuthResult.failure(
        caughtError.code,
        _readableMessage(caughtError),
      );
    }
    return AuthResult.failure('unknown', caughtError.toString());
  }

  /// Prüft via Token-Reload, ob der angegebene User serverseitig schon
  /// gelöscht ist. Gibt true zurück, wenn das Token nicht mehr gültig
  /// ist — egal aus welchem Grund. Konservativ: bei Netzwerkfehlern
  /// ebenfalls true, weil wir dann nichts Sinnvolles mehr beweisen
  /// können und der User-Pfad „Function lief, dann Netz weg" sonst
  /// fälschlich als Fehler endet.
  Future<bool> _userIsGone(User user) async {
    try {
      await user.reload();
      // reload erfolgreich → User existiert noch
      return false;
    } on FirebaseAuthException catch (e) {
      const goneCodes = {
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
        'user-disabled',
        'requires-recent-login',
      };
      // Token ungültig → Account ist serverseitig weg.
      return goneCodes.contains(e.code) || e.code.contains('token');
    } catch (_) {
      // Z.B. PlatformException ohne klaren Code: konservativ als
      // "Account vermutlich weg" einstufen, damit kein falscher
      // Fehler-SnackBar erscheint.
      return true;
    }
  }

  Future<void> _signOutLocal() async {
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('auth GoogleSignIn signOut (local): $e');
    }
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('auth FirebaseAuth signOut (local): $e');
    }
    // Bewusst KEIN signInAnonymously() hier: ein neuer Anon-Login würde
    // einen frischen UID-DB-Slot erzeugen und damit die lokal sichtbaren
    // Fänge/Spots/Trips des soeben abgemeldeten Users „verändern“ (es
    // wechselt auf einen leeren `apex_<neueUid>.db`). Beim nächsten
    // App-Start übernimmt `FirebaseBootstrap.ensureSignedIn()` das
    // Anlegen einer neuen anonymen Session.
  }

  // \u2500\u2500\u2500 Helpers \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  // \u2500\u2500\u2500 Helpers \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  /// Wertet eine anonyme Session per [User.linkWithCredential] zu einem
  /// echten Account auf — die UID bleibt erhalten, sodass die lokale
  /// `apex_<uid>.db` und der Photos-Ordner ohne Migration weitergenutzt
  /// werden können.
  ///
  /// Fällt auf `signInWithCredential` zurück, wenn:
  /// - kein anonymer User aktiv ist (regulärer Login),
  /// - der OAuth-Account bereits einer anderen Firebase-UID zugeordnet ist
  ///   (`credential-already-in-use`) — in dem Fall wird die anonyme
  ///   Session verworfen und mit dem bestehenden Account weitergearbeitet.
  ///   Die anonyme `apex_<oldUid>.db` bleibt auf dem Gerät liegen und
  ///   kann später per Merge-Wizard übernommen werden (Folge-PR).
  Future<UserCredential> _signInOrLink(AuthCredential credential) async {
    final current = _auth.currentUser;
    if (current != null && current.isAnonymous) {
      final anonUid = current.uid;
      try {
        return await current.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use' ||
            e.code == 'email-already-in-use' ||
            e.code == 'provider-already-linked') {
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[Auth] link failed (${e.code}) — '
              'falling back to signInWithCredential',
            );
          }
          // Wichtig: Anon-UID hier persistieren, BEVOR signInWithCredential
          // den Auth-State umschaltet. So bleibt die lokale Anon-DB nach
          // einem späteren Logout/Account-Delete erreichbar — der
          // Auth-Listener in main.dart kann sich nicht darauf verlassen,
          // dass er die Anon-UID rechtzeitig sieht (Stream-Race).
          try {
            await LocalDbAnchor.setPreviousAnonUid(anonUid);
          } catch (e) {
            debugPrint('setPreviousAnonUid failed: $e');
          }
          return await _auth.signInWithCredential(credential);
        }
        rethrow;
      }
    }
    return _auth.signInWithCredential(credential);
  }

  AuthResult _notConfigured() => const AuthResult.failure(
    'not-configured',
    'Cloud-Funktionen sind noch nicht eingerichtet. '
        'Bitte `flutterfire configure` ausf\u00fchren.',
  );

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _readableMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-disabled':
        return 'Dieser Account wurde deaktiviert.';
      case 'invalid-credential':
        return 'Anmeldedaten ungültig.';
      case 'network-request-failed':
        return 'Keine Internetverbindung.';
      case 'requires-recent-login':
        return 'Bitte melde dich zur Bestätigung noch einmal an.';
      case 'too-many-requests':
        return 'Zu viele Versuche — bitte später erneut versuchen.';
      default:
        return e.message ?? e.code;
    }
  }
}
