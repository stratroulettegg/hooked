import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'core/format/app_formats.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/services/app_paths.dart';
import 'shared/services/app_providers.dart';
import 'shared/services/firebase/auth_providers.dart';
import 'shared/services/firebase/firebase_bootstrap.dart';
import 'shared/services/firebase/user_profile_service.dart';
import 'shared/services/notifications/notification_prefs.dart';
import 'shared/services/notifications/notification_scheduler.dart';
import 'shared/services/notifications/notification_service.dart';
import 'shared/services/onboarding_service.dart';
import 'shared/services/tile_cache_service.dart';
import 'shared/widgets/pb_celebration.dart';
import 'shared/widgets/rank_celebration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppPaths.init();
  await TileCacheService.init();
  await OnboardingService.init();
  await NotificationPrefs.init();
  await NotificationService.instance.init();
  await NotificationService.instance.refreshPermission();
  await FirebaseBootstrap.init();

  // Crashlytics nur einhängen, wenn Firebase verfügbar ist UND die native
  // Plugin-Seite registriert wurde. Auf iOS ist das erst nach `pod install`
  // der Fall; in dem Fall fällt der Bool-Lookup auf null und das Plugin
  // wirft AssertionError. Daher defensiv per try/catch absichern.
  var crashlyticsActive = false;
  if (FirebaseBootstrap.isAvailable) {
    try {
      // Nur in Release-Builds aufzeichnen — in Debug stören Stacktraces nur.
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
      crashlyticsActive = true;
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

  await initializeDateFormatting(appLocale, null);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: ApexApp()));
}

class ApexApp extends ConsumerWidget {
  const ApexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    // Beim Wechsel auf einen eingeloggten User Cloud-Trips wiederherstellen,
    // damit Trips nach dem Login auf einem neuen Gerät verfügbar sind.
    ref.listen(authStateProvider, (prev, next) {
      final uid = next.valueOrNull?.uid;
      if (uid == null) return;
      // Nur bei tatsächlichem Wechsel triggern.
      if (prev?.valueOrNull?.uid == uid) return;
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
      routerConfig: appRouter,
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
