import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/onboarding/screens/onboarding_welcome_screen.dart';
import '../../features/onboarding/screens/onboarding_bundesland_screen.dart';
import '../../features/onboarding/screens/onboarding_goal_screen.dart';
import '../../features/onboarding/screens/onboarding_diagnosis_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/quiz/blitzrunde_screen.dart';

// Route-Namen als Konstanten
abstract class Routes {
  static const String splash = '/';
  static const String onboardingWelcome = '/onboarding/welcome';
  static const String onboardingBundesland = '/onboarding/bundesland';
  static const String onboardingGoal = '/onboarding/goal';
  static const String onboardingDiagnosis = '/onboarding/diagnosis';
  static const String home = '/home';
  static const String quiz = '/quiz';
  static const String simulation = '/simulation';
  static const String simulationResult = '/simulation/result';
  static const String flashcards = '/flashcards';
  static const String lexikon = '/lexikon';
  static const String lexikonDetail = '/lexikon/:fishId';
  static const String regelwerk = '/regelwerk';
  static const String leaderboard = '/leaderboard';
  static const String duell = '/duell';
  static const String profile = '/profile';
  static const String achievements = '/achievements';
  static const String settings = '/settings';
  static const String login = '/login';
  static const String register = '/register';
}

final appRouter = GoRouter(
  initialLocation: Routes.splash,
  debugLogDiagnostics: false,
  routes: [
    GoRoute(
      path: Routes.splash,
      builder: (context, state) => const _SplashPlaceholder(),
    ),
    GoRoute(
      path: Routes.onboardingWelcome,
      builder: (context, state) => const OnboardingWelcomeScreen(),
    ),
    GoRoute(
      path: Routes.onboardingBundesland,
      builder: (context, state) => const OnboardingBundeslandScreen(),
    ),
    GoRoute(
      path: Routes.onboardingGoal,
      builder: (context, state) => const OnboardingGoalScreen(),
    ),
    GoRoute(
      path: Routes.onboardingDiagnosis,
      builder: (context, state) => const OnboardingDiagnosisScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => _MainShell(child: child),
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: Routes.quiz,
          builder: (context, state) => const BlitzrundeScreen(),
        ),
        GoRoute(
          path: Routes.lexikon,
          builder: (context, state) => const _PlaceholderScreen(title: 'Fischlexikon'),
        ),
        GoRoute(
          path: Routes.leaderboard,
          builder: (context, state) => const _PlaceholderScreen(title: 'Rangliste'),
        ),
        GoRoute(
          path: Routes.profile,
          builder: (context, state) => const _PlaceholderScreen(title: 'Profil'),
        ),
      ],
    ),
    GoRoute(
      path: Routes.simulation,
      builder: (context, state) => const _PlaceholderScreen(title: 'Prüfungssimulation'),
    ),
    GoRoute(
      path: Routes.flashcards,
      builder: (context, state) => const _PlaceholderScreen(title: 'Karteikarten'),
    ),
    GoRoute(
      path: Routes.regelwerk,
      builder: (context, state) => const _PlaceholderScreen(title: 'Regelwerk'),
    ),
    GoRoute(
      path: Routes.achievements,
      builder: (context, state) => const _PlaceholderScreen(title: 'Achievements'),
    ),
    GoRoute(
      path: Routes.login,
      builder: (context, state) => const _PlaceholderScreen(title: 'Login'),
    ),
    GoRoute(
      path: Routes.register,
      builder: (context, state) => const _PlaceholderScreen(title: 'Registrieren'),
    ),
  ],
);

// Temporäre Platzhalter – werden Feature für Feature ersetzt

class _SplashPlaceholder extends StatelessWidget {
  const _SplashPlaceholder();

  @override
  Widget build(BuildContext context) {
    // Direkt zum Onboarding weiterleiten (Splash-Logik folgt)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go(Routes.onboardingWelcome);
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}

class _MainShell extends StatefulWidget {
  final Widget child;
  const _MainShell({required this.child});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _currentIndex = 0;

  static const _tabs = [
    Routes.home,
    Routes.quiz,
    Routes.lexikon,
    Routes.leaderboard,
    Routes.profile,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          context.go(_tabs[index]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.flash_on_outlined), selectedIcon: Icon(Icons.flash_on), label: 'Quiz'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Lexikon'),
          NavigationDestination(icon: Icon(Icons.leaderboard_outlined), selectedIcon: Icon(Icons.leaderboard), label: 'Rangliste'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
