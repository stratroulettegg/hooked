import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../models/catch_entry.dart';

/// Was wurde gerade übertroffen?
enum PbKind { weight, length, both }

/// Daten für eine Personal-Best-Party.
class PbEvent {
  const PbEvent({
    required this.species,
    required this.kind,
    required this.newWeightG,
    required this.newLengthCm,
    required this.previousWeightG,
    required this.previousLengthCm,
  });

  final FishSpecies species;
  final PbKind kind;
  final int? newWeightG;
  final double? newLengthCm;
  final int? previousWeightG;
  final double? previousLengthCm;
}

/// Globaler Controller — erlaubt das Auslösen der PB-Party von überall.
final pbCelebrationControllerProvider = Provider<PbCelebrationController>(
  (_) => PbCelebrationController(),
);

class PbCelebrationController {
  final ValueNotifier<PbEvent?> current = ValueNotifier<PbEvent?>(null);

  /// Vergleicht alten Bestand mit dem neuen Fang und löst ggf. die Party aus.
  /// `previousCatches` darf den neuen Fang nicht enthalten.
  void maybeTrigger({
    required CatchEntry newEntry,
    required Iterable<CatchEntry> previousCatches,
  }) {
    int? prevW;
    double? prevL;
    for (final c in previousCatches) {
      if (c.species != newEntry.species) continue;
      if (c.weightG != null && c.weightG! > (prevW ?? 0)) prevW = c.weightG;
      if (c.lengthCm != null && c.lengthCm! > (prevL ?? 0)) prevL = c.lengthCm;
    }
    final beatsW =
        newEntry.weightG != null && prevW != null && newEntry.weightG! > prevW;
    final beatsL =
        newEntry.lengthCm != null &&
        prevL != null &&
        newEntry.lengthCm! > prevL;
    if (!beatsW && !beatsL) return;

    final kind = beatsW && beatsL
        ? PbKind.both
        : beatsW
        ? PbKind.weight
        : PbKind.length;
    current.value = PbEvent(
      species: newEntry.species,
      kind: kind,
      newWeightG: newEntry.weightG,
      newLengthCm: newEntry.lengthCm,
      previousWeightG: prevW,
      previousLengthCm: prevL,
    );
  }

  void dismiss() => current.value = null;
}

/// Wrapper, der die App umschließt und bei neuen PBs Konfetti zeigt.
class PbCelebrationHost extends ConsumerWidget {
  const PbCelebrationHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(pbCelebrationControllerProvider);
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        ValueListenableBuilder<PbEvent?>(
          valueListenable: controller.current,
          builder: (_, evt, __) {
            if (evt == null) return const SizedBox.shrink();
            return _PbOverlay(
              key: ValueKey(
                '${evt.species}-${evt.kind}-${evt.newWeightG}-${evt.newLengthCm}',
              ),
              event: evt,
              onDismiss: controller.dismiss,
            );
          },
        ),
      ],
    );
  }
}

// ─── Overlay ────────────────────────────────────────────────────────────────

class _PbOverlay extends StatefulWidget {
  const _PbOverlay({super.key, required this.event, required this.onDismiss});
  final PbEvent event;
  final VoidCallback onDismiss;

  @override
  State<_PbOverlay> createState() => _PbOverlayState();
}

class _PbOverlayState extends State<_PbOverlay> with TickerProviderStateMixin {
  late final AnimationController _cardCtrl;
  late final AnimationController _confettiCtrl;
  late final AnimationController _fadeCtrl;
  late final List<_Particle> _particles;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..forward();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );
    final rnd = Random();
    _particles = List.generate(80, (_) => _Particle.random(rnd));
    Future.delayed(const Duration(milliseconds: 2800), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _fadeCtrl.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _confettiCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: Container(color: Colors.black.withAlpha(140)),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confettiCtrl,
                  builder: (_, __) => CustomPaint(
                    painter: _ConfettiPainter(
                      progress: _confettiCtrl.value,
                      particles: _particles,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: _cardCtrl,
                  curve: Curves.elasticOut,
                ),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _cardCtrl,
                    curve: const Interval(0, 0.4, curve: Curves.easeOut),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: _PbCard(event: widget.event),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PbCard extends StatelessWidget {
  const _PbCard({required this.event});
  final PbEvent event;

  String _formatWeight(int g) =>
      g >= 1000 ? AppNum.kg(g) : '$g g';

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final e = event;

    final lines = <Widget>[];
    if (e.kind == PbKind.weight || e.kind == PbKind.both) {
      lines.add(
        _StatRow(
          label: 'GEWICHT',
          newValue: _formatWeight(e.newWeightG!),
          oldValue: e.previousWeightG != null
              ? _formatWeight(e.previousWeightG!)
              : null,
        ),
      );
    }
    if (e.kind == PbKind.length || e.kind == PbKind.both) {
      lines.add(
        _StatRow(
          label: 'LÄNGE',
          newValue: AppNum.cm(e.newLengthCm!),
          oldValue: e.previousLengthCm != null
              ? AppNum.cm(e.previousLengthCm!)
              : null,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 36),
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ApexColors.primaryDark, c.surfaceVariant],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ApexColors.primary, width: 2),
        boxShadow: [
          BoxShadow(
            color: ApexColors.primary.withAlpha(120),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'NEUER PB',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              color: ApexColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('🏆', style: TextStyle(fontSize: 50)),
          ),
          const SizedBox(height: 16),
          Text(
            e.species.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: ApexColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...lines,
          const SizedBox(height: 4),
          Text(
            'Stark gemacht!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.newValue,
    required this.oldValue,
  });
  final String label;
  final String newValue;
  final String? oldValue;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                if (oldValue != null) ...[
                  TextSpan(
                    text: oldValue,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  TextSpan(
                    text: '  →  ',
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                ],
                TextSpan(
                  text: newValue,
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ApexColors.primary,
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

// ─── Confetti ───────────────────────────────────────────────────────────────

class _Particle {
  _Particle({
    required this.x,
    required this.vy,
    required this.vx,
    required this.color,
    required this.size,
    required this.rotSpeed,
    required this.startDelay,
  });

  final double x;
  final double vy;
  final double vx;
  final Color color;
  final double size;
  final double rotSpeed;
  final double startDelay;

  static final _palette = <Color>[
    const Color(0xFFFFD54F),
    const Color(0xFF4FC3F7),
    const Color(0xFFFF7043),
    const Color(0xFFAED581),
    const Color(0xFFBA68C8),
    ApexColors.primary,
  ];

  factory _Particle.random(Random r) => _Particle(
    x: r.nextDouble(),
    vy: 1.0 + r.nextDouble() * 0.7,
    vx: (r.nextDouble() - 0.5) * 0.4,
    color: _palette[r.nextInt(_palette.length)],
    size: 6.0 + r.nextDouble() * 6.0,
    rotSpeed: (r.nextDouble() - 0.5) * 8.0,
    startDelay: r.nextDouble() * 0.25,
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.particles});

  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final t = progress - p.startDelay;
      if (t <= 0) continue;
      final dx = (p.x + p.vx * t) * size.width;
      final dy = (-0.08 + p.vy * t * 1.35) * size.height;
      if (dy > size.height + 40) continue;
      final rot = t * p.rotSpeed;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rot);
      paint.color = p.color;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.5,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
