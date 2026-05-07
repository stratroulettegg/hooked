/// Zentrale Konstanten für Rechtsdokumente.
///
/// Damit Privacy/Impressum-Verweise nicht über mehrere Dateien gestreut sind
/// und beim Domain-Wechsel nur eine Stelle anzufassen ist.
class LegalUrls {
  LegalUrls._();

  /// Basis-Domain der Marketing-/Rechts-Site.
  static const String _base = 'https://hooked-fangtagebuch.app';

  /// Datenschutzerklärung (DSGVO Art. 13).
  static const String privacy = '$_base/datenschutz.html';

  /// Impressum (TMG §5 / DSA Art. 4).
  static const String imprint = '$_base/impressum.html';

  /// Marketing-Startseite.
  static const String home = '$_base/';

  /// Support-/Kontaktadresse.
  static const String supportEmail = 'hello@hooked-fangtagebuch.app';
}
