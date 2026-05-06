import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Bottom-Navigation für Screens außerhalb der StatefulShellRoute
/// (z. B. Profil, Missionen). Gleicher Stil wie _CenterDockedNavBar
/// im Router, aber ohne FAB-Lücke.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  static const _routes = ['/catches', '/spots', '/trips', '/forecast'];

  @override
  Widget build(BuildContext context) {
    String location = '/catches';
    try {
      location = GoRouterState.of(context).matchedLocation;
    } catch (_) {
      try {
        location =
            GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
      } catch (_) {}
    }
    final idx = _routes.indexWhere((r) => location.startsWith(r));
    final c = ApexColors.of(context);

    return BottomAppBar(
      color: c.surface,
      padding: EdgeInsets.zero,
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _AppNavItem(
            icon: Icons.phishing_outlined,
            selectedIcon: Icons.phishing,
            label: 'Fänge',
            selected: idx == 0,
            onTap: () => context.go(_routes[0]),
          ),
          _AppNavItem(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: 'Spots',
            selected: idx == 1,
            onTap: () => context.go(_routes[1]),
          ),
          _AppNavItem(
            icon: Icons.event_note_outlined,
            selectedIcon: Icons.event_note,
            label: 'Trips',
            selected: idx == 2,
            onTap: () => context.go(_routes[2]),
          ),
          _AppNavItem(
            icon: Icons.bolt_outlined,
            selectedIcon: Icons.bolt,
            label: 'Index',
            selected: idx == 3,
            onTap: () => context.go(_routes[3]),
          ),
        ],
      ),
    );
  }
}

class _AppNavItem extends StatelessWidget {
  const _AppNavItem({
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
