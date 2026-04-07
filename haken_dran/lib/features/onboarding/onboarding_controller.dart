import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/services/auth_service.dart';

class OnboardingState {
  final String? selectedBundesland;
  final int dailyGoalMinutes;
  final bool isLoading;
  final String? error;

  const OnboardingState({
    this.selectedBundesland,
    this.dailyGoalMinutes = 10,
    this.isLoading = false,
    this.error,
  });

  OnboardingState copyWith({
    String? selectedBundesland,
    int? dailyGoalMinutes,
    bool? isLoading,
    String? error,
  }) {
    return OnboardingState(
      selectedBundesland: selectedBundesland ?? this.selectedBundesland,
      dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingState> {
  final AuthService _authService;
  final SharedPreferences _prefs;

  static const _prefKeyOnboardingDone = 'onboarding_done';
  static const _prefKeyBundesland = 'bundesland';
  static const _prefKeyDailyGoal = 'daily_goal_minutes';

  OnboardingController({
    required AuthService authService,
    required SharedPreferences prefs,
  })  : _authService = authService,
        _prefs = prefs,
        super(const OnboardingState());

  void selectBundesland(String bundesland) {
    state = state.copyWith(selectedBundesland: bundesland);
  }

  void selectDailyGoal(int minutes) {
    state = state.copyWith(dailyGoalMinutes: minutes);
  }

  /// Speichert Einstellungen lokal und startet anonymes Firebase-Login.
  Future<bool> completeOnboarding() async {
    final bundesland = state.selectedBundesland;
    if (bundesland == null) {
      state = state.copyWith(error: 'Bitte wähle dein Bundesland aus.');
      return false;
    }

    state = state.copyWith(isLoading: true);
    try {
      // Anonymes Login damit Fortschritt in Firestore gespeichert werden kann
      await _authService.signInAnonymously();

      await _prefs.setString(_prefKeyBundesland, bundesland);
      await _prefs.setInt(_prefKeyDailyGoal, state.dailyGoalMinutes);
      await _prefs.setBool(_prefKeyOnboardingDone, true);

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Fehler beim Starten: $e',
      );
      return false;
    }
  }

  static bool isOnboardingDone(SharedPreferences prefs) {
    return prefs.getBool(_prefKeyOnboardingDone) ?? false;
  }

  static String? getSavedBundesland(SharedPreferences prefs) {
    return prefs.getString(_prefKeyBundesland);
  }
}

// ── Riverpod-Provider ──────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main() with ProviderScope overrides');
});

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
  return OnboardingController(
    authService: ref.watch(authServiceProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
});
