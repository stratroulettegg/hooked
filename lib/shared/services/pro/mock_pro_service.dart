import 'package:shared_preferences/shared_preferences.dart';

/// Persistiert den Mock-Pro-Status, solange RevenueCat noch nicht
/// angeschlossen ist (siehe `docs/MONETIZATION.md`).
///
/// Wird vom Debug-Toggle in den Settings beschrieben und vom
/// `isProProvider` als initialer Wert gelesen. Sobald `purchases_flutter`
/// integriert ist, wird dieser Service durch RevenueCat ersetzt.
class MockProService {
  MockProService._();

  static const _key = 'mock_pro_active_v1';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p =>
      _prefs ?? (throw StateError('MockProService.init() not called'));

  static bool get isPro => _p.getBool(_key) ?? false;

  static Future<void> setPro(bool value) async {
    await _p.setBool(_key, value);
  }
}
