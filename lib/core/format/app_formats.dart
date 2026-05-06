import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Zentrale Format-Konstanten und Helfer.
///
/// Vermeidet, dass Datumsformate, Locale-Kürzel und Druck-Trend-Logik
/// quer durch die App in unterschiedlichen Varianten landen.

/// Die einzige Locale, die die App aktuell unterstützt.
const String appLocale = 'de';

/// Wiederverwendbare DateFormat-Patterns. Alle ohne Locale gespeichert –
/// beim Lookup wird [appLocale] verwendet, damit Wochentag/Monat lokalisiert
/// sind.
abstract class AppDateFormats {
  static final DateFormat dayMonthShort = DateFormat('dd.MM.', appLocale);
  static final DateFormat dayMonth = DateFormat('dd.MM', appLocale);
  static final DateFormat dayMonthYear = DateFormat('dd.MM.yyyy', appLocale);
  static final DateFormat dayMonthYearShort = DateFormat('dd.MM.yy', appLocale);
  static final DateFormat weekdayDate = DateFormat(
    'EEE, dd.MM.yyyy',
    appLocale,
  );
  static final DateFormat weekdayDateLong = DateFormat(
    'EEEE, dd.MM.yyyy',
    appLocale,
  );
  static final DateFormat weekdayDateMonthName = DateFormat(
    'EEEE, d. MMMM y',
    appLocale,
  );
  static final DateFormat dayMonthHourMinute = DateFormat(
    'dd.MM\nHH:mm',
    appLocale,
  );
  static final DateFormat dayMonthYearHourMinute = DateFormat(
    'dd.MM.yyyy – HH:mm',
    appLocale,
  );
  static final DateFormat hourMinute = DateFormat('HH:mm', appLocale);
  static final DateFormat dayOfMonth = DateFormat('dd', appLocale);
  static final DateFormat monthShort = DateFormat('MMM', appLocale);
}

/// Zahlen-Formatter f\u00fcr deutsche Anzeige (Komma als Dezimaltrenner).
///
/// Wird f\u00fcr alle Mengen/Ma\u00df-Werte verwendet (kg, m, cm, mm, hPa).
/// Koordinaten bleiben mit Punkt, weil sie h\u00e4ufig in Maps-URLs landen.
abstract class AppNum {
  /// Wandelt eine Zahl mit fester Nachkommastellen-Zahl in den deutschen
  /// Stil ("12,5"). F\u00fcr negative Werte/Vorzeichen bleibt das Vorzeichen
  /// erhalten.
  static String fixed(num value, int fractionDigits) =>
      value.toStringAsFixed(fractionDigits).replaceAll('.', ',');

  /// Wandelt einen Text-Wert mit Punkt (z. B. ein toString() von double)
  /// in den deutschen Stil mit Komma. Leere/null-Werte werden zu ''.
  static String text(Object? value) =>
      value?.toString().replaceAll('.', ',') ?? '';

  /// Gewicht in Gramm als kg (z. B. 1500 \u2192 "1,50 kg") oder g
  /// (kleiner 1\u202fkg \u2192 "850 g").
  static String kg(int grams) {
    if (grams >= 1000) return '${fixed(grams / 1000, 2)} kg';
    return '$grams g';
  }

  /// Tiefe/L\u00e4nge in Meter (z. B. 4.5 \u2192 "4,5 m"), ganze Zahlen ohne
  /// Nachkommastelle.
  static String meters(double m, {int maxFractionDigits = 1}) {
    if (m == m.roundToDouble()) return '${m.toStringAsFixed(0)} m';
    return '${fixed(m, maxFractionDigits)} m';
  }

  /// L\u00e4nge in cm (90 \u2192 "90 cm", 12.5 \u2192 "12,5 cm").
  static String cm(double v) {
    if (v == v.roundToDouble()) return '${v.toStringAsFixed(0)} cm';
    return '${fixed(v, 1)} cm';
  }

  /// Niederschlag in mm (1 Nachkommastelle).
  static String mm(double v) => '${fixed(v, 1)} mm';

  /// Druck-Delta mit Vorzeichen ("+1,5 hPa" / "\u22120,8 hPa").
  static String hPaDelta(double v) {
    final sign = v >= 0 ? '+' : '';
    return '$sign${fixed(v, 1)} hPa';
  }
}

/// Formatierung der Drucktendenz (Pfeil + signierter hPa-Wert).
///
/// Schwellen unterscheiden sich je nach Bezugszeitraum (3 h vs. 24 h),
/// die Logik ist identisch – darum hier zentralisiert.
abstract class PressureTrend {
  /// Standardwerte für 3-h-Tendenz (Open-Meteo current).
  static const Thresholds threeHour = Thresholds(strong: 3.0, mild: 1.0);

  /// Standardwerte für 24-h-Tendenz.
  static const Thresholds twentyFourHour = Thresholds(strong: 6.0, mild: 2.0);

  /// Pfeil als Text-Glyph (mit VS15, damit iOS keine Emoji-Glyphe nutzt).
  static String arrow(double? deltaHpa, {Thresholds t = threeHour}) {
    if (deltaHpa == null) return '–';
    if (deltaHpa > t.strong) return '⬆\uFE0E';
    if (deltaHpa > t.mild) return '↗\uFE0E';
    if (deltaHpa >= -t.mild) return '→\uFE0E';
    if (deltaHpa >= -t.strong) return '↘\uFE0E';
    return '⬇\uFE0E';
  }

  /// Kurztext der Tendenz.
  static String label(double? deltaHpa, {Thresholds t = threeHour}) {
    if (deltaHpa == null) return '–';
    if (deltaHpa > t.strong) return 'stark steigend';
    if (deltaHpa > t.mild) return 'steigend';
    if (deltaHpa >= -t.mild) return 'stabil';
    if (deltaHpa >= -t.strong) return 'fallend';
    return 'stark fallend';
  }

  /// "↗ +1.5 hPa" – wenn keine Tendenz, fällt auf den absoluten Druck zurück.
  static String formatTrend(
    double? deltaHpa,
    double? absoluteHpa, {
    Thresholds t = threeHour,
  }) {
    if (deltaHpa == null) {
      return absoluteHpa != null ? '${absoluteHpa.round()} hPa' : '–';
    }
    final sign = deltaHpa >= 0 ? '+' : '';
    return '${arrow(deltaHpa, t: t)} $sign${AppNum.fixed(deltaHpa, 1)} hPa';
  }

  /// Farbe nach Stärke der Tendenz – stabile Druckverhältnisse = ruhig.
  /// Erwartet die drei Score-Farben aus dem Theme.
  static Color color({
    required double? deltaHpa,
    required Color stable,
    required Color mid,
    required Color strong,
    required Color unknown,
    Thresholds t = threeHour,
  }) {
    if (deltaHpa == null) return unknown;
    final a = deltaHpa.abs();
    if (a >= t.strong) return strong;
    if (a >= t.mild) return mid;
    return stable;
  }
}

class Thresholds {
  final double strong;
  final double mild;
  const Thresholds({required this.strong, required this.mild});
}

/// Mapping Wettercode → Material-Icon. Spiegelt die Label-/Emoji-Mappings
/// in [WeatherData] wider, lebt aber im UI-Layer, weil hier `IconData`
/// aus Material gebraucht wird.
IconData weatherCodeIcon(int? code) {
  if (code == null) return Icons.question_mark;
  if (code == 0) return Icons.wb_sunny;
  if (code == 1) return Icons.wb_sunny_outlined;
  if (code == 2) return Icons.wb_cloudy_outlined;
  if (code == 3) return Icons.cloud;
  if (code <= 49) return Icons.foggy;
  if (code <= 69) return Icons.grain;
  if (code <= 79) return Icons.ac_unit;
  if (code <= 99) return Icons.thunderstorm;
  return Icons.question_mark;
}
