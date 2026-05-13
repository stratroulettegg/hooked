import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/legal_urls.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart' show bootstrapFirebaseConnections;
import '../../shared/services/consent_service.dart';
import '../../shared/services/onboarding_service.dart';
import '../../shared/widgets/app_toast.dart';

/// Erster Bildschirm beim allerersten App-Start. Holt die Einwilligung in
/// technische Cloud-Verbindungen ein, *bevor* Firebase überhaupt
/// `signInAnonymously()` aufruft.
///
/// Visuell auf dem Niveau des Onboardings: floatende Glow-Orbs, animiertes
/// Hero-Icon, staggered Fade-Ins für Headline → Bullets → CTA.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  bool _busy = false;

  /// Default: Diagnose-Daten aus (echtes Opt-in nach EuGH Planet49 /
  /// Art. 4 Nr. 11 DSGVO). User kann hier am Consent-Screen direkt
  /// einschalten — bewusste, informierte Aktion.
  bool _diagOptIn = false;

  static const _accent = ApexColors.scoreHigh;

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
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      await ConsentService.grantTech();
      // Diagnose-Wahl *vor* Bootstrap setzen — der Bootstrap liest die
      // Flag und konfiguriert Crashlytics entsprechend.
      await ConsentService.setDiagnostics(_diagOptIn);
      // Firebase-Verbindungen erst *nach* erteiltem Consent aufbauen.
      await bootstrapFirebaseConnections();
      if (!mounted) return;
      if (OnboardingService.hasSeen) {
        context.go('/catches');
      } else {
        context.go('/onboarding');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Verbindung fehlgeschlagen. Bitte erneut versuchen.',
      );
      setState(() => _busy = false);
    }
  }

  Future<void> _openPrivacy() async {
    HapticFeedback.selectionClick();
    final ok = await launchUrl(
      Uri.parse(LegalUrls.privacy),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      AppToast.error(context, 'Link konnte nicht geöffnet werden.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // Animierter Hintergrund: zwei sanft floatende Glow-Orbs, identisch
          // zur Onboarding-Inszenierung.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgCtrl,
              builder: (_, __) => CustomPaint(
                painter: _OrbPainter(
                  t: _bgCtrl.value,
                  accent: _accent,
                  background: c.background,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child:
                        _HeroShield(accent: _accent)
                            .animate()
                            .fadeIn(duration: 420.ms, curve: Curves.easeOut)
                            .scaleXY(
                              begin: 0.65,
                              end: 1.0,
                              duration: 700.ms,
                              curve: Curves.elasticOut,
                            )
                            .then(delay: 200.ms)
                            .shimmer(
                              duration: 1400.ms,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                        'Bevor du loslegst',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 380.ms)
                      .slideY(
                        begin: 0.25,
                        end: 0,
                        delay: 200.ms,
                        duration: 520.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 6),
                  Text(
                        'Kurz, ehrlich, kein Account nötig.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 360.ms, duration: 360.ms)
                      .slideY(
                        begin: 0.3,
                        end: 0,
                        delay: 360.ms,
                        duration: 520.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ConsentBullet(
                                icon: Icons.smartphone_outlined,
                                title: 'Deine Daten bleiben lokal',
                                body:
                                    'Fänge, Spots und Trips speichert Hooked '
                                    'auf diesem Gerät — auch ohne Internet.',
                                accent: _accent,
                              )
                              .animate()
                              .fadeIn(delay: 540.ms, duration: 380.ms)
                              .slideY(
                                begin: 0.25,
                                end: 0,
                                delay: 540.ms,
                                duration: 480.ms,
                                curve: Curves.easeOutCubic,
                              ),
                          const SizedBox(height: 14),
                          _ConsentBullet(
                                icon: Icons.fingerprint,
                                title: 'Anonyme Geräte-Kennung',
                                body:
                                    'Damit deine Daten dir gehören (und du sie '
                                    'später bei Bedarf in die Cloud synchen '
                                    'kannst), legt Firebase eine zufällige '
                                    'Kennung an. Keine E-Mail, kein Name. '
                                    'Server in der EU.',
                                accent: _accent,
                              )
                              .animate()
                              .fadeIn(delay: 660.ms, duration: 380.ms)
                              .slideY(
                                begin: 0.25,
                                end: 0,
                                delay: 660.ms,
                                duration: 480.ms,
                                curve: Curves.easeOutCubic,
                              ),
                          const SizedBox(height: 14),
                          _ConsentBullet(
                                icon: Icons.block_flipped,
                                title: 'Kein Werbe-Tracking',
                                body:
                                    'Keine Werbe-IDs (IDFA / Android-AdID), '
                                    'kein Audience-Sharing, keine '
                                    'Drittanbieter-Profile.',
                                accent: _accent,
                              )
                              .animate()
                              .fadeIn(delay: 780.ms, duration: 380.ms)
                              .slideY(
                                begin: 0.25,
                                end: 0,
                                delay: 780.ms,
                                duration: 480.ms,
                                curve: Curves.easeOutCubic,
                              ),
                          const SizedBox(height: 14),
                          _DiagnosticsToggleBullet(
                                value: _diagOptIn,
                                accent: _accent,
                                onChanged: (v) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _diagOptIn = v);
                                },
                              )
                              .animate()
                              .fadeIn(delay: 880.ms, duration: 380.ms)
                              .slideY(
                                begin: 0.25,
                                end: 0,
                                delay: 880.ms,
                                duration: 480.ms,
                                curve: Curves.easeOutCubic,
                              ),
                          const SizedBox(height: 18),
                          Center(
                            child:
                                InkWell(
                                      onTap: _openPrivacy,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.open_in_new,
                                              size: 14,
                                              color: _accent,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Vollständige Datenschutzerklärung',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: _accent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .animate()
                                    .fadeIn(delay: 1000.ms, duration: 360.ms),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AcceptButton(
                        accent: _accent,
                        busy: _busy,
                        onTap: _accept,
                      )
                      .animate()
                      .fadeIn(delay: 1100.ms, duration: 420.ms)
                      .slideY(
                        begin: 0.3,
                        end: 0,
                        delay: 1100.ms,
                        duration: 480.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 8),
                  Text(
                        'Du kannst alle Einstellungen jederzeit in den Settings ändern.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      )
                      .animate()
                      .fadeIn(delay: 1240.ms, duration: 360.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Diagnose-Toggle-Bullet ─────────────────────────────────────────────────

/// Interaktive Bullet-Karte mit Switch — sammelt das Crashlytics-Opt-in
/// direkt am Consent-Screen ein. Default ist OFF; ein aktives Antippen
/// schaltet ein. Damit ist der EuGH-Planet49-Maßstab erfüllt (keine
/// vorausgewählte Einwilligung) und gleichzeitig viel sichtbarer als ein
/// versteckter Settings-Toggle.
class _DiagnosticsToggleBullet extends StatelessWidget {
  const _DiagnosticsToggleBullet({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: value ? 0.85 : 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: value
                  ? accent.withValues(alpha: 0.65)
                  : c.border,
              width: value ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: value
                    ? accent.withValues(alpha: 0.18)
                    : c.cardShadow,
                blurRadius: value ? 22 : 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: value ? 0.32 : 0.22),
                      accent.withValues(alpha: value ? 0.14 : 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withValues(alpha: value ? 0.55 : 0.35),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.bug_report_outlined,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Hilf, Hooked besser zu machen (optional)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value
                          ? 'Danke! Anonyme Absturzberichte und Nutzungs-'
                                'Statistiken (welche Bildschirme öffnest du, '
                                'welche Funktionen nutzt du) helfen uns, Bugs '
                                'zu finden und Features zu priorisieren. '
                                'Keine Fang-Daten, keine Standorte, keine '
                                'Inhalte.'
                          : 'Aus. Wenn du magst, schickt deine App anonym '
                                'Absturzberichte und Nutzungs-Statistiken — '
                                'reine Funnel-Daten, keine Inhalte. Hilft '
                                'uns, Hooked schneller besser zu machen.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.42,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Eigenständiger Switch — vom Card-Tap entkoppelt, damit der
              // User auch direkt am Switch togglen kann.
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                thumbColor: WidgetStatePropertyAll(
                  value ? Colors.white : null,
                ),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return accent;
                  return null;
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bullet-Karte ───────────────────────────────────────────────────────────

class _ConsentBullet extends StatelessWidget {
  const _ConsentBullet({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: c.cardShadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.42,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero-Schild ────────────────────────────────────────────────────────────

class _HeroShield extends StatelessWidget {
  const _HeroShield({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.28),
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
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                color: accent.withValues(alpha: 0.55),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(Icons.shield_outlined, size: 42, color: accent),
          ),
        ],
      ),
    );
  }
}

// ─── Hintergrund-Orbs (1:1 wie Onboarding) ─────────────────────────────────

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
        h * (0.36 + 0.18 * math.sin(angle)),
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

// ─── CTA-Button mit Glow ───────────────────────────────────────────────────

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 22,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: busy ? null : onTap,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            disabledBackgroundColor: accent.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      "Verstanden — los geht's",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 10),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
