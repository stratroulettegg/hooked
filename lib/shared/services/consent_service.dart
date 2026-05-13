import 'package:shared_preferences/shared_preferences.dart';

/// Persistiert die Einwilligung des Users in technisch notwendige
/// Cloud-Verbindungen (anonyme Firebase-UID, FCM-Push-Token-Slot,
/// App Check) sowie — separat — in optionale Diagnose-Daten
/// (Crashlytics).
///
/// Hintergrund: Auch wenn die App ohne sichtbares Konto startet, erzeugt
/// Firebase Auth eine anonyme UID und überträgt dabei IP-Adresse +
/// Geräte-Attestation an Google. Das ist nach § 25 TTDSG / Art. 6 DSGVO
/// einwilligungspflichtig, sobald es nicht zwingend für die App-Funktion
/// erforderlich ist. Wir holen die Einwilligung daher *vor* dem ersten
/// Firebase-Call ein.
///
/// Wird in `main()` vor `runApp` initialisiert, damit der GoRouter-Redirect
/// und die Bootstrap-Logik synchron auf die Flags zugreifen können.
class ConsentService {
  ConsentService._();

  /// V1 — wenn wir Scope/Wording grundlegend ändern, hochzählen, damit
  /// Bestands-User erneut zustimmen.
  static const _techKey = 'tech_consent_v1';
  static const _diagKey = 'diagnostic_consent_v1';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p =>
      _prefs ?? (throw StateError('ConsentService.init() not called'));

  /// True, sobald der User zugestimmt hat, dass eine technische Geräte-
  /// Identität (anonyme Firebase-UID) angelegt und FCM-Push registriert
  /// werden darf. Vor `true` läuft die App rein lokal.
  static bool get techGranted => _p.getBool(_techKey) ?? false;

  /// True, wenn der User Crashlytics aktiv erlaubt hat. Default `false` —
  /// also Opt-in, nicht Opt-out.
  static bool get diagnosticsGranted => _p.getBool(_diagKey) ?? false;

  static Future<void> grantTech() async {
    await _p.setBool(_techKey, true);
  }

  static Future<void> setDiagnostics(bool granted) async {
    await _p.setBool(_diagKey, granted);
  }

  /// Setzt sämtliche Einwilligungen zurück. Wird vom Settings-Eintrag
  /// „Technische Daten zurücksetzen" aufgerufen — beim nächsten Start
  /// erscheint dann erneut der Consent-Screen.
  static Future<void> reset() async {
    await _p.remove(_techKey);
    await _p.remove(_diagKey);
  }
}
