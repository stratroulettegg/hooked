import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/onboarding_service.dart';

/// Mehrseitiges Onboarding mit 5 Stationen, das beim ersten Start
/// erscheint. Setzt auf Story + Animation statt Feature-Bingo:
/// 1. Willkommen
/// 2. Local-First (Datenhoheit)
/// 3. Predator-Score (USP)
/// 4. Was du dokumentieren kannst
/// 5. Account-Erklärung & Start
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  int _index = 0;

  late final AnimationController _bgCtrl;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.waves_rounded,
      accent: ApexColors.primary,
      title: 'Willkommen bei Hooked',
      subtitle: 'Dein digitales Fangbuch',
      body:
          'Speichere jeden Fang. Plane jeden Trip. Lies, wann gebissen wird – '
          'mit einer App, die für Raubfischangler gemacht ist.',
      kind: _PageKind.welcome,
    ),
    _OnboardingPageData(
      icon: Icons.lock_outline_rounded,
      accent: ApexColors.scoreHigh,
      title: 'Local-First',
      subtitle: 'Deine Daten bleiben bei dir',
      body:
          'Alle Fänge, Spots und Trips speichert Hooked direkt auf deinem '
          'Gerät. Kein Login zum Loslegen, keine Cloud-Pflicht, kein '
          'Werbe-Tracking. Du entscheidest, was geteilt wird.',
      kind: _PageKind.local,
    ),
    _OnboardingPageData(
      icon: Icons.bolt_rounded,
      accent: ApexColors.strike,
      title: 'Predator-Score',
      subtitle: 'Live-Bewertung der Bedingungen',
      body:
          'Luftdruck, Wind, Mondphase, Wassertrübung – Hooked rechnet in '
          'Echtzeit aus, wie aktiv Hecht, Zander & Barsch gerade sein '
          'dürften. So weißt du, wann es sich lohnt.',
      kind: _PageKind.score,
    ),
    _OnboardingPageData(
      icon: Icons.map_rounded,
      accent: ApexColors.primary,
      title: 'Fänge · Spots · Trips',
      subtitle: 'Alles, was ein Angeltag braucht',
      body:
          'Dokumentiere Fänge mit Foto, Köder und Wetter. Markiere Spots auf '
          'der Karte. Plane Trips und behalte deine Statistiken im Blick.',
      kind: _PageKind.features,
    ),
    _OnboardingPageData(
      icon: Icons.people_rounded,
      accent: ApexColors.scoreMid,
      title: 'Werde Teil der Community.',
      subtitle: 'Mit Account dabei, ohne geht\'s auch',
      body:
          'Teile Fänge im Feed, sieh was andere Angler fangen und '
          'kommentiere Beiträge. Mit einem kostenlosen Account bist du '
          'dabei — ohne Account nutzt du Hooked einfach als privates '
          'Fangtagebuch.',
      kind: _PageKind.account,
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({bool goToAuth = false}) async {
    HapticFeedback.mediumImpact();
    await OnboardingService.markSeen();
    if (!mounted) return;
    if (goToAuth) {
      context.go('/auth');
    } else {
      context.go('/');
    }
  }

  void _next() {
    HapticFeedback.lightImpact();
    _controller.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final activeAccent = _pages[_index].accent;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // Animierter Hintergrund: zwei sanft floatende Glow-Orbs.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgCtrl,
              builder: (_, __) => CustomPaint(
                painter: _OrbPainter(
                  t: _bgCtrl.value,
                  accent: activeAccent,
                  background: c.background,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top-Leiste: Fortschritt + Überspringen
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ProgressDots(
                          count: _pages.length,
                          active: _index,
                          accent: activeAccent,
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _isLast ? 0 : 1,
                        duration: const Duration(milliseconds: 220),
                        child: TextButton(
                          onPressed: _isLast ? null : _finish,
                          style: TextButton.styleFrom(
                            foregroundColor: c.textSecondary,
                          ),
                          child: const Text('Überspringen'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Seiten mit 3D-Tilt-Übergang
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                    },
                    itemBuilder: (context, i) {
                      return AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          double delta;
                          if (_controller.position.haveDimensions) {
                            delta = (_controller.page ?? _index.toDouble()) - i;
                          } else {
                            delta = (_index - i).toDouble();
                          }
                          final clamped = delta.clamp(-1.0, 1.0);
                          final scale = 1 - clamped.abs() * 0.06;
                          final tilt = clamped * 0.18;
                          final opacity = 1 - clamped.abs() * 0.35;
                          return Opacity(
                            opacity: opacity.clamp(0.0, 1.0),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0011)
                                ..rotateY(tilt)
                                ..scaleByDouble(scale, scale, 1, 1),
                              child: child,
                            ),
                          );
                        },
                        child: _OnboardingPage(data: _pages[i]),
                      );
                    },
                  ),
                ),

                // Aktions-Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: _isLast
                      ? _FinalActions(
                          onLogin: () => _finish(goToAuth: true),
                          onSkip: () => _finish(),
                        )
                      : _NextAction(accent: activeAccent, onNext: _next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hintergrund-Orbs ───────────────────────────────────────────────────────

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.accent,
    required this.background,
  });

  final double t;
  final Color accent;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    Offset orb(double phase) {
      final angle = (t + phase) * 2 * math.pi;
      return Offset(
        w * (0.5 + 0.32 * math.cos(angle)),
        h * (0.42 + 0.18 * math.sin(angle)),
      );
    }

    void drawOrb(Offset center, double radius, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(center, radius, paint);
    }

    drawOrb(orb(0.0), 240, accent);
    drawOrb(orb(0.5), 200, ApexColors.primary);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t || old.accent != accent;
}

// ─── Page-Inhalt ────────────────────────────────────────────────────────────

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});
  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _HeroIcon(icon: data.icon, accent: data.accent, kind: data.kind)
              .animate(key: ValueKey('hero-${data.title}'))
              .fadeIn(duration: 480.ms, curve: Curves.easeOut)
              .scaleXY(
                begin: 0.6,
                end: 1.0,
                duration: 700.ms,
                curve: Curves.elasticOut,
              )
              .then(delay: 200.ms)
              .shimmer(
                duration: 1400.ms,
                color: Colors.white.withValues(alpha: 0.6),
              ),
          const SizedBox(height: 36),
          Text(
                data.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              )
              .animate(key: ValueKey('title-${data.title}'))
              .fadeIn(delay: 220.ms, duration: 380.ms)
              .slideY(
                begin: 0.25,
                end: 0,
                delay: 220.ms,
                duration: 520.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 8),
          Text(
                data.subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: data.accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              )
              .animate(key: ValueKey('sub-${data.title}'))
              .fadeIn(delay: 380.ms, duration: 360.ms)
              .slideY(
                begin: 0.3,
                end: 0,
                delay: 380.ms,
                duration: 520.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 20),
          Text(
                data.body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: c.textSecondary,
                  height: 1.45,
                ),
              )
              .animate(key: ValueKey('body-${data.title}'))
              .fadeIn(delay: 540.ms, duration: 460.ms)
              .slideY(
                begin: 0.18,
                end: 0,
                delay: 540.ms,
                duration: 520.ms,
                curve: Curves.easeOutCubic,
              ),
          if (data.kind == _PageKind.local) ...[
            const SizedBox(height: 22),
            _Badge(
                  icon: Icons.cloud_off_rounded,
                  label: 'Kein Community-Zwang',
                  accent: data.accent,
                )
                .animate(key: ValueKey('badge-local-${data.title}'))
                .fadeIn(delay: 720.ms, duration: 380.ms)
                .slideY(
                  begin: 0.4,
                  end: 0,
                  delay: 720.ms,
                  duration: 480.ms,
                  curve: Curves.easeOutCubic,
                ),
          ],
          if (data.kind == _PageKind.account) ...[
            const SizedBox(height: 22),
            _Badge(
                  icon: Icons.lock_open_rounded,
                  label: 'Account jederzeit später möglich',
                  accent: data.accent,
                )
                .animate(key: ValueKey('badge-acc-${data.title}'))
                .fadeIn(delay: 720.ms, duration: 380.ms)
                .slideY(
                  begin: 0.4,
                  end: 0,
                  delay: 720.ms,
                  duration: 480.ms,
                  curve: Curves.easeOutCubic,
                ),
          ],
        ],
      ),
    );
  }
}

// ─── Hero-Icon mit page-spezifischer Deko ───────────────────────────────────

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({
    required this.icon,
    required this.accent,
    required this.kind,
  });

  final IconData icon;
  final Color accent;
  final _PageKind kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow-Pulsring außen
          Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.25),
                      accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 0.92,
                end: 1.08,
                duration: 1800.ms,
                curve: Curves.easeInOut,
              ),
          // Mittlere Kachel
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
              border: Border.all(
                color: accent.withValues(alpha: 0.45),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, size: 64, color: accent),
          ),
          // page-spezifischer Decor
          if (kind == _PageKind.welcome) const _OrbitDots(),
          if (kind == _PageKind.score) const _ScoreSpark(),
          if (kind == _PageKind.local) const _ShieldRing(),
        ],
      ),
    );
  }
}

class _OrbitDots extends StatefulWidget {
  const _OrbitDots();

  @override
  State<_OrbitDots> createState() => _OrbitDotsState();
}

class _OrbitDotsState extends State<_OrbitDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 168,
          height: 168,
          child: Stack(
            children: List.generate(3, (i) {
              final angle = _ctrl.value * 2 * math.pi + i * 2.094;
              const r = 78.0;
              final x = 84 + r * math.cos(angle) - 4;
              final y = 84 + r * math.sin(angle) - 4;
              return Positioned(
                left: x,
                top: y,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ApexColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: ApexColors.primary.withValues(alpha: 0.7),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _ScoreSpark extends StatelessWidget {
  const _ScoreSpark();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 14,
      child:
          Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: ApexColors.scoreHigh,
              )
              .animate(onPlay: (c) => c.repeat())
              .fadeIn(duration: 500.ms)
              .then()
              .scaleXY(begin: 1.0, end: 1.4, duration: 700.ms)
              .then()
              .scaleXY(begin: 1.4, end: 1.0, duration: 700.ms),
    );
  }
}

class _ShieldRing extends StatelessWidget {
  const _ShieldRing();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
          width: 168,
          height: 168,
          child: CustomPaint(
            painter: _DashedRingPainter(color: ApexColors.scoreHigh),
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .rotate(duration: 14.seconds, begin: 0, end: 1);
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final r = size.width / 2 - 6;
    final center = Offset(size.width / 2, size.height / 2);
    const segments = 28;
    final sweep = (2 * math.pi) / segments * 0.55;
    for (int i = 0; i < segments; i++) {
      final start = (i * 2 * math.pi) / segments;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter old) => old.color != color;
}

// ─── Wiederverwendbares Badge ───────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.accent});
  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Progress-Dots ──────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.count,
    required this.active,
    required this.accent,
  });
  final int count;
  final int active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? accent : c.border,
            borderRadius: BorderRadius.circular(4),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

// ─── Aktionen ───────────────────────────────────────────────────────────────

class _NextAction extends StatelessWidget {
  const _NextAction({required this.accent, required this.onNext});
  final Color accent;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Weiter'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          delay: 1200.ms,
          duration: 1600.ms,
          color: Colors.white.withValues(alpha: 0.18),
        );
  }
}

class _FinalActions extends StatelessWidget {
  const _FinalActions({required this.onLogin, required this.onSkip});
  final VoidCallback onLogin;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Anmelden für Community-Features'),
                style: FilledButton.styleFrom(
                  backgroundColor: ApexColors.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            )
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(
              begin: 0.3,
              end: 0,
              duration: 480.ms,
              curve: Curves.easeOutCubic,
            ),
        const SizedBox(height: 10),
        SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: onSkip,
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('Direkt loslegen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            )
            .animate()
            .fadeIn(delay: 120.ms, duration: 400.ms)
            .slideY(
              begin: 0.3,
              end: 0,
              delay: 120.ms,
              duration: 480.ms,
              curve: Curves.easeOutCubic,
            ),
      ],
    );
  }
}

// ─── Daten ──────────────────────────────────────────────────────────────────

enum _PageKind { welcome, local, score, features, account }

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.kind,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String body;
  final _PageKind kind;
}
