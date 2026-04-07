import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import 'user_repository.dart';

class AuthService {
  final FirebaseAuth _auth;
  final UserRepository _userRepository;

  AuthService({
    required FirebaseAuth auth,
    required UserRepository userRepository,
  })  : _auth = auth,
        _userRepository = userRepository;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Anonymes Login für neue Nutzer ohne Account.
  Future<UserCredential> signInAnonymously() async {
    return _auth.signInAnonymously();
  }

  /// E-Mail/Passwort-Registrierung + AppUser in Firestore anlegen.
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    required String bundesland,
    required int dailyGoalMinutes,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;

    final user = AppUser(
      uid: uid,
      email: email,
      bundesland: bundesland,
      dailyGoalMinutes: dailyGoalMinutes,
    );
    await _userRepository.createUser(user);
    await _userRepository.updateStreak();
    return user;
  }

  /// E-Mail/Passwort-Login.
  Future<AppUser?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _userRepository.updateStreak();
    return _userRepository.getCurrentUser();
  }

  /// Anonymen Account mit E-Mail/Passwort verknüpfen (Upgrade).
  Future<AppUser> linkAnonymousWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final linked =
        await _auth.currentUser!.linkWithCredential(credential);
    final uid = linked.user!.uid;

    final existingUser = await _userRepository.getCurrentUser();
    if (existingUser != null) {
      final updated = existingUser.copyWith();
      await _userRepository.updateUser(
        AppUser(
          uid: uid,
          email: email,
          bundesland: existingUser.bundesland,
          xp: existingUser.xp,
          streak: existingUser.streak,
          lastActive: existingUser.lastActive,
          isPremium: existingUser.isPremium,
          examDate: existingUser.examDate,
          dailyGoalMinutes: existingUser.dailyGoalMinutes,
          displayName: existingUser.displayName,
        ),
      );
      return updated;
    }

    final newUser = AppUser(uid: uid, email: email, bundesland: 'Brandenburg');
    await _userRepository.createUser(newUser);
    return newUser;
  }

  /// Passwort-Reset-E-Mail senden.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

// ── Riverpod-Provider ──────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    auth: FirebaseAuth.instance,
    userRepository: ref.watch(userRepositoryProvider),
  );
});

/// Gibt den aktuell authentifizierten Firebase-User zurück (oder null).
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});
