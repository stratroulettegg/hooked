import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Initialisiert das RevenueCat-SDK (`purchases_flutter`) und stellt die
/// reaktive `customerInfoStream` zur Verfügung.
///
/// **Compile-Time-Konfiguration:** Die platform-spezifischen Public-SDK-Keys
/// werden über `--dart-define` injiziert, damit sie nicht im Repo landen
/// und pro Build-Variante (Dev/Beta/Prod) unterschiedlich sein können:
///
/// ```sh
/// flutter run \
///   --dart-define=REVENUECAT_IOS_KEY=appl_xxx \
///   --dart-define=REVENUECAT_ANDROID_KEY=goog_yyy
/// ```
///
/// Sind keine Keys gesetzt, läuft die App weiter, RevenueCat wird aber
/// nicht initialisiert. Der `IsProNotifier` fällt dann auf den
/// `MockProService` zurück (Debug-Toggle in den Settings).
class RevenueCatBootstrap {
  RevenueCatBootstrap._();

  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  /// Universeller RevenueCat-Test-Key (Sandbox / Dashboard-Test-App).
  /// Greift, wenn keine plattform-spezifischen Keys per `--dart-define`
  /// gesetzt wurden. Für Production-Builds müssen die echten
  /// `appl_*`/`goog_*`-Keys via `--dart-define` injiziert werden.
  static const _fallbackTestKey = 'test_DYUKnAZdpIpdsndFmxOqMwGjzrV';

  /// Kanonischer Entitlement-Identifier in RevenueCat (siehe
  /// docs/MONETIZATION.md). Für Production sollte das Entitlement im
  /// RC-Dashboard genau diesen Identifier tragen.
  static const String entitlementId = 'hooked_pro';

  /// Akzeptierte Entitlement-Identifier (Fallbacks). Der RC-Test-Store
  /// wurde initial mit dem Display-Namen als Identifier angelegt — wir
  /// matchen aus Pragmatismus auf alle bekannten Varianten, damit ein
  /// späteres Rename im Dashboard die App nicht bricht.
  static const List<String> _acceptedEntitlementIds = <String>[
    'hooked_pro',
    'Hooked - Dein Fangtagebuch Pro',
  ];

  static bool _initialized = false;
  static bool get isAvailable => _initialized;

  static final _controller = StreamController<CustomerInfo>.broadcast();

  /// Live-Stream aller Customer-Info-Updates aus dem RC-SDK. Wird von
  /// `pro_providers.dart` konsumiert. Wenn RC nicht initialisiert wurde
  /// (kein Key, oder Init schlägt fehl), bleibt der Stream leer.
  static Stream<CustomerInfo> get customerInfoStream => _controller.stream;

  /// Aktuell zwischengespeicherte CustomerInfo (für Sync-Reads).
  static CustomerInfo? lastCustomerInfo;

  static String? get _platformKey {
    if (kIsWeb) return null;
    if (Platform.isIOS || Platform.isMacOS) {
      return _iosKey.isEmpty ? _fallbackTestKey : _iosKey;
    }
    if (Platform.isAndroid) {
      return _androidKey.isEmpty ? _fallbackTestKey : _androidKey;
    }
    return null;
  }

  /// Initialisiert das SDK. Idempotent. Schluckt Fehler, damit ein
  /// SDK-Fehler den App-Start nicht blockiert — der App fällt dann auf
  /// den Mock-Pro-Pfad zurück.
  static Future<void> init() async {
    if (_initialized) return;
    final key = _platformKey;
    if (key == null) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RevenueCat] no API key — skipping init (mock mode)');
      }
      return;
    }
    try {
      await Purchases.setLogLevel(
        kDebugMode ? LogLevel.debug : LogLevel.warn,
      );
      await Purchases.configure(PurchasesConfiguration(key));
      _initialized = true;
      Purchases.addCustomerInfoUpdateListener((info) {
        lastCustomerInfo = info;
        _logInfo('listener', info);
        if (!_controller.isClosed) _controller.add(info);
      });
      // Initialen Snapshot in den Stream pushen.
      try {
        final info = await Purchases.getCustomerInfo();
        lastCustomerInfo = info;
        _logInfo('init-snapshot', info);
        if (!_controller.isClosed) _controller.add(info);
      } catch (_) {/* okay, Listener wird sich melden */}
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RevenueCat] initialized (key=${key.substring(0, 8)}…)');
      }
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RevenueCat] init failed: $e\n$st');
      }
    }
  }

  /// Aktuell bei RC eingeloggte App-User-ID (Idempotenz für `identify`).
  static String? _currentRcUid;

  /// Verknüpft die Käufe mit dem Firebase-User. Wenn vorher anonym
  /// eingekauft wurde, werden die Entitlements automatisch übertragen.
  /// Aufruf nach erfolgreichem Login.
  ///
  /// Idempotent: wiederholte Aufrufe mit derselben UID werden geschluckt,
  /// damit Auth-State-Listener (die mehrfach feuern können) nicht
  /// versehentlich Entitlements neu laden / clearen.
  static Future<void> identify(String uid) async {
    if (!_initialized) return;
    if (_currentRcUid == uid) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RevenueCat] identify: already logged in as $uid (skip)');
      }
      return;
    }
    try {
      final result = await Purchases.logIn(uid);
      _currentRcUid = uid;
      lastCustomerInfo = result.customerInfo;
      _logInfo('logIn', result.customerInfo);
      if (!_controller.isClosed) _controller.add(result.customerInfo);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RevenueCat] logIn failed: $e');
      }
    }
  }

  /// Wechsel auf anonymen RC-User (z.B. nach Logout). Die App-User-ID
  /// wird intern auf einen $RCAnonymousID-Wert zurückgesetzt.
  static Future<void> logout() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
      _currentRcUid = null;
    } catch (_) {/* z.B. wenn schon anonym */}
  }

  /// Prüft anhand des Entitlements, ob der User Pro ist. Akzeptiert
  /// jeden in [_acceptedEntitlementIds] gelisteten Identifier.
  static bool isProFromInfo(CustomerInfo? info) {
    if (info == null) return false;
    final active = info.entitlements.active;
    for (final id in _acceptedEntitlementIds) {
      if (active[id] != null) return true;
    }
    return false;
  }

  /// Erzwingt einen frischen CustomerInfo-Pull vom RC-Backend und pusht
  /// das Ergebnis in den Stream. Nützlich nach Kauf/Restore und beim
  /// App-Resume, damit die UI nicht auf einem veralteten Cache hängt.
  static Future<CustomerInfo?> refresh() async {
    if (!_initialized) return null;
    try {
      await Purchases.invalidateCustomerInfoCache();
      final info = await Purchases.getCustomerInfo();
      lastCustomerInfo = info;
      _logInfo('refresh', info);
      if (!_controller.isClosed) _controller.add(info);
      return info;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RevenueCat] refresh failed: $e');
      }
      return null;
    }
  }

  static void _logInfo(String source, CustomerInfo info) {
    // Routine-Logs entfernt — bei Bedarf reaktivieren.
  }
}
