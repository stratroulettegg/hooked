import 'package:shared_preferences/shared_preferences.dart';

import 'notification_categories.dart';

/// Persistierte Einstellungen rund um lokale Benachrichtigungen.
///
/// Wird einmal in `main()` initialisiert, damit der NotificationService
/// die Toggles synchron lesen kann.
class NotificationPrefs {
  NotificationPrefs._();

  static const _enabledPrefix = 'notif_enabled_';
  static const _masterKey = 'notif_master_enabled';
  static const _profileKey = 'notif_profile';
  static const _quietStartKey = 'notif_quiet_start_minutes';
  static const _quietEndKey = 'notif_quiet_end_minutes';
  static const _lastDocNudgeKey = 'notif_last_doc_nudge_iso';
  static const _lastStreakKey = 'notif_last_streak_iso';
  static const _lastOnThisDayKey = 'notif_last_otd_iso';
  static const _lastFirstWaterKey = 'notif_last_first_water_iso';
  static const _lastMonthlyKey = 'notif_last_monthly_iso';
  static const _lastWeeklyKey = 'notif_last_weekly_iso';

  /// Quiet Hours: Default 21:00 → 06:30 (in Minuten ab Mitternacht).
  static const int defaultQuietStart = 21 * 60;
  static const int defaultQuietEnd = 6 * 60 + 30;

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p =>
      _prefs ?? (throw StateError('NotificationPrefs not initialized'));

  // ─── Master & Profil ───────────────────────────────────────────────────────

  /// Master-Switch. Default `true` — der User kann komplett stummschalten.
  static bool get masterEnabled => _p.getBool(_masterKey) ?? true;

  static Future<void> setMasterEnabled(bool value) =>
      _p.setBool(_masterKey, value);

  /// Aktives Charakter-Preset. Default [NotificationProfile.standard].
  static NotificationProfile get profile {
    final id = _p.getString(_profileKey);
    return NotificationProfile.values.firstWhere(
      (p) => p.id == id,
      orElse: () => NotificationProfile.standard,
    );
  }

  static Future<void> setProfile(NotificationProfile p) =>
      _p.setString(_profileKey, p.id);

  // ─── Toggles (legacy, für Tests / spätere Erweiterungen) ──────────────────

  /// Eine Kategorie ist aktiv, wenn der Master an ist UND das aktive Profil
  /// sie einschließt. Ein optionales Override (alter API-Pfad) wird zusätzlich
  /// berücksichtigt.
  static bool isEnabled(NotificationCategory c) {
    if (!masterEnabled) return false;
    final override = _p.getBool('$_enabledPrefix${c.id}');
    if (override != null) return override;
    return profile.includes(c);
  }

  static Future<void> setEnabled(NotificationCategory c, bool value) async {
    await _p.setBool('$_enabledPrefix${c.id}', value);
  }

  /// Setzt alle Kategorie-Overrides zurück (z. B. nach Profil-Wechsel),
  /// damit das frisch gewählte Profil sauber gilt.
  static Future<void> clearCategoryOverrides() async {
    for (final c in NotificationCategory.values) {
      await _p.remove('$_enabledPrefix${c.id}');
    }
  }

  // ─── Quiet Hours ───────────────────────────────────────────────────────────

  static int get quietStartMinutes =>
      _p.getInt(_quietStartKey) ?? defaultQuietStart;

  static int get quietEndMinutes => _p.getInt(_quietEndKey) ?? defaultQuietEnd;

  static Future<void> setQuietHours(int startMinutes, int endMinutes) async {
    await _p.setInt(_quietStartKey, startMinutes);
    await _p.setInt(_quietEndKey, endMinutes);
  }

  /// Liegt der gegebene Zeitpunkt in den Ruhezeiten?
  /// Quiet-Range darf über Mitternacht hinweg gehen (start > end).
  static bool isQuiet(DateTime t) {
    final mins = t.hour * 60 + t.minute;
    final start = quietStartMinutes;
    final end = quietEndMinutes;
    if (start == end) return false;
    if (start < end) {
      return mins >= start && mins < end;
    }
    // Über Mitternacht
    return mins >= start || mins < end;
  }

  /// Verschiebt den gegebenen Zeitpunkt aus der Quiet-Zone heraus.
  /// Wird aufgerufen, bevor eine Notification geplant wird.
  static DateTime moveOutOfQuiet(DateTime t) {
    if (!isQuiet(t)) return t;
    final endMinutes = quietEndMinutes;
    final endHour = endMinutes ~/ 60;
    final endMin = endMinutes % 60;
    // Nach Quiet-Ende → falls aktuell nach Mitternacht in der Quiet-Zone:
    // gleicher Tag, sonst nächster Tag.
    final mins = t.hour * 60 + t.minute;
    final shifted = mins >= quietStartMinutes
        ? DateTime(t.year, t.month, t.day + 1, endHour, endMin)
        : DateTime(t.year, t.month, t.day, endHour, endMin);
    return shifted;
  }

  // ─── Letzte Auslösungen (Idempotenz) ───────────────────────────────────────

  static DateTime? _readDate(String key) {
    final s = _p.getString(key);
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static Future<void> _writeDate(String key, DateTime t) async {
    await _p.setString(key, t.toIso8601String());
  }

  static DateTime? get lastDocNudge => _readDate(_lastDocNudgeKey);
  static Future<void> markDocNudge() =>
      _writeDate(_lastDocNudgeKey, DateTime.now());

  static DateTime? get lastStreakWarning => _readDate(_lastStreakKey);
  static Future<void> markStreakWarning() =>
      _writeDate(_lastStreakKey, DateTime.now());

  static DateTime? get lastOnThisDay => _readDate(_lastOnThisDayKey);
  static Future<void> markOnThisDay() =>
      _writeDate(_lastOnThisDayKey, DateTime.now());

  static DateTime? get lastFirstWater => _readDate(_lastFirstWaterKey);
  static Future<void> markFirstWater() =>
      _writeDate(_lastFirstWaterKey, DateTime.now());

  static DateTime? get lastMonthlyRecap => _readDate(_lastMonthlyKey);
  static Future<void> markMonthlyRecap() =>
      _writeDate(_lastMonthlyKey, DateTime.now());

  static DateTime? get lastWeeklyRecap => _readDate(_lastWeeklyKey);
  static Future<void> markWeeklyRecap() =>
      _writeDate(_lastWeeklyKey, DateTime.now());
}
