import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';
import 'firebase_bootstrap.dart';

/// Globaler Riverpod-Einstiegspunkt f\u00fcr den Auth-Zustand.
///
/// Emittiert den aktuellen [User] (oder `null`, wenn nicht angemeldet bzw.
/// Firebase nicht konfiguriert ist).
final authStateProvider = StreamProvider<User?>((ref) {
  if (!FirebaseBootstrap.isAvailable) {
    return Stream<User?>.value(null);
  }
  return AuthService.instance.authStateChanges();
});

/// Bequemer Zugriff auf den aktuellen User ohne Stream-Boilerplate.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Liefert nur einen *echten* (nicht-anonymen) User. Nutze diesen Provider
/// überall dort, wo „angemeldet" wirklich „mit echtem Account" heißen soll
/// — z.B. Cloud-Sync-Gate, Login-Buttons, Public-Profile-Anzeigen.
///
/// Anonyme User entstehen automatisch beim App-Start (siehe
/// [FirebaseBootstrap.ensureSignedIn]), damit die lokale DB ab Tag 1
/// user-scoped ist. Sie sollen aber nicht als „eingeloggt" gelten.
final signedInUserProvider = Provider<User?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isAnonymous) return null;
  return user;
});

/// True, wenn Firebase initialisiert wurde (Cloud-Features verf\u00fcgbar).
final firebaseAvailableProvider = Provider<bool>((ref) {
  return FirebaseBootstrap.isAvailable;
});
