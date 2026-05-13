import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/legal_urls.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/pro/pro_providers.dart';
import '../../shared/services/pro/revenuecat_bootstrap.dart';
import '../../shared/services/pro/revenuecat_service.dart';
import '../../shared/widgets/app_toast.dart';
import 'pro_gate.dart';

/// Paywall im Apex-Style. Stub-Phase: zeigt 3 Pricing-Cards (Monthly,
/// Yearly mit "Beliebt" + Free-Trial, Lifetime), Trust-Elemente (Restore,
/// AGB, Datenschutz). Solange RevenueCat noch nicht angeschlossen ist,
/// schaltet "Kaufen" den Mock-Pro-Status frei.
///
/// Wird als Bottom-Sheet via `showPaywall()` aus `pro_gate.dart` geöffnet
/// oder über die Route `/paywall` direkt (für Onboarding-Slot Nr. 6,
/// Settings-Eintrag etc.).
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.feature});

  /// Optional — wenn gesetzt, wird das Feature als Headline-Kontext oben
  /// im Paywall hervorgehoben („Pro für $featureTitle").
  final ProFeature? feature;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

enum _PlanTier { monthly, yearly, lifetime }

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  _PlanTier _selected = _PlanTier.yearly;
  bool _busy = false;

  /// Offering aus RevenueCat. `null`, wenn (a) RC nicht initialisiert
  /// (Mock-Modus) oder (b) Laden noch läuft / fehlgeschlagen.
  Offering? _offering;
  bool _offeringLoading = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logEvent(
      'paywall_view',
      params: widget.feature != null
          ? {'source': widget.feature!.analyticsKey}
          : null,
    );
    _loadOffering();
  }

  Future<void> _loadOffering() async {
    final off = await RevenueCatService.getCurrentOffering();
    if (!mounted) return;
    setState(() {
      _offering = off;
      _offeringLoading = false;
    });
  }

  /// Mappt einen [_PlanTier] auf ein [Package] aus dem RC-Offering.
  /// Reihenfolge: bevorzugt die typisierten RC-Slots (`monthly`, `annual`,
  /// `lifetime`), dann Lookup per Identifier (`hooked_pro_*`).
  Package? _packageFor(_PlanTier tier) {
    final off = _offering;
    if (off == null) return null;
    Package? byId(String id) {
      for (final p in off.availablePackages) {
        if (p.storeProduct.identifier == id ||
            p.identifier == id ||
            p.storeProduct.identifier.endsWith(id)) {
          return p;
        }
      }
      return null;
    }

    switch (tier) {
      case _PlanTier.monthly:
        return off.monthly ?? byId('hooked_pro_monthly');
      case _PlanTier.yearly:
        return off.annual ?? byId('hooked_pro_yearly');
      case _PlanTier.lifetime:
        return off.lifetime ?? byId('hooked_pro_lifetime');
    }
  }

  Future<void> _purchase() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      // Wenn RevenueCat live ist und ein Paket gefunden wurde, echten
      // Kauf durchziehen. Sonst (Mock-Modus) den Pro-Toggle umlegen,
      // damit man die App ohne Store-Anbindung trotzdem testen kann.
      final pkg = _packageFor(_selected);
      if (RevenueCatBootstrap.isAvailable && pkg != null) {
        final res = await RevenueCatService.purchase(pkg);
        if (!mounted) return;
        if (res.success) {
          AnalyticsService.logEvent(
            'paywall_purchase_succeeded',
            params: {'product_id': pkg.storeProduct.identifier},
          );
          await _showThankYou(tier: _selected);
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
        if (res.userCancelled) {
          setState(() => _busy = false);
          return;
        }
        AppToast.error(
          context,
          res.errorMessage ?? 'Kauf fehlgeschlagen – bitte erneut versuchen.',
        );
        setState(() => _busy = false);
        return;
      }

      // Mock-Pfad (RC nicht konfiguriert oder kein Paket gefunden).
      await ref.read(isProProvider.notifier).set(true);
      AnalyticsService.logEvent(
        'paywall_purchase_succeeded',
        params: {'product_id': _productIdFor(_selected), 'mock': 'true'},
      );
      if (!mounted) return;
      await _showThankYou(tier: _selected);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Kauf fehlgeschlagen: $e');
      setState(() => _busy = false);
    }
  }

  /// Zeigt den Danke-Dialog nach erfolgreichem Kauf. Blockiert bis der
  /// User auf „Los geht's" tippt oder den Dialog wegtappt.
  Future<void> _showThankYou({required _PlanTier tier}) async {
    HapticFeedback.lightImpact();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _ThankYouDialog(tier: tier),
    );
  }

  Future<void> _restore() async {
    HapticFeedback.selectionClick();
    AnalyticsService.logEvent('paywall_restored');
    if (!RevenueCatBootstrap.isAvailable) {
      AppToast.success(
        context,
        'Wiederherstellen ist verfügbar, sobald die Store-Anbindung live ist.',
      );
      return;
    }
    setState(() => _busy = true);
    final res = await RevenueCatService.restore();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      Navigator.of(context).pop(true);
      AppToast.success(context, 'Pro wiederhergestellt.');
    } else {
      AppToast.show(
        context,
        res.errorMessage ?? 'Keine aktiven Käufe gefunden.',
      );
    }
  }

  Future<void> _openLink(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      AppToast.error(context, 'Link konnte nicht geöffnet werden.');
    }
  }

  String _productIdFor(_PlanTier t) {
    switch (t) {
      case _PlanTier.monthly:
        return 'hooked_pro_monthly';
      case _PlanTier.yearly:
        return 'hooked_pro_yearly';
      case _PlanTier.lifetime:
        return 'hooked_pro_lifetime';
    }
  }

  /// Baut die drei Pricing-Cards. Nutzt — falls vorhanden — die echten
  /// lokalisierten Preisstrings aus dem RevenueCat-Offering. Im Mock-Modus
  /// fallen die Cards auf hardcoded EUR-Preise zur\u00fcck.
  List<Widget> _buildPlanCards() {
    String priceFor(_PlanTier t, String fallback) {
      final pkg = _packageFor(t);
      return pkg?.storeProduct.priceString ?? fallback;
    }

    // Titel aus RC-Dashboard (localizedTitle) nutzen, Fallback auf
    // hardcodierte Strings falls Store-Daten noch nicht verfügbar sind
    // (z.B. Sandbox ohne Store-Produkte).
    String titleFor(_PlanTier t, String fallback) {
      final title = _packageFor(t)?.storeProduct.title;
      return (title != null && title.isNotEmpty) ? title : fallback;
    }

    final cards = <Widget>[
      _PlanCard(
        tier: _PlanTier.yearly,
        title: titleFor(_PlanTier.yearly, 'Jahresabo'),
        price: priceFor(_PlanTier.yearly, '24,99 \u20ac'),
        priceSuffix: ' / Jahr',
        footnote: '~ 2,08 \u20ac / Monat \u00b7 7 Tage gratis testen',
        badge: 'BELIEBT',
        selected: _selected == _PlanTier.yearly,
        onTap: () => setState(() => _selected = _PlanTier.yearly),
      ),
      const SizedBox(height: 10),
      _PlanCard(
        tier: _PlanTier.monthly,
        title: titleFor(_PlanTier.monthly, 'Monatsabo'),
        price: priceFor(_PlanTier.monthly, '2,99 \u20ac'),
        priceSuffix: ' / Monat',
        footnote: 'Jederzeit k\u00fcndbar',
        selected: _selected == _PlanTier.monthly,
        onTap: () => setState(() => _selected = _PlanTier.monthly),
      ),
      const SizedBox(height: 10),
      _PlanCard(
        tier: _PlanTier.lifetime,
        title: titleFor(_PlanTier.lifetime, 'Einmalkauf'),
        price: priceFor(_PlanTier.lifetime, '49,99 \u20ac'),
        priceSuffix: ' einmalig',
        footnote: 'Lebenslang Pro \u00b7 kein Abo',
        selected: _selected == _PlanTier.lifetime,
        onTap: () => setState(() => _selected = _PlanTier.lifetime),
      ),
    ];
    if (_offeringLoading) {
      cards.add(const SizedBox(height: 8));
      cards.add(
        const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ApexColors.primary,
            ),
          ),
        ),
      );
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // Animierte Orbs im Hintergrund (wie Onboarding)
          Positioned.fill(child: _PaywallOrbBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                // Schließen-Button rechts oben
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(Icons.close, color: c.textMuted, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 12),
                // Hero-Bereich
                _PaywallHero(feature: widget.feature)
                    .animate()
                    .fadeIn(duration: 480.ms)
                    .scaleXY(
                      begin: 0.88,
                      end: 1.0,
                      duration: 600.ms,
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: 28),
                // Benefits
                _BenefitsList()
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 400.ms)
                    .slideY(
                      begin: 0.2,
                      end: 0,
                      delay: 200.ms,
                      duration: 480.ms,
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: 20),
                // Plan-Cards
                ..._buildPlanCards().asMap().entries.map((e) {
                  final i = e.key;
                  final w = e.value;
                  return w
                      .animate()
                      .fadeIn(
                        delay: Duration(milliseconds: 320 + i * 70),
                        duration: 380.ms,
                      )
                      .slideX(
                        begin: 0.12,
                        end: 0,
                        delay: Duration(milliseconds: 320 + i * 70),
                        duration: 440.ms,
                        curve: Curves.easeOutCubic,
                      );
                }),
                const SizedBox(height: 24),
                // CTA-Button mit Glow
                _GlowCta(
                  busy: _busy,
                  selected: _selected,
                  onPressed: _purchase,
                )
                    .animate()
                    .fadeIn(delay: 560.ms, duration: 400.ms)
                    .slideY(
                      begin: 0.15,
                      end: 0,
                      delay: 560.ms,
                      duration: 440.ms,
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _restore,
                    child: Text(
                      'Käufe wiederherstellen',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ),
                ).animate().fadeIn(delay: 680.ms, duration: 360.ms),
                const SizedBox(height: 4),
                _LegalFooter(onOpen: _openLink)
                    .animate()
                    .fadeIn(delay: 740.ms, duration: 360.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Animierter Orb-Hintergrund (identisch mit Onboarding) ─────────────────

class _PaywallOrbBackground extends StatefulWidget {
  @override
  State<_PaywallOrbBackground> createState() => _PaywallOrbBackgroundState();
}

class _PaywallOrbBackgroundState extends State<_PaywallOrbBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _OrbPainter(
          t: _ctrl.value,
          accent: ApexColors.primary,
          background: c.background,
        ),
      ),
    );
  }
}

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
        w * (0.5 + 0.28 * math.cos(angle)),
        h * (0.28 + 0.14 * math.sin(angle)),
      );
    }

    void drawOrb(Offset center, double radius, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(center, radius, paint);
    }

    drawOrb(orb(0.0), w * 0.7, accent);
    drawOrb(orb(0.5), w * 0.55, ApexColors.strike.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t || old.accent != accent;
}

// ─── Hero-Bereich ────────────────────────────────────────────────────────────

class _PaywallHero extends StatefulWidget {
  const _PaywallHero({required this.feature});
  final ProFeature? feature;

  @override
  State<_PaywallHero> createState() => _PaywallHeroState();
}

class _PaywallHeroState extends State<_PaywallHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final f = widget.feature;
    final icon = f?.icon ?? Icons.workspace_premium_rounded;
    const accent = ApexColors.primary;

    return Column(
      children: [
        // Glow-Icon
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final scale = 0.92 + 0.08 * _pulse.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: 0.22 * _pulse.value),
                          accent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Inner circle
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.13),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.4),
                        blurRadius: 32,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 52, color: accent),
                ),
                // Orbit dots
                _OrbitDots(),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        // "HOOKED PRO" Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: const Text(
            'HOOKED PRO',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
              color: ApexColors.primary,
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(period: 3.seconds))
            .shimmer(duration: 1600.ms, color: accent.withValues(alpha: 0.5)),
        const SizedBox(height: 14),
        if (f != null) ...[
          Text(
            f.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: -0.3,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            f.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: c.textSecondary,
              height: 1.4,
            ),
          ),
        ] else ...[
          Text(
            'Hol mehr aus deinem\nFangtagebuch',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cloud-Backup · Trip-Sharing · 7-Tage-Forecast',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: c.textMuted,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ],
    );
  }
}

// Orbit-Dots (aus Onboarding übernommen)
class _OrbitDots extends StatefulWidget {
  @override
  State<_OrbitDots> createState() => _OrbitDotsState();
}

class _OrbitDotsState extends State<_OrbitDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
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
      builder: (_, __) => SizedBox(
        width: 140,
        height: 140,
        child: Stack(
          children: List.generate(3, (i) {
            final angle = _ctrl.value * 2 * math.pi + i * 2.094;
            const r = 64.0;
            final x = 70 + r * math.cos(angle) - 4;
            final y = 70 + r * math.sin(angle) - 4;
            return Positioned(
              left: x,
              top: y,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ApexColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: ApexColors.primary.withValues(alpha: 0.8),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─── Glow-CTA-Button ────────────────────────────────────────────────────────

class _GlowCta extends StatelessWidget {
  const _GlowCta({
    required this.busy,
    required this.selected,
    required this.onPressed,
  });
  final bool busy;
  final _PlanTier selected;
  final VoidCallback onPressed;

  String get _label => switch (selected) {
        _PlanTier.yearly => '7 Tage gratis testen',
        _PlanTier.lifetime => 'Einmalig freischalten',
        _PlanTier.monthly => 'Pro abonnieren',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: ApexColors.primary.withValues(alpha: 0.45),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
        gradient: const LinearGradient(
          colors: [ApexColors.primary, Color(0xFF00E0A0)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    _label,
                    style: const TextStyle(
                      fontFamily: 'Rajdhani',
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: 0.8,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          begin: 1.0,
          end: 1.015,
          duration: 1600.ms,
          curve: Curves.easeInOut,
        );
  }
}




class _BenefitsList extends StatelessWidget {
  static const _benefits = [
    ('Foto-Cloud-Backup', Icons.cloud_done_rounded),
    ('Unbegrenzt Trips (statt 3)', Icons.route_rounded),
    ('Trip-Sharing mit Buddies', Icons.group_add_rounded),
    ('7-Tage-Predator-Forecast', Icons.calendar_view_week_rounded),
    ('Werbefrei für immer', Icons.block_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ApexColors.primary.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: ApexColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < _benefits.length; i++) ...[
            _BenefitRow(
              icon: _benefits[i].$2,
              label: _benefits[i].$1,
            ),
            if (i < _benefits.length - 1)
              Divider(
                height: 18,
                color: ApexColors.primary.withValues(alpha: 0.12),
              ),
          ],
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Row(
      children: [
        Icon(icon, color: ApexColors.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Icon(Icons.check_rounded, size: 18, color: ApexColors.primary),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tier,
    required this.title,
    required this.price,
    required this.priceSuffix,
    required this.footnote,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final _PlanTier tier;
  final String title;
  final String price;
  final String priceSuffix;
  final String footnote;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final borderColor = selected ? ApexColors.primary : c.border;
    final bgColor = selected
        ? ApexColors.primary.withValues(alpha: 0.10)
        : c.surface.withValues(alpha: 0.85);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: bgColor,
        border: Border.all(
          color: borderColor,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: ApexColors.primary.withValues(alpha: 0.22),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _RadioDot(selected: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    ApexColors.primary,
                                    Color(0xFF00E0A0),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: price,
                              style: TextStyle(
                                color: selected
                                    ? ApexColors.primary
                                    : c.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Rajdhani',
                                letterSpacing: 0.4,
                              ),
                            ),
                            TextSpan(
                              text: priceSuffix,
                              style: TextStyle(
                                color: c.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        footnote,
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? ApexColors.primary : c.border,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: ApexColors.primary,
              ),
            )
          : null,
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter({required this.onOpen});

  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    Widget link(String label, String url) => TextButton(
          onPressed: () => onOpen(url),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            label,
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Abos verlängern sich automatisch, falls nicht spätestens 24 h '
            'vor Ablauf gekündigt. Die Verwaltung erfolgt im App Store / '
            'Play Store. Zahlung wird beim Bestätigen über deinen Store-Account '
            'abgebucht.',
            style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            link('Datenschutz', LegalUrls.privacy),
            Text('·', style: TextStyle(color: c.textMuted)),
            link('Impressum', LegalUrls.imprint),
          ],
        ),
      ],
    );
  }
}

// ─── Danke-Dialog nach erfolgreichem Kauf ──────────────────────────────────

class _ThankYouDialog extends StatelessWidget {
  const _ThankYouDialog({required this.tier});

  final _PlanTier tier;

  String get _subtitle => switch (tier) {
        _PlanTier.yearly =>
          'Deine 7 Tage Probezeit laufen — danach Hooked Pro für ein ganzes Jahr.',
        _PlanTier.lifetime =>
          'Lebenslang Hooked Pro. Kein Abo, kein Ablauf — einfach angeln.',
        _PlanTier.monthly =>
          'Hooked Pro ist freigeschaltet. Verlängert sich monatlich, jederzeit kündbar.',
      };

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    const accent = ApexColors.primary;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Hintergrund-Orbs (statisch, dezent)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OrbPainter(
                    t: 0.12,
                    accent: accent,
                    background: c.background,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glow-Check-Icon
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [accent, Color(0xFF00E0A0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.55),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 56,
                      color: Colors.black,
                    ),
                  )
                      .animate()
                      .scaleXY(
                        begin: 0.4,
                        end: 1.0,
                        duration: 520.ms,
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(duration: 240.ms),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.45)),
                    ),
                    child: const Text(
                      'HOOKED PRO',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                        color: accent,
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(period: 3.seconds))
                      .shimmer(
                        duration: 1600.ms,
                        color: accent.withValues(alpha: 0.5),
                      ),
                  const SizedBox(height: 14),
                  Text(
                    'Danke, Captain!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                      letterSpacing: -0.4,
                      height: 1.1,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 320.ms)
                      .slideY(
                        begin: 0.2,
                        end: 0,
                        delay: 200.ms,
                        duration: 360.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: c.textSecondary,
                      height: 1.4,
                    ),
                  ).animate().fadeIn(delay: 320.ms, duration: 320.ms),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        gradient: const LinearGradient(
                          colors: [accent, Color(0xFF00E0A0)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(13),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).pop();
                          },
                          child: const Center(
                            child: Text(
                              "Los geht's",
                              style: TextStyle(
                                fontFamily: 'Rajdhani',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 460.ms, duration: 320.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
