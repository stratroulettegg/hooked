import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import 'revenuecat_bootstrap.dart';

/// Dünner Wrapper um die nativen RevenueCat-UI-Komponenten
/// ([RevenueCatUI]). Trennt Bootstrap-/Service-Logik von der UI-Schicht
/// und prüft konsistent die `RevenueCatBootstrap.isAvailable`-Flag,
/// damit Aufrufe im Mock-Modus harmlos no-op sind.
class RevenueCatUiHelper {
  RevenueCatUiHelper._();

  /// Zeigt das im RC-Dashboard konfigurierte Paywall-Template als
  /// Vollbild-Overlay an. Liefert das Resultat zurück (`purchased`,
  /// `restored`, `cancelled`, `error`, `notPresented`).
  ///
  /// Wenn das Default-Offering kein Paywall-Asset hat, oder RC nicht
  /// initialisiert ist, wird `null` zurückgegeben — Caller fallen dann
  /// auf den hauseigenen [PaywallScreen] zurück.
  static Future<PaywallResult?> presentPaywall({
    String? entitlementIdentifier,
    bool displayCloseButton = true,
  }) async {
    if (!RevenueCatBootstrap.isAvailable) return null;
    try {
      return await RevenueCatUI.presentPaywallIfNeeded(
        entitlementIdentifier ?? RevenueCatBootstrap.entitlementId,
        displayCloseButton: displayCloseButton,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RC-UI] presentPaywall failed: $e');
      }
      return PaywallResult.error;
    }
  }

  /// Erzwingt das Paywall-Sheet (auch wenn der User bereits Pro hat).
  /// Nützlich für „Plan wechseln" / „Upgrade"-Aktionen.
  static Future<PaywallResult?> presentPaywallForce({
    Offering? offering,
    bool displayCloseButton = true,
  }) async {
    if (!RevenueCatBootstrap.isAvailable) return null;
    try {
      return await RevenueCatUI.presentPaywall(
        offering: offering,
        displayCloseButton: displayCloseButton,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RC-UI] presentPaywallForce failed: $e');
      }
      return PaywallResult.error;
    }
  }

  /// Öffnet das native Customer-Center: aktiver Plan, nächstes
  /// Abrechnungsdatum, „Plan wechseln", „Kündigen", FAQ.
  /// Setzt voraus, dass das Customer-Center im RC-Dashboard konfiguriert
  /// wurde.
  static Future<void> presentCustomerCenter() async {
    if (!RevenueCatBootstrap.isAvailable) return;
    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[RC-UI] presentCustomerCenter failed: $e');
      }
    }
  }
}
