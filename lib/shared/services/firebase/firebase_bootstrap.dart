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
    } catch (e, st) {
      _available = false;
      _initError = e.toString();
      if (kDebugMode) {
        // ignore: avoid_print
        print('Firebase init failed (App l\u00e4uft offline weiter): $e\n$st');
      }
    }
  }
}
