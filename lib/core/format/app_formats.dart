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
    return '${arrow(deltaHpa, t: t)} $sign${deltaHpa.toStringAsFixed(1)} hPa';
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
