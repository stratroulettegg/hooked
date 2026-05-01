import 'package:flutter/material.dart';
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
import '../../features/auth/auth_screen.dart';
import '../../features/auth/profile_screen.dart';
import '../../features/auth/edit_profile_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/models/trip.dart';
import '../../shared/services/onboarding_service.dart';
import '../../shared/widgets/quick_add_sheet.dart';
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
                  builder: (_, __) => const AddEditCatchScreen(),
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
                    final entry = state.extra as CatchEntry;
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
                  builder: (_, __) => const AddEditSpotScreen(),
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
                    final spot = state.extra as FishingSpot;
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

class _ScaffoldWithNavBar extends StatelessWidget {
  const _ScaffoldWithNavBar({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _QuickAddFab(
        onPressed: () => QuickAddSheet.show(context),
      ),
      bottomNavigationBar: _CenterDockedNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _QuickAddFab extends StatelessWidget {
  const _QuickAddFab({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: ApexColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: const CircleBorder(),
        tooltip: 'Schnell erfassen',
        child: const Icon(Icons.add, size: 32),
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
      child: InkWell(
        onTap: onTap,
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
