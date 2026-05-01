import 'package:shared_preferences/shared_preferences.dart';

/// Persistiert, ob das Onboarding bereits gesehen wurde.
/// Wird einmal in `main()` vor `runApp` initialisiert, damit der
/// `GoRouter`-Redirect synchron darauf zugreifen kann.
class OnboardingService {
  OnboardingService._();

  static const _key = 'onboarding_seen_v1';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool get hasSeen => _prefs?.getBool(_key) ?? false;

  static Future<void> markSeen() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setBool(_key, true);
  }

  /// Nur für Debug / „Onboarding erneut zeigen".
  static Future<void> reset() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.remove(_key);
  }
}
