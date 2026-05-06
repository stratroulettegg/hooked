import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/catches/catch_list_screen.dart';
import '../../features/catches/add_edit_catch_screen.dart';
import '../../features/catches/catch_detail_screen.dart';
import '../../features/spots/spot_list_screen.dart';
import '../../features/spots/add_edit_spot_screen.dart';
import '../../features/spots/spot_detail_screen.dart';
import '../../features/trips/trip_list_screen.dart';
import '../../features/trips/add_edit_trip_screen.dart';
import '../../features/trips/trip_detail_screen.dart';
import '../../features/missions/missions_screen.dart';
import '../../features/missions/lure_levels_screen.dart';
import '../../features/lexicon/lexicon_screen.dart';
import '../../features/forecast/forecast_screen.dart';
import '../../features/water_days/water_days_screen.dart';
import '../../features/records/records_screen.dart';
import '../../features/settings/notification_settings_screen.dart';
import '../../features/settings/blocked_users_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/profile_screen.dart';
import '../../features/auth/edit_profile_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/models/trip.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/firebase/moderation_service.dart';
import '../../shared/services/onboarding_service.dart';
import '../../shared/widgets/app_quick_add_fab.dart';
import '../theme/app_theme.dart';

final appRouter = GoRouter(
  initialLocation: '/catches',
  redirect: (context, state) {
    // Beim allerersten Start Onboarding zeigen.
    final goingToOnboarding = state.matchedLocation == '/onboarding';
    if (!OnboardingService.hasSeen && !goingToOnboarding) {
      return '/onboarding';
    }
    if (OnboardingService.hasSeen && goingToOnboarding) {
      return '/catches';
    }
    // Alte Home-Route auf Fänge umleiten.
    if (state.matchedLocation == '/') {
      return '/catches';
    }
    return null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _ScaffoldWithNavBar(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/catches',
              builder: (_, __) => const CatchListScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (context, state) {
                    final extra = state.extra;
                    if (extra is CatchEntry) {
                      return AddEditCatchScreen(prefill: extra);
                    }
                    return const AddEditCatchScreen();
                  },
                ),
                GoRoute(
                  path: 'edit',
                  builder: (context, state) {
                    final entry = state.extra as CatchEntry;
                    return AddEditCatchScreen(existing: entry);
                  },
                ),
                GoRoute(
                  path: 'detail',
                  builder: (context, state) {
                    final extra = state.extra;
                    if (extra is CatchDetailArgs) {
                      return CatchDetailScreen(
                        entry: extra.entry,
                        siblingIds: extra.siblingIds,
                      );
                    }
                    final entry = extra as CatchEntry;
                    return CatchDetailScreen(entry: entry);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/spots',
              builder: (_, __) => const SpotListScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (context, state) {
                    final extra = state.extra;
                    if (extra is Map) {
                      return AddEditSpotScreen(
                        prefillLat: extra['lat'] as double?,
                        prefillLng: extra['lng'] as double?,
                        prefillName: extra['name'] as String?,
                      );
                    }
                    return const AddEditSpotScreen();
                  },
                ),
                GoRoute(
                  path: 'edit',
                  builder: (context, state) {
                    final spot = state.extra as FishingSpot;
                    return AddEditSpotScreen(existing: spot);
                  },
                ),
                GoRoute(
                  path: 'detail',
                  builder: (context, state) {
                    final extra = state.extra;
                    if (extra is SpotDetailArgs) {
                      return SpotDetailScreen(
                        spot: extra.spot,
                        siblingIds: extra.siblingIds,
                      );
                    }
                    final spot = extra as FishingSpot;
                    return SpotDetailScreen(spot: spot);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/trips',
              builder: (_, __) => const TripListScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (_, __) => const AddEditTripScreen(),
                ),
                GoRoute(
                  path: 'edit',
                  builder: (context, state) {
                    final trip = state.extra as Trip;
                    return AddEditTripScreen(existing: trip);
                  },
                ),
                GoRoute(
                  path: 'detail',
                  builder: (context, state) {
                    final trip = state.extra as Trip;
                    return TripDetailScreen(trip: trip);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/forecast',
              builder: (_, __) => const ForecastScreen(),
            ),
          ],
        ),
      ],
    ),
    // Missionen — außerhalb der Shell, wird als Top-Level-Route gepusht
    GoRoute(path: '/missions', builder: (_, __) => const MissionsScreen()),
    GoRoute(path: '/lure-levels', builder: (_, __) => const LureLevelsScreen()),
    GoRoute(path: '/lexicon', builder: (_, __) => const LexiconScreen()),
    GoRoute(path: '/water-days', builder: (_, __) => const WaterDaysScreen()),
    GoRoute(path: '/records', builder: (_, __) => const RecordsScreen()),
    GoRoute(
      path: '/settings/notifications',
      builder: (_, __) => const NotificationSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/blocked',
      builder: (_, __) => const BlockedUsersScreen(),
    ),
    // Auth — außerhalb der Shell
    GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(
      path: '/profile/edit',
      builder: (_, __) => const EditProfileScreen(),
    ),
    // Onboarding — beim ersten Start
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
  ],
);

class _ScaffoldWithNavBar extends ConsumerStatefulWidget {
  const _ScaffoldWithNavBar({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<_ScaffoldWithNavBar> createState() =>
      _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<_ScaffoldWithNavBar> {
  DateTime? _lastShownHitAt;

  void _handleRateLimitHit(RateLimitHit? hit) {
    if (hit == null) return;
    // Nur zeigen, wenn seit letztem Snackbar mind. 1s vergangen ist und
    // der Hit erst kürzlich passiert ist (max 30s alt) – sonst zeigt sich
    // beim App-Start jeder alte Eintrag als "frisch" an.
    if (_lastShownHitAt == hit.at) return;
    if (DateTime.now().toUtc().difference(hit.at.toUtc()).inSeconds.abs() > 30) {
      return;
    }
    _lastShownHitAt = hit.at;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final msg = switch (hit.kind) {
      'posts' =>
        'Du hast in der letzten Stunde sehr viele Fänge geteilt. '
            'Versuch es später nochmal – dein letzter Beitrag wurde nicht veröffentlicht.',
      'comments' =>
        'Du kommentierst gerade sehr viel. Bitte mach eine kurze Pause – '
            'dein letzter Kommentar wurde nicht gespeichert.',
      'reports' =>
        'Du hast in der letzten Stunde viele Meldungen abgesendet. '
            'Bitte warte etwas, bevor du weitere Meldungen erstellst.',
      _ => 'Du hast ein Limit erreicht. Versuch es später nochmal.',
    };
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RateLimitHit?>>(rateLimitHitsProvider, (prev, next) {
      next.whenData(_handleRateLimitHit);
    });
    final navigationShell = widget.navigationShell;
    // Wenn die Tastatur offen ist, blenden wir NavBar und FAB komplett
    // aus. Sonst w\u00fcrde der Scaffold-Resize beide \u00fcber die Tastatur
    // hochschieben (h\u00e4sslich auf iOS) \u2013 und wenn wir den Resize
    // ausschalten, gibt es einen schwarzen Balken hinter der Tastatur.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    const dur = Duration(milliseconds: 220);
    const curve = Curves.easeOutCubic;
    return Scaffold(
      // Tap auf den Hintergrund (au\u00dferhalb von Eingabefeldern) schlie\u00dft
      // die Tastatur \u2013 sonst bleibt sie auf iOS h\u00e4ngen, weil iOS keine
      // automatische Done-Geste hat.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: navigationShell,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AnimatedScale(
        duration: dur,
        curve: curve,
        scale: keyboardOpen ? 0.0 : 1.0,
        child: AnimatedOpacity(
          duration: dur,
          curve: curve,
          opacity: keyboardOpen ? 0.0 : 1.0,
          child: const AppQuickAddFab(),
        ),
      ),
      bottomNavigationBar: AnimatedSize(
        duration: dur,
        curve: curve,
        alignment: Alignment.topCenter,
        child: keyboardOpen
            ? const SizedBox.shrink()
            : _CenterDockedNavBar(
                currentIndex: navigationShell.currentIndex,
                onTap: (i) => navigationShell.goBranch(
                  i,
                  initialLocation: i == navigationShell.currentIndex,
                ),
              ),
      ),
    );
  }
}

class _CenterDockedNavBar extends StatelessWidget {
  const _CenterDockedNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return BottomAppBar(
      color: c.surface,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      padding: EdgeInsets.zero,
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavItem(
            icon: Icons.phishing_outlined,
            selectedIcon: Icons.phishing,
            label: 'Fänge',
            selected: currentIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: 'Spots',
            selected: currentIndex == 1,
            onTap: () => onTap(1),
          ),
          // Lücke für den FAB
          const SizedBox(width: 64),
          _NavItem(
            icon: Icons.event_note_outlined,
            selectedIcon: Icons.event_note,
            label: 'Trips',
            selected: currentIndex == 2,
            onTap: () => onTap(2),
          ),
          _NavItem(
            icon: Icons.bolt_outlined,
            selectedIcon: Icons.bolt,
            label: 'Index',
            selected: currentIndex == 3,
            onTap: () => onTap(3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final color = selected ? ApexColors.primary : c.textMuted;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        // Standard-Splash der BottomAppBar ist bei uns ein heller Ton, der
        // sich beim Tippen kreisrund über das ganze Item legt und das Icon
        // kurzzeitig „weiß überdeckt". Wir nehmen einen dezenten Tint in
        // Primärfarbe und stellen das Highlight transparent, damit der
        // Button auch beim Drücken sichtbar bleibt.
        splashColor: ApexColors.primary.withAlpha(28),
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        radius: 36,
        containedInkWell: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
