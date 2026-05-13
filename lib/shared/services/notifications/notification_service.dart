import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_categories.dart';
import 'notification_prefs.dart';

/// Stable Notification-IDs pro Kategorie (Trip-Reminder verwenden eigene
/// Hashes, weil sie pro Trip individuell sind).
class _Ids {
  static const int weeklyRecap = 1001;
  static const int monthlyRecap = 1002;
  static const int firstWaterOfMonth = 1003;
  static const int streakWarning = 1004;
  static const int onThisDay = 1005;
  static const int docNudge = 1006;
}

/// Wrapper rund um `flutter_local_notifications` plus Hooked-spezifische
/// Helfer (Quiet Hours, Toggles, deterministische IDs für Trip-Reminder).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;

  bool get isReady => _initialized && _permissionGranted;

  Future<void> init() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      String tzName = 'UTC';
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tzName = info.identifier;
      } catch (e) {
        debugPrint('notifications timezone lookup: $e');
      }
      try {
        tz.setLocalLocation(tz.getLocation(tzName));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
      );
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('Notification init failed: $e');
    }
  }

  /// Permission anfragen. Auf iOS expliziter Dialog, auf Android 13+
  /// ebenfalls expliziter Dialog. Vorher kein Schedule erlaubt.
  Future<bool> requestPermission() async {
    if (!_initialized) await init();
    if (!_initialized) return false;

    bool ok = true;
    try {
      if (Platform.isIOS) {
        ok =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      } else if (Platform.isAndroid) {
        ok =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Notification permission failed: $e');
      ok = false;
    }
    _permissionGranted = ok;
    return ok;
  }

  /// Synchronisiert den aktuell bekannten Permission-Status, ohne den
  /// Dialog zu öffnen. iOS gibt das nicht zurück → optimistisch true.
  Future<void> refreshPermission() async {
    if (!_initialized) await init();
    if (Platform.isAndroid) {
      try {
        final granted =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false;
        _permissionGranted = granted;
      } catch (_) {
        _permissionGranted = false;
      }
    } else {
      _permissionGranted = true;
    }
  }

  // ─── Schedule / Cancel Helfer ──────────────────────────────────────────────

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      'hooked_reminders',
      'Hooked Erinnerungen',
      channelDescription:
          'Trip-Erinnerungen, Doku-Nudges, Recaps und Streak-Hinweise.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const ios = DarwinNotificationDetails();
    return const NotificationDetails(android: android, iOS: ios);
  }

  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!isReady) return;
    final shifted = NotificationPrefs.moveOutOfQuiet(when);
    if (!shifted.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(shifted, tz.local),
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Notification schedule failed ($id): $e');
    }
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!isReady) return;
    if (NotificationPrefs.isQuiet(DateTime.now())) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details(),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Notification show failed ($id): $e');
    }
  }

  Future<void> _cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('notifications cancel($id): $e');
    }
  }

  // ─── Social Push (FCM Foreground) ─────────────────────────────────────────

  /// Zeigt eine soziale Push-Benachrichtigung (Like/Kommentar/Follow), die
  /// vom FCM-Foreground-Handler kommt. Eigener High-Priority-Channel auf
  /// Android, damit OS-Gruppierung und Sound passen.
  Future<void> showSocialPush({
    required String title,
    required String body,
    String? threadId,
    String? payload,
  }) async {
    if (!_initialized) await init();
    if (!_initialized) return;
    final android = AndroidNotificationDetails(
      'social',
      'Soziale Aktivität',
      channelDescription: 'Likes, Kommentare und neue Follower.',
      importance: Importance.high,
      priority: Priority.high,
      tag: threadId,
      groupKey: threadId,
    );
    final ios = DarwinNotificationDetails(threadIdentifier: threadId);
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android, iOS: ios),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('social push show failed: $e');
    }
  }

  // ─── Public API: Trip-Reminder ────────────────────────────────────────────

  /// Eindeutige IDs für die zwei Reminder eines Trips (Vorabend & Morgen).
  /// Pro Trip 2 IDs aus dem Hash der trip-ID.
  int _tripEveId(String tripId) =>
      2_000_000 + (tripId.hashCode.abs() % 1_000_000);
  int _tripMorningId(String tripId) =>
      3_000_000 + (tripId.hashCode.abs() % 1_000_000);

  Future<void> scheduleTripReminders({
    required String tripId,
    required String tripName,
    required DateTime tripDate,
    String? waterBodyName,
  }) async {
    await cancelTripReminders(tripId);
    if (!NotificationPrefs.isEnabled(NotificationCategory.tripReminder)) {
      return;
    }

    // Datum normalisieren auf 5:30 Trip-Tag
    final morning = DateTime(
      tripDate.year,
      tripDate.month,
      tripDate.day,
      5,
      30,
    );
    final eve = morning.subtract(const Duration(hours: 9, minutes: 30));
    // = Vortag 20:00

    final loc = waterBodyName?.trim().isNotEmpty == true
        ? waterBodyName!
        : tripName;

    if (eve.isAfter(DateTime.now())) {
      await _zonedSchedule(
        id: _tripEveId(tripId),
        title: 'Morgen geht\u2019s los',
        body: 'Trip „$tripName" — $loc um 5:30. Wetter checken?',
        when: eve,
        payload: 'trip:$tripId',
      );
    }
    if (morning.isAfter(DateTime.now())) {
      await _zonedSchedule(
        id: _tripMorningId(tripId),
        title: 'Tight Lines!',
        body: 'Heute 5:30 — $loc. Viel Erfolg.',
        when: morning,
        payload: 'trip:$tripId',
      );
    }
  }

  Future<void> cancelTripReminders(String tripId) async {
    await _cancel(_tripEveId(tripId));
    await _cancel(_tripMorningId(tripId));
  }

  // ─── Public API: Voice-Quick-Add Erinnerung ───────────────────────────────

  /// Stabile ID-Bucket für „Foto/Details-zu-Fang"-Erinnerungen.
  int _catchDetailsId(String catchId) =>
      4_000_000 + (catchId.hashCode.abs() % 1_000_000);

  /// Plant eine lokale Erinnerung, später Foto und Details zu einem per
  /// Sprache erfassten Fang zu ergänzen.
  Future<void> scheduleCatchDetailsReminder({
    required String catchId,
    required String species,
    required DateTime when,
  }) async {
    if (!_initialized) await init();
    if (!_permissionGranted) {
      // Versuch ohne Dialog — falls iOS still erlaubt, ist alles ok.
      await refreshPermission();
    }
    await _zonedSchedule(
      id: _catchDetailsId(catchId),
      title: 'Foto & Details ergänzen',
      body: 'Dein „$species"-Fang wartet noch auf Foto und Details.',
      when: when,
      payload: 'catch:$catchId',
    );
  }

  // ─── Public API: Reaktive / sofortige Notifications ───────────────────────

  Future<void> showDocNudge({required int catchCountWithoutDoc}) async {
    if (!NotificationPrefs.isEnabled(NotificationCategory.docNudge)) return;
    // Höchstens 1× pro Tag
    final last = NotificationPrefs.lastDocNudge;
    if (last != null && DateTime.now().difference(last).inHours < 22) {
      return;
    }
    final body = catchCountWithoutDoc == 1
        ? 'Gestern gefangen, aber noch keine Notiz oder Foto — magst du was '
              'ergänzen?'
        : '$catchCountWithoutDoc Fänge ohne Foto/Notiz — kurz nachpflegen?';
    await _showNow(
      id: _Ids.docNudge,
      title: 'Doku-Erinnerung',
      body: body,
      payload: 'route:/catches',
    );
    await NotificationPrefs.markDocNudge();
  }

  Future<void> showStreakWarning({required int streakDays}) async {
    if (!NotificationPrefs.isEnabled(NotificationCategory.streakProtection)) {
      return;
    }
    final last = NotificationPrefs.lastStreakWarning;
    if (last != null && DateTime.now().difference(last).inHours < 22) {
      return;
    }
    await _showNow(
      id: _Ids.streakWarning,
      title: 'Streak in Gefahr',
      body: '$streakDays-Tage-Streak läuft heute ab — kurz raus und halten?',
      payload: 'route:/water-days',
    );
    await NotificationPrefs.markStreakWarning();
  }

  Future<void> showOnThisDay({required String body}) async {
    if (!NotificationPrefs.isEnabled(NotificationCategory.onThisDay)) return;
    final last = NotificationPrefs.lastOnThisDay;
    if (last != null && DateTime.now().difference(last).inDays < 6) return;
    await _showNow(
      id: _Ids.onThisDay,
      title: 'Vor einem Jahr',
      body: body,
      payload: 'route:/catches',
    );
    await NotificationPrefs.markOnThisDay();
  }

  Future<void> showFirstWaterOfMonth() async {
    if (!NotificationPrefs.isEnabled(NotificationCategory.firstWaterOfMonth)) {
      return;
    }
    final last = NotificationPrefs.lastFirstWater;
    final now = DateTime.now();
    if (last != null && last.year == now.year && last.month == now.month) {
      return;
    }
    await _showNow(
      id: _Ids.firstWaterOfMonth,
      title: 'Neuer Monat',
      body: 'Lust auf eine kurze Trip-Planung?',
      payload: 'route:/trips',
    );
    await NotificationPrefs.markFirstWater();
  }

  Future<void> showMonthlyRecap({required String body}) async {
    if (!NotificationPrefs.isEnabled(NotificationCategory.monthlyRecap)) {
      return;
    }
    final last = NotificationPrefs.lastMonthlyRecap;
    final now = DateTime.now();
    if (last != null && last.year == now.year && last.month == now.month) {
      return;
    }
    await _showNow(
      id: _Ids.monthlyRecap,
      title: 'Monats-Recap',
      body: body,
      payload: 'route:/records',
    );
    await NotificationPrefs.markMonthlyRecap();
  }

  Future<void> showWeeklyRecap({required String body}) async {
    if (!NotificationPrefs.isEnabled(NotificationCategory.weeklyRecap)) return;
    final last = NotificationPrefs.lastWeeklyRecap;
    if (last != null && DateTime.now().difference(last).inDays < 5) return;
    await _showNow(
      id: _Ids.weeklyRecap,
      title: 'Wochen-Recap',
      body: body,
      payload: 'route:/records',
    );
    await NotificationPrefs.markWeeklyRecap();
  }

  /// Cancelt alle geplanten Notifications. Wird genutzt, wenn der Nutzer
  /// alle Kategorien abschaltet.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('notifications cancelAll: $e');
    }
  }
}
