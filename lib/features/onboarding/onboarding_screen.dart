import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/onboarding_service.dart';

/// Mehrseitiges Onboarding, das beim ersten App-Start gezeigt wird.
/// Stellt die vier Hauptbereiche vor (Fänge, Spots, Trips, Index) und
/// bietet am Ende optional die Anmeldung an — benötigt wird sie nur für
/// das Teilen von Trips.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.waves_rounded,
      accent: ApexColors.primary,
      title: 'Willkommen bei Hooked',
      subtitle: 'Dein digitales Fangbuch',
      body:
          'Plane deine Raubfisch-Trips, halte Fänge fest und lies ab, wann die '
          'Beißchancen am höchsten sind – alles in einer App.',
    ),
    _OnboardingPageData(
      icon: Icons.phishing,
      accent: ApexColors.strike,
      title: 'Fänge',
      subtitle: 'Jeder Biss zählt',
      body:
          'Dokumentiere jeden Fang mit Art, Größe, Köder, Wetter und Foto. '
          'Deine Statistik wächst automatisch mit.',
    ),
    _OnboardingPageData(
      icon: Icons.map_rounded,
      accent: ApexColors.primary,
      title: 'Spots',
      subtitle: 'Deine Hotspots auf der Karte',
      body:
          'Speichere Stellen mit GPS, Notizen und Fotos. Beim nächsten Trip '
          'siehst du auf einen Blick, wo es sich lohnt.',
    ),
    _OnboardingPageData(
      icon: Icons.event_note_rounded,
      accent: ApexColors.scoreMid,
      title: 'Trips',
      subtitle: 'Geplant & optional geteilt',
      body:
          'Plane Angelausflüge, fasse Fänge pro Trip zusammen und teile sie '
          'bei Bedarf mit Angelkumpels – dafür brauchst du einen Account.',
      highlightLogin: true,
    ),
    _OnboardingPageData(
      icon: Icons.bolt_rounded,
      accent: ApexColors.scoreHigh,
      title: 'Index',
      subtitle: 'Predator-Score in Echtzeit',
      body:
          'Luftdruck, Wind, Mond, Wassertrübung – Hooked berechnet laufend, '
          'wie aktiv Hecht, Zander & Barsch gerade sein dürften.',
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  Future<void> _finish({bool goToAuth = false}) async {
    await OnboardingService.markSeen();
    if (!mounted) return;
    if (goToAuth) {
      context.go('/auth');
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top-Leiste: Fortschritt + Überspringen
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _ProgressDots(count: _pages.length, active: _index),
                  ),
                  TextButton(
                    onPressed: _finish,
                    style: TextButton.styleFrom(
                      foregroundColor: c.textSecondary,
                    ),
                    child: const Text('Überspringen'),
                  ),
                ],
              ),
            ),

            // Seiten
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _OnboardingPage(data: _pages[i]),
              ),
            ),

            // Aktions-Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _isLast
                  ? _FinalActions(onFinish: _finish)
                  : _NextAction(
                      onNext: () => _controller.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Seiten-Widget ───────────────────────────────────────────────────────────

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});
  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon-Kachel
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.accent.withValues(alpha: 0.12),
              border: Border.all(
                color: data.accent.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: Icon(data.icon, size: 64, color: data.accent),
          ),
          const SizedBox(height: 36),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: data.accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 20),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: c.textSecondary,
                  height: 1.4,
                ),
          ),
          if (data.highlightLogin) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: c.textMuted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Anmeldung nur für das Teilen von Trips nötig',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.textMuted,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Progress-Dots ───────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? ApexColors.primary : c.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ─── Aktionen ────────────────────────────────────────────────────────────────

class _NextAction extends StatelessWidget {
  const _NextAction({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onNext,
        style: FilledButton.styleFrom(
          backgroundColor: ApexColors.primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        child: const Text('Weiter'),
      ),
    );
  }
}

class _FinalActions extends StatelessWidget {
  const _FinalActions({required this.onFinish});
  final Future<void> Function({bool goToAuth}) onFinish;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: () => onFinish(goToAuth: true),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Anmelden'),
            style: FilledButton.styleFrom(
              backgroundColor: ApexColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => onFinish(),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textPrimary,
              side: BorderSide(color: c.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Ohne Anmeldung starten'),
          ),
        ),
      ],
    );
  }
}

// ─── Datenklasse ─────────────────────────────────────────────────────────────

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.body,
    this.highlightLogin = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String body;
  final bool highlightLogin;
}
