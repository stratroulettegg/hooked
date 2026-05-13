import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'mock_pro_service.dart';
import 'revenuecat_bootstrap.dart';

/// Liefert die jeweils aktuelle [CustomerInfo] aus dem RevenueCat-SDK.
/// Wenn RC nicht initialisiert ist (kein API-Key), bleibt der Stream leer
/// — der `isProProvider` fällt dann auf den `MockProService` zurück.
///
/// `keepAlive: true`, damit Riverpod beim ersten Subscriber den letzten
/// Broadcast-Event nicht verpasst, wenn ein UI-Konsument disposed wird
/// und ein neuer (z.B. anderer Screen) später wieder mountet.
final customerInfoProvider = StreamProvider<CustomerInfo>((ref) {
  ref.keepAlive();
  return RevenueCatBootstrap.customerInfoStream;
});

/// Notifier, der den Pro-Status hält.
///
/// **Quelle der Wahrheit (Priorität):**
/// 1. RevenueCat-Entitlement `hooked_pro` (Live-CustomerInfo).
/// 2. Wenn RC nicht initialisiert ist (kein Key): `MockProService`
///    (Debug-Toggle in den Settings).
class IsProNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Reaktiv auf RC-CustomerInfo lauschen, sobald verfügbar.
    final infoAsync = ref.watch(customerInfoProvider);

    if (!RevenueCatBootstrap.isAvailable) {
      return MockProService.isPro;
    }
    return infoAsync.maybeWhen(
      data: RevenueCatBootstrap.isProFromInfo,
      orElse: () => RevenueCatBootstrap.isProFromInfo(
        RevenueCatBootstrap.lastCustomerInfo,
      ),
    );
  }

  /// Bestehender API-Erhalt: Mock-Toggle in den Settings.
  /// Kein-Op, wenn RevenueCat live ist — dort entscheidet der Store.
  Future<void> set(bool value) async {
    if (RevenueCatBootstrap.isAvailable) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Pro] manual set() ignored — RevenueCat is live');
      }
      return;
    }
    state = value;
    await MockProService.setPro(value);
  }
}

/// Reaktive Source-of-Truth für den Pro-Status. Konsumiert über
/// `ref.watch(isProProvider)`.
final isProProvider = NotifierProvider<IsProNotifier, bool>(IsProNotifier.new);

