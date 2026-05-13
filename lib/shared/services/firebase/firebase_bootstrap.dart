import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Versucht Firebase zu initialisieren. Schl\u00e4gt die Initialisierung fehl
/// (z.\u00a0B. weil GoogleService-Info.plist bzw. google-services.json noch nicht
/// via `flutterfire configure` eingerichtet wurden), bleibt die App nutzbar
/// \u2014 Auth-/Cloud-Features werden dann ausgeblendet.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _available = false;
  static String? _initError;

  static bool get isAvailable => _available;
  static String? get initError => _initError;

  static Future<void> init() async {
    try {
      // Nutzt die nativen Plattform-Configs (GoogleService-Info.plist /
      // google-services.json), die `flutterfire configure` ablegt.
      await Firebase.initializeApp();
      _available = true;

      // App Check aktivieren \u2014 verhindert, dass Backends von au\u00dferhalb
      // unserer App angesprochen werden.
      // Debug-Builds nutzen den Debug-Provider; das gedruckte Token muss
      // einmalig in der Firebase-Console (App Check \u2192 Apps \u2192 Manage debug
      // tokens) registriert werden.
      // Release-Builds nutzen Play Integrity (Android) bzw. App Attest /
      // Device Check (iOS). Daf\u00fcr m\u00fcssen die Apps in der Firebase-Console
      // unter App Check registriert sein.
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kReleaseMode
              ? AndroidProvider.playIntegrity
              : AndroidProvider.debug,
          appleProvider: kReleaseMode
              ? AppleProvider.appAttest
              : AppleProvider.debug,
        );
      } catch (e) {
        // App Check-Aktivierung darf den App-Start nicht kippen.
        if (kDebugMode) {
          // ignore: avoid_print
          print('FirebaseAppCheck.activate failed: $e');
        }
      }
    } catch (e, st) {
      _available = false;
      _initError = e.toString();
      if (kDebugMode) {
        // ignore: avoid_print
        print('Firebase init failed (App l\u00e4uft offline weiter): $e\n$st');
      }
    }
  }

  /// Stellt sicher, dass *immer* ein Firebase-User eingeloggt ist — wenn
  /// nicht via Apple/Google/Email, dann anonym. So ist die lokale
  /// SQLite-DB ab Tag 1 user-scoped (verhindert Daten-Kontamination, wenn
  /// sich später ein zweiter Account auf demselben Gerät anmeldet).
  ///
  /// Anonyme User werden bei einer späteren echten Anmeldung via
  /// `linkWithCredential` aufgewertet — dabei bleibt die UID erhalten,
  /// sodass die DB-Datei ohne Migration weitergenutzt wird.
  static Future<User?> ensureSignedIn() async {
    if (!_available) return null;
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser;
    try {
      final cred = await auth.signInAnonymously();
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Auth] signed in anonymously: uid=${cred.user?.uid}');
      }
      return cred.user;
    } catch (e, st) {
      // Anonymous-Auth deaktiviert oder offline → App startet trotzdem,
      // aber ohne user-scoped DB. Datenintegrität bleibt gewahrt durch
      // den Fallback-Slot in main().
      if (kDebugMode) {
        // ignore: avoid_print
        print('signInAnonymously failed: $e\n$st');
      }
      return null;
    }
  }
}
