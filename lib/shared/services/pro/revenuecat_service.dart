import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import 'revenuecat_bootstrap.dart';

/// Resultat eines Kaufversuchs. Wird vom Paywall ausgewertet, um
/// passende Toasts/Analytics zu feuern.
class PurchaseResult {
  PurchaseResult({
    required this.success,
    this.userCancelled = false,
    this.errorMessage,
    this.customerInfo,
  });

  final bool success;
  final bool userCancelled;
  final String? errorMessage;
  final CustomerInfo? customerInfo;
}

/// Dünner Wrapper um `Purchases`-API. Hält keine eigenen Streams —
/// für reaktive Konsumenten siehe [RevenueCatBootstrap.customerInfoStream].
class RevenueCatService {
  RevenueCatService._();

  /// Holt das aktuelle Default-Offering. Liefert `null`, wenn
  /// RevenueCat nicht initialisiert ist oder keine Offerings konfiguriert
  /// sind.
  static Future<Offering?> getCurrentOffering() async {
    if (!RevenueCatBootstrap.isAvailable) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RevenueCat] getOfferings failed: $e');
      }
      return null;
    }
  }

  /// Startet den Kauf eines Pakets. Behandelt User-Cancel als Nicht-Fehler.
  static Future<PurchaseResult> purchase(Package package) async {
    if (!RevenueCatBootstrap.isAvailable) {
      return PurchaseResult(
        success: false,
        errorMessage: 'Store ist nicht verfügbar.',
      );
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      // Kauf-Transaktion abgeschlossen → Erfolg.
      // RC pushed customerInfo bereits via Listener; zusätzlich erzwingen
      // wir einen Cache-Invalidate + Refresh, damit die UI garantiert die
      // neueste Server-Wahrheit sieht (insbesondere im Test-Store, wo der
      // Listener-Push gelegentlich schon mit altem Stand kommt).
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[RevenueCat] purchase ok product=${package.storeProduct.identifier} '
          'active=${result.customerInfo.entitlements.active.keys.toList()}',
        );
      }
      // Async, blockiert die UI nicht. Listener pushed das Ergebnis.
      // ignore: unawaited_futures
      RevenueCatBootstrap.refresh();
      return PurchaseResult(
        success: true,
        customerInfo: result.customerInfo,
      );
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseResult(success: false, userCancelled: true);
      }
      return PurchaseResult(
        success: false,
        errorMessage: e.message ?? 'Kauf fehlgeschlagen',
      );
    } catch (e) {
      return PurchaseResult(success: false, errorMessage: e.toString());
    }
  }

  /// Wiederherstellung früherer Käufe (z.B. nach Re-Install).
  static Future<PurchaseResult> restore() async {
    if (!RevenueCatBootstrap.isAvailable) {
      return PurchaseResult(
        success: false,
        errorMessage: 'Store ist nicht verfügbar.',
      );
    }
    try {
      final info = await Purchases.restorePurchases();
      return PurchaseResult(
        success: RevenueCatBootstrap.isProFromInfo(info),
        customerInfo: info,
      );
    } catch (e) {
      return PurchaseResult(success: false, errorMessage: e.toString());
    }
  }
}
