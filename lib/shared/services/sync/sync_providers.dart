import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';
import '../firebase/auth_providers.dart';
import '../pro/pro_providers.dart';
import '../../../features/water_days/water_days_providers.dart';
import 'cloud_sync_service.dart';

/// Singleton-Provider für den [CloudSyncService].
///
/// Der Service hat keinen User/Pro-State im Konstruktor — beide werden bei
/// jedem `syncNow()` frisch aus FirebaseAuth gelesen, sodass ein einmal
/// instanziierter Service auch nach Login-Wechseln korrekt arbeitet.
final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  final svc = CloudSyncService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Liefert `true`, wenn die Voraussetzungen für Cloud-Sync erfüllt sind:
/// Firebase initialisiert, **echter** User (nicht anonym) eingeloggt,
/// Pro-Status aktiv. Anonyme Auto-Login-Sessions dürfen nicht syncen —
/// ihre Daten gehören niemandem und würden später beim Account-Upgrade
/// per `linkWithCredential` ohnehin lokal mitwandern.
final cloudSyncEnabledProvider = Provider<bool>((ref) {
  final firebaseOk = ref.watch(firebaseAvailableProvider);
  final user = ref.watch(signedInUserProvider);
  final isPro = ref.watch(isProProvider);
  return firebaseOk && user != null && isPro;
});

/// Stream des aktuellen Sync-Zustands für UI-Indikatoren.
///
/// Initialwert ist [SyncStatus.idle]; jede Statusänderung im Service wird
/// hier weitergereicht.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final svc = ref.watch(cloudSyncServiceProvider);
  // Kombiniere Initial-Snapshot mit dem Live-Stream.
  late final StreamController<SyncStatus> ctrl;
  ctrl = StreamController<SyncStatus>(
    onListen: () {
      ctrl.add(svc.status);
      final sub = svc.statusStream.listen(ctrl.add);
      ctrl.onCancel = () async {
        await sub.cancel();
      };
    },
  );
  ref.onDispose(ctrl.close);
  return ctrl.stream;
});

/// Hängt den Cloud-Sync an Auth- und Pro-Status. Sobald beide passen,
/// wird ein initialer Sync angestoßen; andernfalls passiert nichts.
///
/// Der Provider hält selbst keinen sichtbaren Zustand — er existiert nur,
/// damit Reaktionen auf Auth/Pro-Wechsel zentral an einer Stelle stehen.
final cloudSyncOrchestratorProvider = Provider<void>((ref) {
  final enabled = ref.watch(cloudSyncEnabledProvider);
  final svc = ref.watch(cloudSyncServiceProvider);

  // Bei jedem erfolgreichen Sync, der tatsächlich Remote-Zeilen in die
  // lokale DB übernommen hat, die gecachten Daten-Provider invalidieren,
  // damit Riverpod sie frisch aus SQLite nachlädt. Wichtig: nur wenn
  // `lastPullApplied > 0` — sonst Endlos-Loop, weil das Invalidate die
  // Provider neu baut, deren `ref.listen` in main.dart wiederum einen
  // neuen Sync schedult.
  DateTime? lastSeen;
  ref.listen<AsyncValue<SyncStatus>>(syncStatusProvider, (prev, next) {
    final status = next.valueOrNull;
    if (status == null) return;
    if (status.state != SyncState.idle) return;
    final ts = status.lastSuccessAt;
    if (ts == null || ts == lastSeen) return;
    lastSeen = ts;
    if (status.lastPullApplied == 0) return;
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[CloudSync] pulled ${status.lastPullApplied} rows '
        '— invalidating data providers',
      );
    }
    ref.invalidate(spotProvider);
    ref.invalidate(waterbodyProvider);
    ref.invalidate(catchProvider);
    ref.invalidate(tripProvider);
    ref.invalidate(missionProvider);
    ref.invalidate(manualWaterDaysProvider);
  });

  if (enabled) {
    // Kurz warten, damit andere Provider (z.B. AuthState) sich gesetzt haben.
    Future.delayed(const Duration(milliseconds: 250), () {
      unawaited(svc.syncNow());
    });
  }
});
