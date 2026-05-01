import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-Navigation für Screens außerhalb der StatefulShellRoute
/// (z. B. Profil, Missionen). Verwendet `context.go` um in einen der
/// Haupt-Tabs zu wechseln.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  static const _routes = ['/catches', '/spots', '/trips', '/forecast'];

  @override
  Widget build(BuildContext context) {
    // Fallback, falls dieser BottomNav unter einem klassischen Navigator.push
    // gerendert wird (z. B. Lexikon-Detail) — dann gibt es keinen
    // GoRouterState im Subtree.
    String location = '/catches';
    try {
      location = GoRouterState.of(context).matchedLocation;
    } catch (_) {
      try {
        location = GoRouter.of(
          context,
        ).routerDelegate.currentConfiguration.uri.path;
      } catch (_) {}
    }
    final idx = _routes.indexWhere((r) => location.startsWith(r));

    return NavigationBar(
      selectedIndex: idx >= 0 ? idx : 0,
      onDestinationSelected: (i) => context.go(_routes[i]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.phishing_outlined),
          selectedIcon: Icon(Icons.phishing),
          label: 'Fänge',
        ),
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'Spots',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note),
          label: 'Trips',
        ),
        NavigationDestination(
          icon: Icon(Icons.bolt_outlined),
          selectedIcon: Icon(Icons.bolt),
          label: 'Index',
        ),
      ],
    );
  }
}
