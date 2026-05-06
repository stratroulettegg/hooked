import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../utils/image_compression.dart';
import 'firebase_bootstrap.dart';

/// Ergebnis eines Auth-Versuchs.
class AuthResult {
  final User? user;
  final String? errorCode;
  final String? errorMessage;

  const AuthResult.success(this.user) : errorCode = null, errorMessage = null;
  const AuthResult.failure(this.errorCode, this.errorMessage) : user = null;

  bool get isSuccess => user != null;
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
      final cred = await _auth.signInWithCredential(credential);
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

      final oauth = OAuthProvider(
        'apple.com',
      ).credential(idToken: appleCred.identityToken, rawNonce: rawNonce);
      final cred = await _auth.signInWithCredential(oauth);

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
      return AuthResult.failure(e.code.name, e.message);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(e.code, _readableMessage(e));
    } catch (e) {
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
        await ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
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
    } catch (_) {}
    await _auth.signOut();
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
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('deleteUserAccount');
      await callable.call<Map<String, dynamic>>();
      // Auth-User ist serverseitig schon weg → lokale Session beenden.
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
      try {
        await _auth.signOut();
      } catch (_) {}
      return const AuthResult.success(null);
    } on FirebaseFunctionsException catch (e) {
      return AuthResult.failure(e.code, e.message ?? 'Account-Löschung fehlgeschlagen.');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(e.code, _readableMessage(e));
    } catch (e) {
      return AuthResult.failure('unknown', e.toString());
    }
  }

  // \u2500\u2500\u2500 Helpers \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

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
        return 'Bitte melde dich zur Bestaetigung noch einmal an.';
      case 'too-many-requests':
        return 'Zu viele Versuche — bitte spaeter erneut versuchen.';
      default:
        return e.message ?? e.code;
    }
  }
}
