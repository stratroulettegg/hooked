import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/format/app_formats.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/services/app_paths.dart';
import 'shared/services/app_providers.dart';
import 'shared/services/firebase/auth_providers.dart';
import 'shared/services/firebase/firebase_bootstrap.dart';
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
      // Best-effort, Fehler werden im Notifier geschluckt.
      // ignore: discarded_futures
      ref.read(tripProvider.notifier).restoreCloudTrips(uid);
    });

    // Beim Start (und bei Daten-Änderungen) reaktive Notifications prüfen
    // sowie Trip-Reminder neu planen.
    ref.listen(catchProvider, (_, next) {
      final catches = next.valueOrNull;
      final trips = ref.read(tripProvider).valueOrNull;
      if (catches == null || trips == null) return;
      // ignore: discarded_futures
      NotificationScheduler.instance.runStartupChecks(
        catches: catches,
        trips: trips,
      );
    });
    ref.listen(tripProvider, (_, next) {
      final trips = next.valueOrNull;
      if (trips == null) return;
      // ignore: discarded_futures
      NotificationScheduler.instance.rescheduleAllTrips(trips);
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
