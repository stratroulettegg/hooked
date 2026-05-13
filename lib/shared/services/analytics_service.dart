import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'consent_service.dart';

/// Schmaler Wrapper um Firebase Analytics mit **strikter Event-Allowlist**.
///
/// Datenschutz-Prinzip: wir tracken Funnel-Ereignisse (welcher Screen,
/// welche Aktion), aber **niemals** den Inhalt — keine Spezies, keine
/// Gewichte, keine GPS-Koordinaten, keine Spot-Namen, keine
/// Trip-Bezeichnungen. Nur was wir brauchen, um zu verstehen ob das UX
/// funktioniert.
///
/// Aktiv nur wenn der User in der App-internen Diagnose-Einwilligung
/// (`ConsentService.diagnosticsGranted`) zugestimmt hat. Ohne Consent
/// werden alle Aufrufe still verworfen.
class AnalyticsService {
  AnalyticsService._();

  /// Whitelist — nur Events aus dieser Liste werden überhaupt gesendet.
  /// Wer ein neues Event braucht, MUSS es hier eintragen. Das verhindert
  /// versehentliches Loggen sensibler Daten via Tipp-Fehler.
  static const _allowedEvents = <String>{
    // Lifecycle / Navigation
    'app_open',
    'screen_view',
    // Onboarding-Funnel
    'onboarding_step',
    'onboarding_completed',
    'consent_granted', // params: tech, diagnostics
    // Catches & Trips (nur Counter, keine Inhalte!)
    'catch_added',
    'catch_deleted',
    'trip_started',
    'trip_finished',
    'spot_added',
    // Auth & Account
    'sign_in_started', // params: provider (apple/google/email)
    'sign_in_succeeded',
    'sign_out',
    'account_deleted',
    // Pro / Monetization
    'paywall_view', // params: source
    'paywall_purchase_started',
    'paywall_purchase_succeeded',
    'paywall_purchase_failed',
    'paywall_restored',
    // Community
    'community_post_created',
    'community_post_liked',
    // Settings
    'diagnostics_toggled', // params: enabled (bool)
  };

  /// Whitelist erlaubter Parameter-Keys — schützt vor versehentlichem
  /// Loggen von Inhalten. Werte werden zusätzlich automatisch gekürzt.
  static const _allowedParamKeys = <String>{
    'step',
    'tech',
    'diagnostics',
    'enabled',
    'provider',
    'source',
    'screen',
    'count',
    'duration_s',
    'error_code',
    'product_id',
    'success',
  };

  static FirebaseAnalytics? _instance;
  static bool _initialized = false;

  /// Wird vom Bootstrap aufgerufen, sobald Firebase verfügbar ist.
  /// Liest [ConsentService.diagnosticsGranted] und konfiguriert das
  /// Collection-Flag. Idempotent.
  static Future<void> bootstrap() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _instance = FirebaseAnalytics.instance;
      await applyConsent(ConsentService.diagnosticsGranted);
    } catch (e) {
      if (kDebugMode) debugPrint('AnalyticsService bootstrap skipped: $e');
      _instance = null;
    }
  }

  /// Schaltet Analytics-Collection live um — wird vom Settings-Toggle
  /// und beim initialen Bootstrap aufgerufen. In Debug-Builds bleibt
  /// Collection aus, damit Tests/Entwicklungs-Sessions keine Events
  /// produzieren.
  static Future<void> applyConsent(bool granted) async {
    final inst = _instance;
    if (inst == null) return;
    try {
      await inst.setAnalyticsCollectionEnabled(granted && !kDebugMode);
    } catch (e) {
      // Native Plugin nicht verfügbar (z.B. fehlender Pod nach pubspec-
      // Update vor `pod install`). Service permanent deaktivieren, damit
      // nicht jedes Event erneut auf den Channel kracht.
      if (kDebugMode) debugPrint('Analytics setCollection failed: $e');
      _instance = null;
    }
  }

  /// Loggt ein Event aus der Allowlist. Unbekannte Events oder Param-
  /// Keys werden geloggt-warning und nicht gesendet (defensiv).
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? params,
  }) async {
    final inst = _instance;
    if (inst == null) return;
    if (!ConsentService.diagnosticsGranted) return;
    if (!_allowedEvents.contains(name)) {
      if (kDebugMode) {
        debugPrint('[Analytics] event "$name" not in allowlist — dropped');
      }
      return;
    }

    Map<String, Object>? clean;
    if (params != null && params.isNotEmpty) {
      clean = <String, Object>{};
      for (final entry in params.entries) {
        if (!_allowedParamKeys.contains(entry.key)) {
          if (kDebugMode) {
            debugPrint(
              '[Analytics] param "${entry.key}" not in allowlist — dropped',
            );
          }
          continue;
        }
        // Auf 100 Zeichen kürzen — Schutz gegen versehentlich lange
        // Werte (z. B. Trip-Namen, Fehler-Stacks).
        final v = entry.value;
        if (v is String && v.length > 100) {
          clean[entry.key] = v.substring(0, 100);
        } else {
          clean[entry.key] = v;
        }
      }
    }

    try {
      await inst.logEvent(name: name, parameters: clean);
    } catch (e) {
      if (kDebugMode) debugPrint('Analytics logEvent failed: $e');
    }
  }
}
