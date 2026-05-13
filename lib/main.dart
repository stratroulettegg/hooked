import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'core/format/app_formats.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/services/analytics_service.dart';
import 'shared/services/app_paths.dart';
import 'shared/services/app_providers.dart';
import 'shared/services/consent_service.dart';
import 'shared/services/pro/mock_pro_service.dart';
import 'shared/services/pro/revenuecat_bootstrap.dart';
import 'shared/services/firebase/auth_providers.dart';
import 'shared/services/firebase/firebase_bootstrap.dart';
import 'shared/services/firebase/user_profile_providers.dart';
import 'shared/services/firebase/user_profile_service.dart';
import 'shared/services/local_database_service.dart';
import 'shared/services/local_db_anchor.dart';
import 'features/water_days/water_days_providers.dart';
import 'shared/services/notifications/notification_prefs.dart';
import 'shared/services/notifications/notification_scheduler.dart';
import 'shared/services/notifications/notification_service.dart';
import 'shared/services/notifications/push_token_service.dart';
import 'shared/services/onboarding_service.dart';
import 'shared/services/sync/sync_providers.dart';
import 'shared/services/tile_cache_service.dart';
import 'shared/widgets/pb_celebration.dart';
import 'shared/widgets/rank_celebration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppPaths.init();
  await TileCacheService.init();
  await OnboardingService.init();
  await ConsentService.init();
  await MockProService.init();
  // RevenueCat (purchases_flutter): wenn keine Keys per --dart-define
  // gesetzt sind, läuft die App ohne Store-Anbindung weiter und nutzt
  // den Mock-Status (Settings-Toggle in Debug). Siehe docs/MONETIZATION.md.
  await RevenueCatBootstrap.init();
  await LocalDbAnchor.init();
  await NotificationPrefs.init();
  await NotificationService.instance.init();
  await NotificationService.instance.refreshPermission();
  await FirebaseBootstrap.init();

  // Firebase-Verbindungen (anonyme Auth, FCM-Token-Registrierung,
  // Crashlytics) erzeugen vom ersten Start an Telemetrie an Google.
  // Nach § 25 TTDSG / Art. 6 DSGVO ist das einwilligungspflichtig — bis
  // der User auf dem Consent-Screen zugestimmt hat, läuft die App rein
  // lokal im `__noauth__`-Slot.
  if (FirebaseBootstrap.isAvailable && ConsentService.techGranted) {
    await bootstrapFirebaseConnections();
  }

  // Lokale DB & Photos auf den aktuellen User scopen. Fallback-Slot
  // `__noauth__`, solange noch kein Consent erteilt wurde oder Firebase
  // nicht verfügbar ist (Offline-Bootstrap, fehlende Konfiguration).
  // Echte User-Daten liegen dann sauber in `apex_<uid>.db` bzw.
  // `<docs>/photos/<uid>/`.
  //
  // DB-Anker (siehe [LocalDbAnchor]) bestimmt den Slot stickier als der
  // aktuelle Firebase-User: nach `signOut()` oder Cold-Restart mit
  // frischer Anon-Session bleibt der DB-Slot des letzten bekannten
  // Anker-Users aktiv — lokale Fänge/Spots/Trips bleiben sichtbar, der
  // Anwender kann sich mit demselben Account wieder einloggen, um
  // Cloud-Sync fortzusetzen.
  String bootstrapUid;
  if (FirebaseBootstrap.isAvailable && ConsentService.techGranted) {
    final fbUid = FirebaseAuth.instance.currentUser?.uid;
    final anchor = LocalDbAnchor.value;
    if (anchor != null) {
      bootstrapUid = anchor;
    } else if (fbUid != null) {
      bootstrapUid = fbUid;
      await LocalDbAnchor.set(fbUid);
    } else {
      bootstrapUid = '__noauth__';
    }
  } else {
    bootstrapUid = '__noauth__';
  }
  await AppPaths.activateForUid(bootstrapUid);
  await LocalDatabaseService().activateForUid(bootstrapUid);

  // Crashlytics nur einhängen, wenn (a) Firebase verfügbar, (b) der User
  // Diagnose-Daten freigeschaltet hat und (c) die native Plugin-Seite
  // registriert wurde. Ohne Diagnose-Consent darf Crashlytics auch in
  // Release-Builds keine Daten sammeln.
  var crashlyticsActive = false;
  if (FirebaseBootstrap.isAvailable) {
    try {
      final wantCollect = !kDebugMode && ConsentService.diagnosticsGranted;
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        wantCollect,
      );
      crashlyticsActive = wantCollect;
    } catch (e, st) {
      debugPrint('Crashlytics init skipped: $e\n$st');
    }
  }

  if (crashlyticsActive) {
    // Globaler Error-Handler für sonst unbehandelte Framework-Fehler.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    // Globaler Error-Handler für Async-Errors außerhalb des Frameworks.
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Unhandled async error: $error\n$stack');
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } else {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Unhandled async error: $error\n$stack');
      return true;
    };
  }

  // Analytics: derselbe Diagnose-Consent steuert Crashlytics + Analytics.
  // Ohne Diagnose-Consent bleibt Collection aus; in Debug-Builds immer aus.
  if (FirebaseBootstrap.isAvailable) {
    await AnalyticsService.bootstrap();
  }

  await initializeDateFormatting(appLocale, null);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: ApexApp()));
}

/// Stellt sicher, dass eine Firebase-Auth-Identität existiert (anonym
/// oder echt) und startet die FCM-Token-Pipeline.
///
/// Wird einmal in `main()` aufgerufen, sobald Tech-Consent vorliegt — und
/// erneut vom Consent-Screen, wenn der User dort *zustimmt*. Idempotent.
Future<void> bootstrapFirebaseConnections() async {
  if (!FirebaseBootstrap.isAvailable) return;
  // Sorgt dafür, dass IMMER ein User vorhanden ist — entweder bereits
  // eingeloggt (Apple/Google) oder neu anonym. Vorbedingung dafür,
  // dass die SQLite-DB ab Tag 1 user-scoped läuft.
  await FirebaseBootstrap.ensureSignedIn();
  // FCM-Token-Lifecycle starten: registriert auf Auth-State-Changes,
  // pushed Token in /userProfiles/{uid}/fcmTokens/.
  await PushTokenService.instance.init();
  // Crashlytics + Analytics aufbauen / Collection-Flag aus aktuellem
  // Diagnose-Consent ableiten. Wenn der User vom Consent-Screen aus
  // gerade „Hilf uns besser werden" angetippt hat, fließt das hier in
  // beide Systeme zugleich — ein Schalter, ein Wille.
  try {
    final wantCollect = !kDebugMode && ConsentService.diagnosticsGranted;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      wantCollect,
    );
  } catch (_) {
    // Native Plugin nicht registriert — egal.
  }
  await AnalyticsService.bootstrap();
}

class ApexApp extends ConsumerStatefulWidget {
  const ApexApp({super.key});

  @override
  ConsumerState<ApexApp> createState() => _ApexAppState();
}

class _ApexAppState extends ConsumerState<ApexApp> {
  // Router GENAU EINMAL beim ersten Mount lesen und festhalten. So
  // bleibt die GoRouter-Instanz (und ihr interner GlobalKey für die
  // StatefulNavigationShell) für die gesamte App-Laufzeit stabil,
  // egal wie oft ApexApp wegen Theme-/Listen-Änderungen rebuild.
  late final GoRouter _router = ref.read(appRouterProvider);

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    // Cloud-Sync Orchestrator: startet einen initialen Sync, sobald
    // Pro-Status + Login + Firebase verfügbar sind.
    ref.watch(cloudSyncOrchestratorProvider);

    // Beim Wechsel auf einen eingeloggten User Cloud-Trips wiederherstellen,
    // damit Trips nach dem Login auf einem neuen Gerät verfügbar sind.
    ref.listen(authStateProvider, (prev, next) {
      final user = next.valueOrNull;
      final uid = user?.uid;
      final prevUserEarly = prev?.valueOrNull;

      // Logout-Edge-Case: signOut() lässt den Auth-State auf `null`
      // fallen (kein Auto-Anon-Login). Ohne Behandlung würde der Listener
      // hier early-returnen und der DB-Anker bliebe auf der UID des
      // soeben abgemeldeten Users hängen → der Ex-User würde nach dem
      // Logout weiter seine eigenen Fänge sehen. Wir wechseln daher
      // proaktiv zurück auf den zuvor gemerkten Anon-Slot (oder, falls
      // keiner gemerkt wurde, geben den Anker frei, damit der nächste
      // Login frisch aktiviert).
      if (uid == null &&
          prevUserEarly != null &&
          prevUserEarly.isAnonymous == false) {
        final fallbackUid = LocalDbAnchor.previousAnonUid;
        unawaited(() async {
          try {
            if (fallbackUid != null) {
              await LocalDbAnchor.set(fallbackUid);
              await AppPaths.activateForUid(fallbackUid);
              await LocalDatabaseService().activateForUid(fallbackUid);
            } else {
              await LocalDbAnchor.clear();
            }
            await LocalDbAnchor.clearPreviousAnonUid();
            ref.invalidate(catchProvider);
            ref.invalidate(spotProvider);
            ref.invalidate(waterbodyProvider);
            ref.invalidate(tripProvider);
            ref.invalidate(manualWaterDaysProvider);
          } catch (e, st) {
            debugPrint('logout DB restore: $e\n$st');
          }
        }());
        unawaited(RevenueCatBootstrap.logout());
        return;
      }

      if (uid == null) return;
      // Nur bei tatsächlichem Wechsel triggern.
      if (prev?.valueOrNull?.uid == uid) return;

      // DB-Anker-Logik: der lokale DB-Slot soll nur dann auf eine neue
      // UID umschalten, wenn der User sich wirklich in einen *anderen*
      // Account einloggt — oder wenn er sich aus einem echten Account
      // *ausloggt* und in eine Anon-Session zurückfällt (dann zurück auf
      // die zuvor gemerkte Anon-UID, sonst auf die neue Anon-UID).
      //
      // Regeln:
      //   - kein Anker                       → setzen (egal anon/echt)
      //   - Anker == uid                     → noop
      //   - Anker != uid, user echt          → Account-Wechsel:
      //                                        Anker updaten + DB switchen.
      //                                        Falls vorheriger User anon
      //                                        war → Anon-UID als
      //                                        previousAnonUid sichern.
      //   - Anker != uid, user anon,
      //     vorheriger User echt             → Logout-Event:
      //                                        Anker auf previousAnonUid
      //                                        zurücksetzen (oder, falls
      //                                        keiner gemerkt, auf die
      //                                        aktuelle Anon-UID).
      //   - Anker != uid, user anon,
      //     vorheriger User auch anon        → Anker behalten (Cold-
      //                                        Restart, frische Anon-
      //                                        Session).
      final anchor = LocalDbAnchor.value;
      final prevUser = prev?.valueOrNull;
      final isLogout =
          prevUser != null &&
          prevUser.isAnonymous == false &&
          user!.isAnonymous == true;

      String? targetUid;
      if (anchor == null) {
        targetUid = uid;
      } else if (user!.isAnonymous == false && anchor != uid) {
        // Echter Login → echter Login bzw. anon → echt.
        // Wenn der Vorgänger anonym war, dessen UID als preLogin merken,
        // damit ein späterer Logout darauf zurückspringen kann.
        if (prevUser != null && prevUser.isAnonymous == true) {
          unawaited(LocalDbAnchor.setPreviousAnonUid(prevUser.uid));
        }
        targetUid = uid;
      } else if (isLogout && anchor != uid) {
        // echt → anon: zurück auf den vorherigen Anon-Slot, falls
        // gemerkt; sonst auf die neue Anon-UID (frischer Slot).
        targetUid = LocalDbAnchor.previousAnonUid ?? uid;
        unawaited(LocalDbAnchor.clearPreviousAnonUid());
      }

      if (targetUid == null) {
        // Auch ohne DB-Switch: RC weiter informieren (s.u.).
        unawaited(RevenueCatBootstrap.identify(uid));
        return;
      }

      // ZUERST DB & Photos auf die Ziel-UID umschalten — alle folgenden
      // Provider-Reads landen sonst noch in der DB des Vorgängers und
      // verursachen Daten-Kontamination zwischen Accounts auf demselben
      // Gerät. Anschließend abhängige Notifier invalidieren.
      final dbUid = targetUid;
      unawaited(() async {
        try {
          await LocalDbAnchor.set(dbUid);
          await AppPaths.activateForUid(dbUid);
          await LocalDatabaseService().activateForUid(dbUid);
          ref.invalidate(catchProvider);
          ref.invalidate(spotProvider);
          ref.invalidate(waterbodyProvider);
          ref.invalidate(tripProvider);
        } catch (e, st) {
          debugPrint('activateForUid: $e\n$st');
        }
      }());

      // RevenueCat: App-User-ID auf Firebase-UID setzen, damit
      // Käufe auf allen Geräten desselben Accounts gelten. Auch für
      // anonyme Nutzer sinnvoll (Trial → später echter Account via
      // linkWithCredential läuft bei RC sauber durch).
      unawaited(RevenueCatBootstrap.identify(uid));

      // Cloud-Aktionen NUR für echte (nicht-anonyme) User: anonyme
      // Auto-Login-Sessions haben keinen öffentlichen Profil-Eintrag und
      // keine Cloud-Trips — wir würden sonst ungewollt Müll-Profile in
      // /userProfiles/ anlegen.
      if (user?.isAnonymous == false) {
        // Best-effort, Fehler werden zusätzlich geloggt.
        unawaited(() async {
          try {
            await ref.read(tripProvider.notifier).restoreCloudTrips(uid);
          } catch (e, st) {
            debugPrint('restoreCloudTrips: $e\n$st');
          }
        }());
        // Öffentliches User-Profil sicherstellen, damit fremde User uns
        // sofort finden und der gespiegelte Avatar/Name aktuell bleibt.
        unawaited(() async {
          try {
            await UserProfileService.instance.ensureMyProfileExists();
          } catch (e, st) {
            debugPrint('ensureMyProfileExists: $e\n$st');
          }
        }());
      }
    });

    // Account-Integrity: Wenn das eigene Profil-Doc plötzlich verschwindet
    // (z.B. weil der Account auf einem anderen Gerät gelöscht wurde), ist
    // der Auth-User serverseitig weg — Phone B bemerkt das nicht von
    // selbst, weil das ID-Token noch ~1h gültig bleibt. Wir verifizieren
    // per `user.reload()` und werfen den lokalen Auth-State raus, damit
    // die App nahtlos in eine frische Anon-Session zurückfällt.
    ref.listen(myProfileProvider, (prev, next) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return;
      // Nur prüfen, wenn der Stream tatsächlich `null` geliefert hat
      // (Doc fehlt) — Loading/Error nicht.
      if (!next.hasValue || next.valueOrNull != null) return;
      unawaited(() async {
        try {
          await user.reload();
          // Reload OK → Doc fehlt nur wirklich (z.B. Setup nicht
          // abgeschlossen). Nichts tun, Setup-Gate übernimmt.
        } on FirebaseAuthException catch (e) {
          const goneCodes = {
            'user-not-found',
            'user-token-expired',
            'invalid-user-token',
            'user-disabled',
          };
          if (goneCodes.contains(e.code) || e.code.contains('token')) {
            debugPrint(
              '[Auth] account gone server-side (${e.code}) → '
              'signing out and re-anonymizing',
            );
            try {
              await FirebaseAuth.instance.signOut();
            } catch (_) {}
            try {
              await FirebaseAuth.instance.signInAnonymously();
            } catch (e2) {
              debugPrint('post-gone signInAnonymously failed: $e2');
            }
            try {
              ref.read(appRouterProvider).go('/catches');
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('account integrity reload: $e');
        }
      }());
    });

    // Beim Start (und bei Daten-Änderungen) reaktive Notifications prüfen
    // sowie Trip-Reminder neu planen.
    ref.listen(catchProvider, (_, next) {
      final catches = next.valueOrNull;
      final trips = ref.read(tripProvider).valueOrNull;
      if (catches == null || trips == null) return;
      unawaited(() async {
        try {
          await NotificationScheduler.instance.runStartupChecks(
            catches: catches,
            trips: trips,
          );
        } catch (e, st) {
          debugPrint('notifications runStartupChecks: $e\n$st');
        }
      }());
    });
    ref.listen(tripProvider, (_, next) {
      final trips = next.valueOrNull;
      if (trips == null) return;
      unawaited(() async {
        try {
          await NotificationScheduler.instance.rescheduleAllTrips(trips);
        } catch (e, st) {
          debugPrint('notifications rescheduleAllTrips: $e\n$st');
        }
      }());
    });

    // Cloud-Sync: bei jedem Schreibvorgang in einer sync-relevanten Tabelle
    // einen debounced Sync einplanen. Der CloudSyncService prüft selbst,
    // ob ein User eingeloggt und Pro aktiv ist — bei Free-Usern ist das
    // ein günstiger No-Op.
    void scheduleSyncIfEnabled() {
      if (!ref.read(cloudSyncEnabledProvider)) return;
      ref.read(cloudSyncServiceProvider).scheduleSync();
    }

    ref.listen(catchProvider, (_, _) => scheduleSyncIfEnabled());
    ref.listen(spotProvider, (_, _) => scheduleSyncIfEnabled());
    ref.listen(waterbodyProvider, (_, _) => scheduleSyncIfEnabled());
    ref.listen(tripProvider, (_, _) => scheduleSyncIfEnabled());
    ref.listen(missionProvider, (_, _) => scheduleSyncIfEnabled());

    SystemChrome.setSystemUIOverlayStyle(
      isDark
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: ApexColors.systemSurfaceDark,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarColor: ApexColors.systemSurfaceLight,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
    );

    return MaterialApp.router(
      title: 'Hooked',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: _router,
      // Die App ist nur auf Deutsch verfügbar — Material/Cupertino/Widgets-
      // Localizations sorgen dafür, dass DatePicker, TimePicker, Tooltips,
      // Wochentags-Kürzel etc. auf Deutsch erscheinen.
      locale: const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) => PbCelebrationHost(
        child: RankCelebrationHost(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
