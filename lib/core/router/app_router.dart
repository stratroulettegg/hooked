import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../features/catches/catch_list_screen.dart';
import '../../features/catches/add_edit_catch_screen.dart';
import '../../features/catches/catch_detail_screen.dart';
import '../../features/catches/voice/voice_quick_add_sheet.dart';
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
        onListPressed: () => QuickAddSheet.show(context),
        onMicPressed: () => VoiceQuickAddSheet.show(context),
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

class _QuickAddFab extends StatefulWidget {
  const _QuickAddFab({required this.onListPressed, required this.onMicPressed});
  final VoidCallback onListPressed;
  final VoidCallback onMicPressed;

  @override
  State<_QuickAddFab> createState() => _QuickAddFabState();
}

class _QuickAddFabState extends State<_QuickAddFab>
    with SingleTickerProviderStateMixin {
  static const double _fabSize = 64;
  static const double _satRadius = 96; // Abstand FAB-Mitte → Satellit-Mitte
  static const double _satSize = 64;

  final GlobalKey _fabKey = GlobalKey();
  late final AnimationController _ctrl;
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isOpen => _entry != null;

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final fabCtx = _fabKey.currentContext;
    if (fabCtx == null) return;
    final box = fabCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
    HapticFeedback.lightImpact();
    _entry = OverlayEntry(
      builder: (_) => _FanOverlay(
        animation: _ctrl,
        anchor: anchor,
        satRadius: _satRadius,
        satSize: _satSize,
        onScrimTap: _close,
        onListTap: () async {
          await _closeAnimated();
          if (mounted) widget.onListPressed();
        },
        onMicTap: () async {
          await _closeAnimated();
          if (mounted) widget.onMicPressed();
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _ctrl.forward(from: 0);
    setState(() {});
  }

  Future<void> _closeAnimated() async {
    if (_entry == null) return;
    try {
      await _ctrl.reverse();
    } catch (_) {}
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _close() {
    unawaited(_closeAnimated());
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _fabKey,
      width: _fabSize,
      height: _fabSize,
      child: Material(
        color: ApexColors.primary,
        shape: const CircleBorder(),
        elevation: 6,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Center(
              // Plus rotiert sanft auf 135° → wirkt wie ein Schließen-„×".
              child: Transform.rotate(
                angle: _ctrl.value * math.pi * 0.75,
                child: const Icon(Icons.add, size: 32, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vollbild-Overlay mit halbtransparentem Scrim und zwei Satelliten-FABs,
/// die sich animiert vom Plus-Button nach oben links / oben rechts
/// herausschieben.
class _FanOverlay extends StatelessWidget {
  const _FanOverlay({
    required this.animation,
    required this.anchor,
    required this.satRadius,
    required this.satSize,
    required this.onScrimTap,
    required this.onListTap,
    required this.onMicTap,
  });

  final Animation<double> animation;
  final Offset anchor;
  final double satRadius;
  final double satSize;
  final VoidCallback onScrimTap;
  final VoidCallback onListTap;
  final VoidCallback onMicTap;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOutBack.transform(animation.value.clamp(0.0, 1.0));
        final scrimAlpha = (animation.value * 130).clamp(0.0, 130.0).toInt();
        // Zielversatz: 135° (oben-links) und 45° (oben-rechts).
        // y nach oben = negativ.
        final dxLeft = -math.cos(math.pi / 4) * satRadius * t;
        final dyUp = -math.sin(math.pi / 4) * satRadius * t;
        final leftPos = Offset(anchor.dx + dxLeft, anchor.dy + dyUp);
        final rightPos = Offset(anchor.dx - dxLeft, anchor.dy + dyUp);
        return SizedBox(
          width: media.size.width,
          height: media.size.height,
          child: Stack(
            children: [
              // Scrim
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onScrimTap,
                  child: Container(color: Colors.black.withAlpha(scrimAlpha)),
                ),
              ),
              _Satellite(
                center: leftPos,
                size: satSize,
                scale: t.clamp(0.0, 1.0),
                opacity: animation.value.clamp(0.0, 1.0),
                icon: Icons.list_alt,
                background: ApexColors.primary,
                foreground: Colors.white,
                onTap: onListTap,
              ),
              _Satellite(
                center: rightPos,
                size: satSize,
                scale: t.clamp(0.0, 1.0),
                opacity: animation.value.clamp(0.0, 1.0),
                icon: Icons.mic,
                background: ApexColors.primary,
                foreground: Colors.white,
                onTap: onMicTap,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Satellite extends StatelessWidget {
  const _Satellite({
    required this.center,
    required this.size,
    required this.scale,
    required this.opacity,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final Offset center;
  final double size;
  final double scale;
  final double opacity;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final left = center.dx - size / 2;
    final top = center.dy - size / 2;
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: Icon(icon, color: foreground, size: 30),
              ),
            ),
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
