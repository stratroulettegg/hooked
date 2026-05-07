import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import 'revier_stats.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTIKEL-SYSTEM (Glitter / Funken)
// ═══════════════════════════════════════════════════════════════════════════

class _Particle {
  const _Particle({
    required this.x,
    required this.speed,
    required this.size,
    required this.colorIdx,
    required this.phase,
    this.wobble = 8.0,
  });
  final double x; // 0..1 relative x start
  final double speed; // float-up speed factor
  final double size; // radius in dp
  final int colorIdx; // 0=teal 1=orange 2=ice
  final double phase; // animation phase offset 0..1
  final double wobble; // horizontal sway in dp
}

const _kParticles = [
  _Particle(
    x: 0.07,
    speed: 0.20,
    size: 2.0,
    colorIdx: 0,
    phase: 0.00,
    wobble: 6,
  ),
  _Particle(
    x: 0.20,
    speed: 0.15,
    size: 1.5,
    colorIdx: 1,
    phase: 0.17,
    wobble: 10,
  ),
  _Particle(
    x: 0.34,
    speed: 0.24,
    size: 3.0,
    colorIdx: 2,
    phase: 0.33,
    wobble: 5,
  ),
  _Particle(
    x: 0.50,
    speed: 0.17,
    size: 1.5,
    colorIdx: 0,
    phase: 0.50,
    wobble: 8,
  ),
  _Particle(
    x: 0.65,
    speed: 0.21,
    size: 2.5,
    colorIdx: 1,
    phase: 0.66,
    wobble: 12,
  ),
  _Particle(
    x: 0.80,
    speed: 0.14,
    size: 2.0,
    colorIdx: 2,
    phase: 0.82,
    wobble: 7,
  ),
  _Particle(
    x: 0.13,
    speed: 0.26,
    size: 1.5,
    colorIdx: 1,
    phase: 0.42,
    wobble: 9,
  ),
  _Particle(
    x: 0.44,
    speed: 0.18,
    size: 2.0,
    colorIdx: 0,
    phase: 0.28,
    wobble: 6,
  ),
  _Particle(
    x: 0.58,
    speed: 0.23,
    size: 1.5,
    colorIdx: 2,
    phase: 0.61,
    wobble: 11,
  ),
  _Particle(
    x: 0.73,
    speed: 0.19,
    size: 3.0,
    colorIdx: 0,
    phase: 0.08,
    wobble: 8,
  ),
  _Particle(
    x: 0.29,
    speed: 0.16,
    size: 1.5,
    colorIdx: 1,
    phase: 0.90,
    wobble: 5,
  ),
  _Particle(
    x: 0.91,
    speed: 0.22,
    size: 2.0,
    colorIdx: 2,
    phase: 0.46,
    wobble: 10,
  ),
  _Particle(
    x: 0.38,
    speed: 0.13,
    size: 1.5,
    colorIdx: 0,
    phase: 0.72,
    wobble: 7,
  ),
  _Particle(
    x: 0.86,
    speed: 0.28,
    size: 1.5,
    colorIdx: 1,
    phase: 0.12,
    wobble: 6,
  ),
];

const _kParticleColors = [
  Color(0xFF00D4AA), // teal
  Color(0xFFFF6B35), // orange
  Color(0xFF90D8FF), // ice blue
];

class _ParticlePainter extends CustomPainter {
  const _ParticlePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _kParticles) {
      final t = (p.phase + progress * p.speed * 5) % 1.0;
      final opacity = math.sin(t * math.pi).clamp(0.0, 1.0);
      if (opacity < 0.02) continue;

      final x =
          p.x * size.width +
          math.sin(t * math.pi * 2.5 + p.phase * 8) * p.wobble;
      final y = size.height * (1.0 - t);

      canvas.drawCircle(
        Offset(x, y),
        p.size,
        Paint()
          ..color = _kParticleColors[p.colorIdx].withAlpha(
            (opacity * 195).round(),
          )
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

class _SparkleOverlay extends StatefulWidget {
  const _SparkleOverlay();

  @override
  State<_SparkleOverlay> createState() => _SparkleOverlayState();
}

class _SparkleOverlayState extends State<_SparkleOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) =>
            CustomPaint(painter: _ParticlePainter(progress: _ctrl.value)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HINTERGRUND-ORBS (langsam pulsierende Leuchtblobs)
// ═══════════════════════════════════════════════════════════════════════════

class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress;

    canvas.drawCircle(
      Offset(
        size.width * (0.25 + math.sin(t * math.pi) * 0.12),
        size.height * (0.35 + math.cos(t * math.pi * 0.8) * 0.08),
      ),
      130,
      Paint()
        ..color = const Color(0xFF00D4AA).withAlpha(22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90),
    );

    canvas.drawCircle(
      Offset(
        size.width * (0.75 + math.cos(t * math.pi * 1.2) * 0.12),
        size.height * (0.65 + math.sin(t * math.pi * 0.9) * 0.08),
      ),
      110,
      Paint()
        ..color = const Color(0xFFFF6B35).withAlpha(16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80),
    );

    canvas.drawCircle(
      Offset(
        size.width * (0.6 + math.sin(t * math.pi * 0.7 + 1.5) * 0.1),
        size.height * (0.25 + math.cos(t * math.pi * 1.1 + 0.5) * 0.08),
      ),
      90,
      Paint()
        ..color = const Color(0xFF60D8FF).withAlpha(12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.progress != progress;
}

class _BackgroundOrbs extends StatefulWidget {
  const _BackgroundOrbs();

  @override
  State<_BackgroundOrbs> createState() => _BackgroundOrbsState();
}

class _BackgroundOrbsState extends State<_BackgroundOrbs>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _OrbPainter(progress: _ctrl.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PER-KARTE ANIMATIONS-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

/// Sanftes Auf-Ab-Schweben (z.B. für Emojis)
class _FloatWidget extends StatefulWidget {
  const _FloatWidget({
    required this.child,
    this.amplitude = 8.0,
    this.period = 2500,
  });
  final Widget child;
  final double amplitude;
  final int period;
  @override
  State<_FloatWidget> createState() => _FloatWidgetState();
}

class _FloatWidgetState extends State<_FloatWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.period),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -widget.amplitude * _anim.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Pendelschaukeln (z.B. 🪝)
class _SwingWidget extends StatefulWidget {
  const _SwingWidget({required this.child});
  final Widget child;
  @override
  State<_SwingWidget> createState() => _SwingWidgetState();
}

class _SwingWidgetState extends State<_SwingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: -1.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.rotate(
        angle: _anim.value * 0.26,
        alignment: Alignment.topCenter,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Dauerhaft rotierende Animation (z.B. 🔄)
class _SpinWidget extends StatefulWidget {
  const _SpinWidget({required this.child, this.duration = 2200});
  final Widget child;
  final int duration;
  @override
  State<_SpinWidget> createState() => _SpinWidgetState();
}

class _SpinWidgetState extends State<_SpinWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.duration),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) =>
          Transform.rotate(angle: _ctrl.value * 2 * math.pi, child: child),
      child: widget.child,
    );
  }
}

/// Spring-Bounce (z.B. 📍)
class _BounceWidget extends StatefulWidget {
  const _BounceWidget({required this.child});
  final Widget child;
  @override
  State<_BounceWidget> createState() => _BounceWidgetState();
}

class _BounceWidgetState extends State<_BounceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _anim = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.bounceOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -12.0 * _anim.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Feuerfunken-Flackern (für 🔥)
class _FlickerWidget extends StatefulWidget {
  const _FlickerWidget({required this.child});
  final Widget child;
  @override
  State<_FlickerWidget> createState() => _FlickerWidgetState();
}

class _FlickerWidgetState extends State<_FlickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleX;
  late Animation<double> _scaleY;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    )..repeat(reverse: true);
    _scaleX = Tween<double>(
      begin: 0.90,
      end: 1.10,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _scaleY = Tween<double>(
      begin: 1.00,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.scale(
        scaleX: _scaleX.value,
        scaleY: _scaleY.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Expandierende Puls-Ringe (Radar-Effekt)
class _PulseRingPainter extends CustomPainter {
  const _PulseRingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    for (int i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = 50.0 + t * 130.0;
      final alpha = ((1.0 - t) * 0.38 * 255).round();
      if (alpha < 3) continue;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withAlpha(alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) => old.progress != progress;
}

class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color});
  final Color color;
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _PulseRingPainter(
            progress: _ctrl.value,
            color: widget.color,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Diagonaler Scan-Beam (Tech-Scanner-Effekt)
class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = -size.width * 0.3 + progress * size.width * 1.6;
    final gradient = LinearGradient(
      colors: [
        Colors.transparent,
        color.withAlpha(60),
        color.withAlpha(120),
        color.withAlpha(60),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
    );
    final rect = Rect.fromLTWH(x - 50, 0, 100, size.height);
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}

class _ScanLine extends StatefulWidget {
  const _ScanLine({this.color = ApexColors.primary, this.period = 3200});
  final Color color;
  final int period;
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.period),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _ScanLinePainter(progress: _ctrl.value, color: widget.color),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Umlaufende Orbit-Punkte (z.B. um Fisch-Emoji)
class _OrbitDotsPainter extends CustomPainter {
  const _OrbitDotsPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 52.0;
    for (int i = 0; i < 5; i++) {
      final angle = (progress * 2 * math.pi) + (i / 5) * 2 * math.pi;
      final pos = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final opacity =
          (0.35 + 0.65 * math.sin(angle * 0.5 + progress * math.pi).abs())
              .clamp(0.1, 1.0);
      canvas.drawCircle(
        pos,
        2.5,
        Paint()
          ..color = color.withAlpha((opacity * 210).round())
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitDotsPainter old) => old.progress != progress;
}

class _OrbitDots extends StatefulWidget {
  const _OrbitDots({required this.color});
  final Color color;
  @override
  State<_OrbitDots> createState() => _OrbitDotsState();
}

class _OrbitDotsState extends State<_OrbitDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _OrbitDotsPainter(
            progress: _ctrl.value,
            color: widget.color,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KARTEN-EINGANG (scale + fade + slide beim Erscheinen)
// ═══════════════════════════════════════════════════════════════════════════

class _CardEntrance extends StatelessWidget {
  const _CardEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child
        .animate()
        .fadeIn(duration: 350.ms, curve: Curves.easeOut)
        .blurXY(begin: 6, end: 0, duration: 400.ms, curve: Curves.easeOut)
        .slideY(
          begin: 0.06,
          end: 0,
          duration: 500.ms,
          curve: Curves.easeOutCubic,
        )
        .scale(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1, 1),
          duration: 500.ms,
          curve: Curves.elasticOut,
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COUNT-UP ZAHL (animiertes Hochzählen mit Glow)
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedBigNumber extends StatefulWidget {
  const _AnimatedBigNumber(
    this.target, {
    this.color = ApexColors.primary,
    this.suffix = '',
    this.fontSize = 80,
    this.delayMs = 120,
  });
  final int target;
  final Color color;
  final String suffix;
  final double fontSize;
  final int delayMs;

  @override
  State<_AnimatedBigNumber> createState() => _AnimatedBigNumberState();
}

class _AnimatedBigNumberState extends State<_AnimatedBigNumber> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _started = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      // Unsichtbar halten bis das cardIn-Delay abgelaufen ist
      return Opacity(
        opacity: 0,
        child: _glowText(
          '${widget.target}${widget.suffix}',
          color: widget.color,
          fontSize: widget.fontSize,
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.target.toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, val, __) => _glowText(
        '${val.round()}${widget.suffix}',
        color: widget.color,
        fontSize: widget.fontSize,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHIMMER-TITEL
// ═══════════════════════════════════════════════════════════════════════════

class _RevierTitle extends StatelessWidget {
  const _RevierTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
          'Dein Revier',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 2800.ms, color: ApexColors.primary, angle: 0.3);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PULSIERENDER NEU-WÜRFELN-BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _RerollButton extends StatelessWidget {
  const _RerollButton({required this.onReroll});
  final VoidCallback onReroll;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
          onPressed: onReroll,
          icon: const Icon(Icons.casino_outlined, size: 15),
          label: const Text('Neu würfeln', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: ApexColors.primary,
            side: BorderSide(
              color: ApexColors.primary.withAlpha(110),
              width: 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          begin: 1.0,
          end: 1.08,
          duration: 1700.ms,
          curve: Curves.easeInOut,
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREEN STATE
// ═══════════════════════════════════════════════════════════════════════════

class RevierScreen extends ConsumerStatefulWidget {
  const RevierScreen({super.key});

  @override
  ConsumerState<RevierScreen> createState() => _RevierScreenState();
}

class _RevierScreenState extends ConsumerState<RevierScreen> {
  RevierPeriod _period = RevierPeriod.month;
  late DateTime _reference;
  late int _seed;
  late PageController _pageController;
  int _currentPage = 0;

  // Autoplay
  Timer? _autoplayTimer;

  // Musik
  AudioPlayer? _audioPlayer;
  bool _musicEnabled = true;

  // Confetti
  ConfettiController? _confettiCtrl;
  bool _confettiPlayed = false;
  bool _confettiReady = false;
  bool _confettiFired = false;

  // Share
  final _shareButtonKey = GlobalKey();
  final _shareRepaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _reference = DateTime(now.year, now.month);
    _seed = math.Random().nextInt(0x7FFFFFFF);
    _pageController = PageController();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 3));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _confettiReady = true);
    });
    _initAudio();
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _confettiCtrl?.dispose();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ─── Autoplay ───────────────────────────────────────────────────────────

  void _startAutoplay(int totalCards) {
    _autoplayTimer?.cancel();
    if (totalCards <= 1) return;
    _autoplayTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % totalCards;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
  }

  // ─── Audio ───────────────────────────────────────────────────────────────

  static const _tracks = [
    'audio/revier_loop_1.mp3',
    'audio/revier_loop_2.mp3',
    'audio/revier_loop_3.mp3',
    'audio/revier_loop_4.mp3',
  ];

  Future<void> _initAudio() async {
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer!.setVolume(0.35);
      await _switchTrack();
    } catch (_) {
      // Kein Audio-Asset vorhanden — kein Crash
    }
  }

  Future<void> _switchTrack() async {
    try {
      final track = _tracks[math.Random().nextInt(_tracks.length)];
      await _audioPlayer?.stop();
      await _audioPlayer?.play(AssetSource(track));
    } catch (e) {
      debugPrint('revier music switchTrack: $e');
    }
  }

  void _toggleMusic() {
    HapticFeedback.selectionClick();
    setState(() => _musicEnabled = !_musicEnabled);
    if (_musicEnabled) {
      _audioPlayer?.resume();
    } else {
      _audioPlayer?.pause();
    }
  }

  void _reroll() {
    HapticFeedback.heavyImpact();
    _cancelAutoplay();
    setState(() {
      _seed = math.Random().nextInt(0x7FFFFFFF);
      _currentPage = 0;
    });
    _pageController.jumpToPage(0);
    if (_musicEnabled) _switchTrack();
  }

  void _setPeriod(RevierPeriod p) {
    _cancelAutoplay();
    setState(() {
      _period = p;
      _currentPage = 0;
    });
    _pageController.jumpToPage(0);
  }

  Future<void> _pickDate(BuildContext context) async {
    final catches = ref.read(catchProvider).valueOrNull ?? const <CatchEntry>[];
    if (_period == RevierPeriod.month) {
      final months =
          catches
              .map((e) => DateTime(e.caughtAt.year, e.caughtAt.month))
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      if (months.isEmpty) {
        final now = DateTime.now();
        months.add(DateTime(now.year, now.month));
      }
      if (!context.mounted) return;
      final picked = await showDialog<DateTime>(
        context: context,
        builder: (ctx) => _MonthPickerDialog(
          selected: DateTime(_reference.year, _reference.month),
          months: months,
        ),
      );
      if (picked != null) {
        _cancelAutoplay();
        setState(() {
          _reference = picked;
          _currentPage = 0;
        });
        _pageController.jumpToPage(0);
      }
    } else {
      final years = catches.map((e) => e.caughtAt.year).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      if (years.isEmpty) years.add(DateTime.now().year);
      if (!context.mounted) return;
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) =>
            _YearPickerDialog(selectedYear: _reference.year, years: years),
      );
      if (picked != null) {
        _cancelAutoplay();
        setState(() {
          _reference = DateTime(picked);
          _currentPage = 0;
        });
        _pageController.jumpToPage(0);
      }
    }
  }

  String _shareText(RevierStats stats) {
    final buf = StringBuffer();
    buf.writeln('📊 Meine Angelbilanz – ${stats.label}');
    buf.writeln('');
    for (final card in stats.cards) {
      final line = _cardShareLine(card);
      if (line != null) buf.writeln(line);
    }
    buf.writeln('');
    buf.writeln('#Angeln #Angelbilanz');
    return buf.toString();
  }

  Future<void> _shareImage(BuildContext context, RevierStats stats) async {
    // Kurz warten bis das offscreen Widget gerendert ist
    await Future.delayed(const Duration(milliseconds: 120));
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final boundary =
          _shareRepaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('no boundary');
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('no bytes');
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/angelbilanz.png');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '#Angeln #Angelbilanz',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      // Fallback auf Text
      if (!mounted) return;
      Share.share(_shareText(stats), sharePositionOrigin: origin);
    }
  }

  String? _cardShareLine(RevierCard card) {
    switch (card.type) {
      case RevierCardType.catchCount:
        return '🎣 ${card.data['count']} Fische gefangen';
      case RevierCardType.totalWeight:
        final g = card.data['totalG'] as int;
        return '⚖️ ${(g / 1000).toStringAsFixed(1)} kg Gesamtgewicht';
      case RevierCardType.topSpecies:
        final sp = card.data['species'] as FishSpecies;
        return '${sp.emoji} Lieblingsart: ${sp.displayName} (${card.data['count']}×)';
      case RevierCardType.biggestCatch:
        final g = card.data['weightG'] as int;
        final sp = (card.data['entry'] as CatchEntry).species;
        return '🏆 Schwerster Fang: ${sp.displayName} – ${(g / 1000).toStringAsFixed(2)} kg';
      case RevierCardType.longestCatch:
        final cm = card.data['lengthCm'] as double;
        final sp = (card.data['entry'] as CatchEntry).species;
        return '📏 Längster Fang: ${sp.displayName} – ${cm.toStringAsFixed(0)} cm';
      case RevierCardType.bestWeekday:
        final wd = card.data['weekday'] as int;
        const wdNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
        return '📅 Bester Wochentag: ${wdNames[wd - 1]} (${card.data['count']} Fänge)';
      case RevierCardType.bestDaytime:
        return '🌅 Beste Zeit: ${card.data['label']}';
      case RevierCardType.topLure:
        return '🪝 Lieblingsköder: ${card.data['lure']} (${card.data['count']}×)';
      case RevierCardType.topRetrieve:
        final style = card.data['style'] as RetrieveStyle;
        return '🔄 Beliebteste Technik: ${style.displayName}';
      case RevierCardType.topSpot:
        return null;
      case RevierCardType.streak:
        return '🔥 ${card.data['days']} Tage in Folge am Wasser';
      case RevierCardType.avgDrill:
        return '⏱️ Ø Drill: ${card.data['avgSec']} Sek.';
      case RevierCardType.tempRange:
        return '🌡️ Wassertemp. ${card.data['minC']}–${card.data['maxC']} °C';
      case RevierCardType.comparison:
        final cur = card.data['current'] as int;
        final prev = card.data['prev'] as int;
        final diff = cur - prev;
        final sign = diff >= 0 ? '+' : '';
        return '📈 Vergleich: $sign$diff Fänge ggü. Vorperiode';
    }
  }

  @override
  Widget build(BuildContext context) {
    final catches =
        ref.watch(catchProvider).valueOrNull ?? const <CatchEntry>[];
    final spots = ref.watch(spotProvider).valueOrNull ?? const <FishingSpot>[];
    final spotById = {for (final s in spots) s.id: s};

    final stats = RevierStats.compute(
      all: catches,
      period: _period,
      reference: _reference,
      seed: _seed,
    );

    // Autoplay starten wenn Stats verfügbar und Timer noch nicht läuft
    if (!stats.isEmpty && _autoplayTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAutoplay(stats.cards.length);
      });
    }

    // Confetti: _confettiFired=true erst wenn Widgets sicher im Tree, dann play() einen Frame danach
    if (!stats.isEmpty &&
        !_confettiPlayed &&
        _confettiReady &&
        !_confettiFired) {
      _confettiPlayed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _confettiFired = true);
        // Festes Delay statt nested postFrameCallback: garantiert,
        // dass das ConfettiWidget vollständig layoutet ist, bevor
        // play() Partikel emittiert. Beim 2./3. Öffnen war der erste
        // Frame so schnell fertig, dass play() teils vor dem Layout
        // feuerte → Partikel kamen aus (0,0) statt aus der Mitte.
        Future.delayed(const Duration(milliseconds: 220), () {
          if (mounted) _confettiCtrl?.play();
        });
      });
    }

    // PB-Foto für Share-Karte (longestCatch bevorzugt, Fallback biggestCatch)
    RevierCard? pbCard;
    for (final card in stats.cards) {
      if (card.type == RevierCardType.longestCatch) {
        pbCard = card;
        break;
      }
    }
    pbCard ??= stats.cards
        .where((c) => c.type == RevierCardType.biggestCatch)
        .firstOrNull;
    final pbEntry = pbCard?.data['entry'] as CatchEntry?;
    final pbPhotoFile = AppPaths.photoFile(pbEntry?.photoPath);

    final c = ApexColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          color: c.textPrimary,
          onPressed: () => context.pop(),
        ),
        title: const _RevierTitle(),
        centerTitle: false,
        actions: [
          // Musik-Toggle
          IconButton(
            icon: Icon(_musicEnabled ? Icons.music_note : Icons.music_off),
            color: _musicEnabled ? ApexColors.primary : c.textMuted,
            tooltip: _musicEnabled ? 'Musik aus' : 'Musik an',
            onPressed: _toggleMusic,
          ),
          if (!stats.isEmpty)
            IconButton(
              key: _shareButtonKey,
              icon: const Icon(Icons.share_outlined),
              color: c.textSecondary,
              tooltip: 'Teilen',
              onPressed: () => _shareImage(context, stats),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Ambient background orbs (always behind everything)
          const Positioned.fill(child: _BackgroundOrbs()),
          // Main content
          Column(
            children: [
              _PeriodBar(
                period: _period,
                reference: _reference,
                onPeriodChanged: _setPeriod,
                onPickDate: () => _pickDate(context),
              ),
              const SizedBox(height: 4),
              if (!stats.isEmpty)
                _AutoplayProgressBar(
                  currentPage: _currentPage,
                  cardCount: stats.cards.length,
                ),
              Expanded(
                child: stats.isEmpty
                    ? _EmptyState(
                        label: stats.label,
                        period: _period,
                        onPickDate: () => _pickDate(context),
                      )
                    : _CardStack(
                        stats: stats,
                        spotById: spotById,
                        pageController: _pageController,
                        currentPage: _currentPage,
                        onPageChanged: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _currentPage = i);
                          _startAutoplay(stats.cards.length);
                        },
                      ),
              ),
              if (!stats.isEmpty)
                _BottomBar(
                  cardCount: stats.cards.length,
                  currentPage: _currentPage,
                  onReroll: _reroll,
                ),
              const SizedBox(height: 10),
            ],
          ),
          // Confetti über allem – Nozzle in der Mitte, volle Breite
          if (_confettiCtrl != null && _confettiFired)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  // Fixe 1×1-Box als deterministische Emissions-Quelle.
                  // Ohne SizedBox kann der Stack die Box auf 0×0 oder
                  // unbestimmte Größe shrinken; das `confetti`-Package
                  // emittiert dann teils vom Rand statt aus der Mitte
                  // (User-Report: "Konfetti fliegt nur nach links").
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: ConfettiWidget(
                      confettiController: _confettiCtrl!,
                      blastDirectionality: BlastDirectionality.explosive,
                      maxBlastForce: 55,
                      minBlastForce: 25,
                      emissionFrequency: 0.06,
                      numberOfParticles: 40,
                      gravity: 0.08,
                      shouldLoop: false,
                      canvas: MediaQuery.sizeOf(context),
                      colors: const [
                        ApexColors.primary,
                        ApexColors.strike,
                        Colors.white,
                        Color(0xFFFFD700),
                        Color(0xFF7B61FF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Offscreen Share-Karte (immer gerendert, nie sichtbar)
          Transform.translate(
            offset: const Offset(-5000, 0),
            child: RepaintBoundary(
              key: _shareRepaintKey,
              child: _ShareCardWidget(stats: stats, pbPhotoFile: pbPhotoFile),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOPLAY-FORTSCHRITTSLEISTE (Stories-Style)
// ═══════════════════════════════════════════════════════════════════════════

class _AutoplayProgressBar extends StatelessWidget {
  const _AutoplayProgressBar({
    required this.currentPage,
    required this.cardCount,
  });

  final int currentPage;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: List.generate(cardCount, (i) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: i < currentPage
                    ? Container(height: 3, color: ApexColors.primary)
                    : i == currentPage
                    ? TweenAnimationBuilder<double>(
                        key: ValueKey(currentPage),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(seconds: 4),
                        builder: (_, val, __) => LinearProgressIndicator(
                          value: val,
                          backgroundColor: Colors.white.withAlpha(40),
                          color: ApexColors.primary,
                          minHeight: 3,
                        ),
                      )
                    : Container(height: 3, color: Colors.white.withAlpha(40)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PERIOD-BAR
// ═══════════════════════════════════════════════════════════════════════════

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.period,
    required this.reference,
    required this.onPeriodChanged,
    required this.onPickDate,
  });

  final RevierPeriod period;
  final DateTime reference;
  final ValueChanged<RevierPeriod> onPeriodChanged;
  final VoidCallback onPickDate;

  String get _dateLabel {
    if (period == RevierPeriod.month) {
      const months = [
        'Jan',
        'Feb',
        'Mär',
        'Apr',
        'Mai',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Okt',
        'Nov',
        'Dez',
      ];
      return '${months[reference.month - 1]} ${reference.year}';
    } else {
      return '${reference.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border.withAlpha(100), width: 1),
            ),
            padding: const EdgeInsets.all(2),
            child: Row(
              children: [
                _ToggleChip(
                  label: 'Monat',
                  selected: period == RevierPeriod.month,
                  onTap: () => onPeriodChanged(RevierPeriod.month),
                ),
                _ToggleChip(
                  label: 'Jahr',
                  selected: period == RevierPeriod.year,
                  onTap: () => onPeriodChanged(RevierPeriod.year),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onPickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dateLabel,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more, color: c.textMuted, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? ApexColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: ApexColors.primary.withAlpha(60),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : c.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KARTEN-STACK
// ═══════════════════════════════════════════════════════════════════════════

class _CardStack extends StatelessWidget {
  const _CardStack({
    required this.stats,
    required this.spotById,
    required this.pageController,
    required this.currentPage,
    required this.onPageChanged,
  });

  final RevierStats stats;
  final Map<String, FishingSpot> spotById;
  final PageController pageController;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      onPageChanged: onPageChanged,
      itemCount: stats.cards.length,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: pageController,
          builder: (context, _) {
            double page = 0;
            if (pageController.hasClients &&
                pageController.position.haveDimensions) {
              page = pageController.page ?? 0;
            } else {
              page = currentPage.toDouble();
            }
            final delta = (index - page).clamp(-1.0, 1.0);
            // 3D-Tilt: leichter Y-Rotation, Scale, Opacity beim Swipen
            final tilt = delta * 0.35; // ~20°
            final scale = 1 - delta.abs() * 0.08;
            final opacity = 1 - delta.abs() * 0.4;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012) // Perspektive
                ..rotateY(tilt)
                ..scaleByDouble(scale, scale, 1, 1),
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: _CardEntrance(
                  key: ValueKey('${stats.label}_${stats.cards[index].type}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: _buildCard(context, stats.cards[index], stats),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Jedem Kartentyp ein eigenes Fischbild zuweisen – für visuelle Vielfalt
  static const _cardTypeBg = {
    RevierCardType.catchCount: 'assets/fische/barsch.png',
    RevierCardType.totalWeight: 'assets/fische/wels.png',
    RevierCardType.bestWeekday: 'assets/fische/zander.png',
    RevierCardType.bestDaytime: 'assets/fische/forelle.png',
    RevierCardType.topLure: 'assets/fische/hecht.png',
    RevierCardType.topRetrieve: 'assets/fische/huchen.png',
    RevierCardType.topSpot: 'assets/fische/aal.png',
    RevierCardType.streak: 'assets/fische/barsch.png',
    RevierCardType.avgDrill: 'assets/fische/zander.png',
    RevierCardType.tempRange: 'assets/fische/wels.png',
    RevierCardType.comparison: 'assets/fische/forelle.png',
  };

  Widget _buildCard(BuildContext context, RevierCard card, RevierStats stats) {
    switch (card.type) {
      case RevierCardType.catchCount:
        return _CatchCountCard(
          data: card.data,
          label: stats.label,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.totalWeight:
        return _TotalWeightCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.topSpecies:
        // TopSpeciesCard setzt selbst das Bild der Lieblingsart
        return _TopSpeciesCard(data: card.data);
      case RevierCardType.biggestCatch:
        return _BiggestCatchCard(
          data: card.data,
          photoFile: AppPaths.photoFile(
            (card.data['entry'] as CatchEntry).photoPath,
          ),
        );
      case RevierCardType.longestCatch:
        return _LongestCatchCard(
          data: card.data,
          photoFile: AppPaths.photoFile(
            (card.data['entry'] as CatchEntry).photoPath,
          ),
        );
      case RevierCardType.bestWeekday:
        return _BestWeekdayCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.bestDaytime:
        return _BestDaytimeCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.topLure:
        return _TopLureCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.topRetrieve:
        return _TopRetrieveCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.topSpot:
        return _TopSpotCard(
          data: card.data,
          spotById: spotById,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.streak:
        return _StreakCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.avgDrill:
        return _AvgDrillCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.tempRange:
        return _TempRangeCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
      case RevierCardType.comparison:
        return _ComparisonCard(
          data: card.data,
          backgroundImage: _cardTypeBg[card.type],
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BOTTOM BAR
// ═══════════════════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.cardCount,
    required this.currentPage,
    required this.onReroll,
  });

  final int cardCount;
  final int currentPage;
  final VoidCallback onReroll;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: List.generate(cardCount, (i) {
              final active = i == currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 22 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? ApexColors.primary : c.border,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: ApexColors.primary.withAlpha(90),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
          _RerollButton(onReroll: onReroll),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LEERER ZUSTAND
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.label,
    required this.period,
    required this.onPickDate,
  });
  final String label;
  final RevierPeriod period;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎣', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'Keine Fänge in $label',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              period == RevierPeriod.month
                  ? 'Wähl einen anderen Monat oder leg los.'
                  : 'Wähl ein anderes Jahr oder fang dieses Jahr was.',
              style: TextStyle(color: c.textMuted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onPickDate,
              style: OutlinedButton.styleFrom(
                foregroundColor: ApexColors.primary,
                side: const BorderSide(color: ApexColors.primary),
              ),
              child: Text(
                period == RevierPeriod.month
                    ? 'Anderen Monat wählen'
                    : 'Anderes Jahr wählen',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BASE CARD (mit Sparkle-Overlay und Glow-Rahmen)
// ═══════════════════════════════════════════════════════════════════════════

class _BaseCard extends StatelessWidget {
  const _BaseCard({
    required this.child,
    this.gradient,
    this.backgroundImage,
    this.backgroundImageFile,
    this.glowColor,
  });

  final Widget child;
  final Gradient? gradient;
  final String? backgroundImage;
  final File? backgroundImageFile;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final accent = glowColor ?? ApexColors.primary;
    const radius = BorderRadius.all(Radius.circular(24));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: accent.withAlpha(55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(45),
            blurRadius: 32,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C1320),
            gradient: gradient,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backgroundImageFile != null || backgroundImage != null) ...[
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.22,
                    child: backgroundImageFile != null
                        ? Image.file(backgroundImageFile!, fit: BoxFit.cover)
                        : Image.asset(backgroundImage!, fit: BoxFit.cover),
                  ),
                ),
                // Dunkel-Scrim für Lesbarkeit
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF06090F).withAlpha(140),
                          const Color(0xFF06090F).withAlpha(210),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              // Glitter overlay
              const Positioned.fill(
                child: IgnorePointer(child: _SparkleOverlay()),
              ),
              // Card content
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER-FUNKTIONEN
// ═══════════════════════════════════════════════════════════════════════════

/// Staggered Eingangs-Animation für Card-Elemente.
extension _CardAnim on Widget {
  /// Standard-Eintritt: Fade + Slide-Up + Scale-Bounce + Schärfeziehen + sanftes Schimmern.
  Widget cardIn({int delayMs = 0}) =>
      animate(delay: Duration(milliseconds: delayMs))
          .fadeIn(duration: 460.ms, curve: Curves.easeOut)
          .slideY(
            begin: 0.28,
            end: 0,
            duration: 620.ms,
            curve: Curves.easeOutCubic,
          )
          .scaleXY(
            begin: 0.88,
            end: 1.0,
            duration: 620.ms,
            curve: Curves.easeOutBack,
          )
          .blurXY(begin: 6, end: 0, duration: 420.ms, curve: Curves.easeOut)
          // Sanfter Glanz nach dem Eintritt
          .shimmer(
            delay: 700.ms,
            duration: 1100.ms,
            color: Colors.white.withAlpha(70),
          );

  /// Für große Zahlen / Hero-Elemente: elastischer Pop mit Glow-Pulse.
  Widget popIn({int delayMs = 0}) =>
      animate(delay: Duration(milliseconds: delayMs))
          .fadeIn(duration: 380.ms, curve: Curves.easeOut)
          .scaleXY(
            begin: 0.4,
            end: 1.0,
            duration: 900.ms,
            curve: Curves.elasticOut,
          )
          .blurXY(begin: 8, end: 0, duration: 420.ms, curve: Curves.easeOut)
          .then(delay: 100.ms)
          .shimmer(duration: 1300.ms, color: Colors.white.withAlpha(110));

  /// Für Header-Labels: schwingt von oben ein mit Blur und kräftigem Slide.
  Widget swoopIn({int delayMs = 0}) =>
      animate(delay: Duration(milliseconds: delayMs))
          .fadeIn(duration: 500.ms, curve: Curves.easeOut)
          .slideY(
            begin: -0.6,
            end: 0,
            duration: 700.ms,
            curve: Curves.easeOutCubic,
          )
          .blurXY(begin: 8, end: 0, duration: 420.ms, curve: Curves.easeOut);
}

Widget _glowText(
  String text, {
  Color color = ApexColors.primary,
  double fontSize = 80,
  FontWeight fontWeight = FontWeight.w900,
  double letterSpacing = -2,
}) {
  return Text(
    text,
    style: TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: 1.0,
      letterSpacing: letterSpacing,
      shadows: [
        Shadow(color: color.withAlpha(160), blurRadius: 22),
        Shadow(color: color.withAlpha(80), blurRadius: 48),
      ],
    ),
  );
}

Widget _cardLabel(String text, ApexColors c) => Text(
  text.toUpperCase(),
  style: TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: c.textMuted,
    letterSpacing: 1.5,
  ),
);

String _formatShortDate(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];
  return '${dt.day}. ${months[dt.month - 1]} ${dt.year}';
}

String _retrieveDesc(RetrieveStyle style) {
  switch (style) {
    case RetrieveStyle.cranking:
      return 'Gleichmäßig kurbeln — Wobbler zum Laufen bringen';
    case RetrieveStyle.stopGo:
      return 'Einhalten und wieder einsetzen — verführerisch!';
    case RetrieveStyle.speedVariation:
      return 'Tempowechsel hält den Fisch in Spannung';
    case RetrieveStyle.faulenzen:
      return 'Einfach liegen lassen — manchmal das Beste';
    case RetrieveStyle.jig:
      return 'Rucken und zucken — der Klassiker am Grund';
    case RetrieveStyle.dragging:
      return 'Soft-Plastik schleifend über den Grund ziehen';
    case RetrieveStyle.tumbling:
      return 'Taumelnde Bewegung verführt zögerliche Räuber';
    case RetrieveStyle.twitch:
      return 'Kurze Rutenimpulse — lebhaft und aggressiv';
    case RetrieveStyle.jerking:
      return 'Breite Rutenausschläge für maximale Flucht-Aktion';
    case RetrieveStyle.walkTheDog:
      return 'Topwater-Klassiker: Zick-Zack an der Oberfläche';
    case RetrieveStyle.ripping:
      return 'Jig schnell hochreißen, fallen lassen — Herzrasen';
    case RetrieveStyle.shaking:
      return 'In-Place zittern — perfekt beim Drop-Shot';
    case RetrieveStyle.deadSticking:
      return 'Geduld: Köder sinken und liegen lassen';
    case RetrieveStyle.liftDrop:
      return 'Heben und fallen — natürliche Beutebewegung';
    case RetrieveStyle.vertical:
      return 'Senkrecht unter dem Boot — präzise Zielfischerei';
    case RetrieveStyle.pelagic:
      return 'In der Freiwasserzone schwebend präsentieren';
    case RetrieveStyle.dropShot:
      return 'Finesse-Rig am Grund — unschlagbar bei Druck';
    case RetrieveStyle.texasRig:
      return 'Unkrautfreie Präsentation in dichter Vegetation';
    case RetrieveStyle.carolinaRig:
      return 'Gewicht gleitet, Köder schwebt dahinter frei';
    case RetrieveStyle.nedRig:
      return 'Mini-Jig aufrecht stehend — Kleinfisch-Imitation';
    case RetrieveStyle.cheburashkaRig:
      return 'Freies Gewicht für natürliches Fallen des Köders';
    case RetrieveStyle.freeRig:
      return 'Gewicht gleitet frei — natürliche Aktion garantiert';
    case RetrieveStyle.wackyRig:
      return 'Mittig gehakter Wurm — verlockende U-Form';
    default:
      return 'Bewährte Technik aus deiner Praxis';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EINZELNE KARTEN
// ═══════════════════════════════════════════════════════════════════════════

class _CatchCountCard extends StatelessWidget {
  const _CatchCountCard({
    required this.data,
    required this.label,
    this.backgroundImage,
  });
  final Map<String, dynamic> data;
  final String label;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final count = data['count'] as int;
    final prev = data['prev'] as int;
    final diff = count - prev;
    return _BaseCard(
      glowColor: ApexColors.primary,
      backgroundImage: backgroundImage,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0C2030), Color(0xFF061018)],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: _ScanLine(color: ApexColors.primary, period: 2800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardLabel('Dein Revier · $label', c).swoopIn(),
                const Spacer(),
                _AnimatedBigNumber(count, delayMs: 120).popIn(delayMs: 120),
                const SizedBox(height: 4),
                Text(
                  count == 1 ? 'Fisch gefangen' : 'Fische gefangen',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ).cardIn(delayMs: 200),
                const SizedBox(height: 6),
                Text(
                  count >= 30
                      ? 'Absolute Bestform! 🎯'
                      : count >= 15
                      ? 'Richtig aktiver Monat!'
                      : count >= 8
                      ? 'Starke Leistung 🤙'
                      : count >= 3
                      ? 'Schon was gerissen!'
                      : 'Der Anfang ist gemacht.',
                  style: TextStyle(
                    fontSize: 14,
                    color: c.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ).cardIn(delayMs: 280),
                const SizedBox(height: 16),
                if (prev > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: diff >= 0
                          ? ApexColors.primary.withAlpha(30)
                          : ApexColors.strike.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      diff >= 0
                          ? '+$diff ggü. Vorperiode'
                          : '$diff ggü. Vorperiode',
                      style: TextStyle(
                        color: diff >= 0
                            ? ApexColors.primary
                            : ApexColors.strike,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ).cardIn(delayMs: 380),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalWeightCard extends StatelessWidget {
  const _TotalWeightCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final totalG = data['totalG'] as int;
    final count = data['count'] as int;
    final targetKg = totalG / 1000;
    return _BaseCard(
      glowColor: ApexColors.primary,
      backgroundImage: backgroundImage,
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF0D2218), Color(0xFF061018)],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _ScanLine(color: const Color(0xFF00D4AA), period: 3800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardLabel('Gesamtgewicht', c).swoopIn(),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: targetKg),
                  duration: const Duration(milliseconds: 1100),
                  curve: Curves.easeOutCubic,
                  builder: (_, val, __) => _glowText(
                    val >= 10
                        ? '${val.toStringAsFixed(1)} kg'
                        : '${val.toStringAsFixed(2)} kg',
                  ),
                ).cardIn(delayMs: 120),
                const SizedBox(height: 8),
                const SizedBox(height: 4),
                Text(
                  'Ø ${(totalG / count / 1000).toStringAsFixed(2)} kg pro Fisch',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ApexColors.primary,
                  ),
                ).cardIn(delayMs: 220),
                Text(
                  'aus $count gewogenen Fängen',
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ).cardIn(delayMs: 280),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: _FloatWidget(
                    amplitude: 8,
                    period: 2600,
                    child: const Text('⚖️', style: TextStyle(fontSize: 40)),
                  ).cardIn(delayMs: 380),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopSpeciesCard extends StatelessWidget {
  const _TopSpeciesCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final species = data['species'] as FishSpecies;
    final count = data['count'] as int;
    final total = data['total'] as int;
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return _BaseCard(
      glowColor: ApexColors.primary,
      backgroundImage: species.imageAsset,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, const Color(0xFF06090F).withAlpha(230)],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: _OrbitDots(color: ApexColors.primary)),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardLabel('Lieblingsart', c).swoopIn(),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dein Markenzeichen',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ).cardIn(delayMs: 80),
                          const SizedBox(height: 6),
                          _glowText(
                            species.displayName,
                            fontSize: 34,
                            letterSpacing: -1,
                            color: c.textPrimary,
                          ).cardIn(delayMs: 140),
                        ],
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      builder: (_, val, child) =>
                          Transform.scale(scale: 0.6 + val * 0.4, child: child),
                      child: _FloatWidget(
                        child: Text(
                          species.emoji,
                          style: const TextStyle(fontSize: 64),
                        ),
                      ),
                    ).cardIn(delayMs: 80),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: ApexColors.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count Fänge',
                        style: const TextStyle(
                          color: ApexColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ).cardIn(delayMs: 240),
                    const SizedBox(width: 8),
                    Text(
                      '$pct% aller Fänge',
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ).cardIn(delayMs: 280),
                  ],
                ),
                const SizedBox(height: 10),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct / 100.0),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  builder: (_, frac, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac,
                      backgroundColor: c.border,
                      color: ApexColors.primary,
                      minHeight: 6,
                    ),
                  ),
                ).cardIn(delayMs: 320),
                const SizedBox(height: 4),
                Text(
                  'Dominanz im Revier',
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ).cardIn(delayMs: 380),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BiggestCatchCard extends StatelessWidget {
  const _BiggestCatchCard({required this.data, this.photoFile});
  final Map<String, dynamic> data;
  final File? photoFile;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final entry = data['entry'] as CatchEntry;
    final weightG = data['weightG'] as int;
    final targetKg = weightG / 1000;
    return _BaseCard(
      glowColor: ApexColors.strike,
      backgroundImageFile: photoFile,
      backgroundImage: photoFile == null ? entry.species.imageAsset : null,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, const Color(0xFF06090F).withAlpha(235)],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: _PulseRing(color: ApexColors.strike)),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _cardLabel('Schwerster Fang', c).swoopIn()),
                    _FloatWidget(
                      amplitude: 7,
                      child: const Text('🏆', style: TextStyle(fontSize: 30)),
                    ).cardIn(delayMs: 80),
                  ],
                ),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: targetKg),
                  duration: const Duration(milliseconds: 1100),
                  curve: Curves.easeOutCubic,
                  builder: (_, val, __) => _glowText(
                    val >= 10 ? val.toStringAsFixed(1) : val.toStringAsFixed(2),
                    color: ApexColors.strike,
                  ),
                ).cardIn(delayMs: 150),
                _glowText(
                  'kg',
                  fontSize: 26,
                  color: ApexColors.strike.withAlpha(200),
                  letterSpacing: 0,
                ).cardIn(delayMs: 150),
                const SizedBox(height: 6),
                Text(
                  entry.species.displayName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ).cardIn(delayMs: 240),
                const SizedBox(height: 4),
                Text(
                  _formatShortDate(entry.caughtAt),
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ).cardIn(delayMs: 300),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LongestCatchCard extends StatelessWidget {
  const _LongestCatchCard({required this.data, this.photoFile});
  final Map<String, dynamic> data;
  final File? photoFile;

  @override
  Widget build(BuildContext context) {
    const iceBlue = Color(0xFF60D8FF);
    final c = ApexColors.of(context);
    final entry = data['entry'] as CatchEntry;
    final lengthCm = data['lengthCm'] as double;
    return _BaseCard(
      glowColor: iceBlue,
      backgroundImageFile: photoFile,
      backgroundImage: photoFile == null ? entry.species.imageAsset : null,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, const Color(0xFF06090F).withAlpha(235)],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _ScanLine(color: iceBlue, period: 4000),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _cardLabel('Längster Fang', c).swoopIn()),
                    _FloatWidget(
                      amplitude: 6,
                      period: 2200,
                      child: const Text('📏', style: TextStyle(fontSize: 30)),
                    ).cardIn(delayMs: 80),
                  ],
                ),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: lengthCm),
                  duration: const Duration(milliseconds: 1100),
                  curve: Curves.easeOutCubic,
                  builder: (_, val, __) =>
                      _glowText(val.toStringAsFixed(0), color: iceBlue),
                ).cardIn(delayMs: 150),
                _glowText(
                  'cm',
                  fontSize: 26,
                  color: iceBlue.withAlpha(200),
                  letterSpacing: 0,
                ).cardIn(delayMs: 150),
                const SizedBox(height: 6),
                Text(
                  entry.species.displayName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ).cardIn(delayMs: 240),
                const SizedBox(height: 4),
                Text(
                  entry.weightG != null
                      ? '${(entry.weightG! / 1000).toStringAsFixed(2)} kg · ${_formatShortDate(entry.caughtAt)}'
                      : _formatShortDate(entry.caughtAt),
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ).cardIn(delayMs: 300),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BestWeekdayCard extends StatelessWidget {
  const _BestWeekdayCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  static const _names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const _fullNames = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final weekday = data['weekday'] as int;
    final count = data['count'] as int;
    final counts = data['counts'] as List<int>;
    final maxVal = counts.reduce(math.max);

    return _BaseCard(
      glowColor: ApexColors.primary,
      backgroundImage: backgroundImage,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardLabel('Bester Wochentag', c).swoopIn(),
            const Spacer(),
            _glowText(
              _fullNames[weekday - 1],
              fontSize: 34,
              letterSpacing: -1,
            ).cardIn(delayMs: 120),
            Text(
              '$count Fänge',
              style: const TextStyle(
                fontSize: 16,
                color: ApexColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ).cardIn(delayMs: 180),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final val = counts[i];
                final isActive = i == weekday - 1;
                final heightFraction = maxVal > 0 ? val / maxVal : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: heightFraction),
                          duration: Duration(milliseconds: 500 + i * 60),
                          curve: Curves.easeOutCubic,
                          builder: (_, frac, __) => Container(
                            height: 60 * frac,
                            decoration: BoxDecoration(
                              color: isActive ? ApexColors.primary : c.border,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: ApexColors.primary.withAlpha(
                                          100,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _names[i],
                          style: TextStyle(
                            fontSize: 10,
                            color: isActive ? ApexColors.primary : c.textMuted,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ).cardIn(delayMs: 260),
            const SizedBox(height: 14),
            Text(
              'Plan deinen nächsten Trip für ${_fullNames[weekday - 1]}! 🎣',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ).cardIn(delayMs: 380),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _BestDaytimeCard extends StatelessWidget {
  const _BestDaytimeCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  String _emoji(String label) {
    if (label.startsWith('Morgens')) return '🌅';
    if (label.startsWith('Vormittags')) return '🌤️';
    if (label.startsWith('Mittags')) return '☀️';
    if (label.startsWith('Abends')) return '🌇';
    return '🌙';
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final label = data['label'] as String;
    final count = data['count'] as int;
    final slots = data['slots'] as Map<String, int>;
    final maxVal = slots.values.reduce(math.max);

    return _BaseCard(
      glowColor: const Color(0xFF8060FF),
      backgroundImage: backgroundImage,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A1230), Color(0xFF061018)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardLabel('Beste Tageszeit', c).swoopIn(),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              builder: (_, val, child) =>
                  Transform.scale(scale: 0.6 + val * 0.4, child: child),
              child: _FloatWidget(
                amplitude: 10,
                period: 3000,
                child: Text(
                  _emoji(label),
                  style: const TextStyle(fontSize: 52),
                ),
              ),
            ).cardIn(delayMs: 80),
            const SizedBox(height: 8),
            _glowText(
              label.split(' (').first,
              fontSize: 28,
              letterSpacing: -0.5,
              color: const Color(0xFFDFECF8),
            ).cardIn(delayMs: 140),
            Text(
              '$count Fänge',
              style: const TextStyle(
                fontSize: 15,
                color: ApexColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ).cardIn(delayMs: 200),
            const SizedBox(height: 4),
            Text(
              label.startsWith('Morgens')
                  ? 'Stell den Wecker früh! ⏰'
                  : label.startsWith('Nachts')
                  ? 'Du bist eine Nachteule! 🦉'
                  : label.startsWith('Abends')
                  ? 'Das Abendrot lockt die Fische! 🌇'
                  : 'Bestens ausgeschlafen ☀️',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ).cardIn(delayMs: 260),
            const SizedBox(height: 12),
            ...slots.entries.map((e) {
              final fraction = maxVal > 0 ? e.value / maxVal : 0.0;
              final isActive = e.key == label;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 82,
                      child: Text(
                        e.key.split(' (').first,
                        style: TextStyle(
                          fontSize: 10,
                          color: isActive ? c.textPrimary : c.textMuted,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: fraction),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (_, frac, __) => ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: frac,
                            backgroundColor: c.border,
                            color: isActive ? ApexColors.primary : c.textMuted,
                            minHeight: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${e.value}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? ApexColors.primary : c.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _TopLureCard extends StatelessWidget {
  const _TopLureCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final lure = data['lure'] as String;
    final count = data['count'] as int;
    final total = data['total'] as int;
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return _BaseCard(
      glowColor: ApexColors.strike,
      backgroundImage: backgroundImage,
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF201008), Color(0xFF061018)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _cardLabel('Lieblingsköder', c).swoopIn()),
                _SwingWidget(
                  child: const Text('🪝', style: TextStyle(fontSize: 36)),
                ).cardIn(delayMs: 80),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Köder des Vertrauens',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ).cardIn(delayMs: 120),
            const SizedBox(height: 6),
            _glowText(
              lure,
              fontSize: lure.length > 15 ? 24 : 32,
              color: c.textPrimary,
              letterSpacing: -0.5,
            ).cardIn(delayMs: 180),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _AnimatedBigNumber(
                  count,
                  color: ApexColors.strike,
                  suffix: '×',
                  fontSize: 40,
                  delayMs: 260,
                ).cardIn(delayMs: 260),
                const SizedBox(width: 10),
                Text(
                  '= $pct% aller Fänge',
                  style: TextStyle(
                    color: ApexColors.strike.withAlpha(180),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ).cardIn(delayMs: 320),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Immer dabei im Tackle-Setup! 🎣',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ).cardIn(delayMs: 380),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _TopRetrieveCard extends StatelessWidget {
  const _TopRetrieveCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final style = data['style'] as RetrieveStyle;
    final count = data['count'] as int;
    return _BaseCard(
      glowColor: ApexColors.primary,
      backgroundImage: backgroundImage,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardLabel('Beliebteste Technik', c).swoopIn(),
            const Spacer(),
            _glowText(
              style.displayName,
              fontSize: style.displayName.length > 15 ? 22 : 30,
              letterSpacing: -0.5,
            ).cardIn(delayMs: 120),
            const SizedBox(height: 6),
            Text(
              _retrieveDesc(style),
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ).cardIn(delayMs: 200),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _AnimatedBigNumber(
                  count,
                  fontSize: 40,
                  delayMs: 280,
                ).popIn(delayMs: 280),
                const SizedBox(width: 10),
                Text(
                  'Mal\nangewendet',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ).cardIn(delayMs: 320),
                const Spacer(),
                _SpinWidget(
                  duration: 1800,
                  child: const Text('🔄', style: TextStyle(fontSize: 40)),
                ).cardIn(delayMs: 100),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _TopSpotCard extends StatelessWidget {
  const _TopSpotCard({
    required this.data,
    required this.spotById,
    this.backgroundImage,
  });
  final Map<String, dynamic> data;
  final Map<String, FishingSpot> spotById;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final spotId = data['spotId'] as String;
    final count = data['count'] as int;
    final spot = spotById[spotId];
    final spotName = spot?.name ?? 'Unbekannter Spot';
    final waterName = spot?.waterBodyName;
    return _BaseCard(
      glowColor: const Color(0xFF40A8FF),
      backgroundImage: backgroundImage,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF051525), Color(0xFF061018)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _cardLabel('Top-Angelplatz', c).swoopIn()),
                _BounceWidget(
                  child: const Text('📍', style: TextStyle(fontSize: 36)),
                ).cardIn(delayMs: 80),
              ],
            ),
            const SizedBox(height: 10),
            _glowText(
              spotName,
              fontSize: spotName.length > 18 ? 22 : 30,
              color: c.textPrimary,
              letterSpacing: -0.5,
            ).cardIn(delayMs: 150),
            if (waterName != null) ...[
              const SizedBox(height: 2),
              Text(
                waterName,
                style: TextStyle(color: c.textMuted, fontSize: 14),
              ).cardIn(delayMs: 200),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF40A8FF).withAlpha(25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF40A8FF).withAlpha(60),
                ),
              ),
              child: const Text(
                'Dein Stammrevier',
                style: TextStyle(
                  color: Color(0xFF40A8FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ).cardIn(delayMs: 250),
            const Spacer(),
            _AnimatedBigNumber(
              count,
              color: const Color(0xFF40A8FF),
              suffix: ' Fänge',
              fontSize: 36,
              delayMs: 300,
            ).cardIn(delayMs: 300),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final days = data['days'] as int;
    final totalDays = data['totalDays'] as int;
    return _BaseCard(
      glowColor: ApexColors.strike,
      backgroundImage: backgroundImage,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ApexColors.strike.withAlpha(35), const Color(0xFF061018)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _cardLabel('Angeltag-Streak', c).swoopIn()),
                _FlickerWidget(
                  child: const Text('🔥', style: TextStyle(fontSize: 36)),
                ).cardIn(delayMs: 80),
              ],
            ),
            const Spacer(),
            _AnimatedBigNumber(
              days,
              color: ApexColors.strike,
              delayMs: 120,
            ).popIn(delayMs: 120),
            Text(
              days == 1 ? 'Tag in Folge' : 'Tage in Folge',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ).cardIn(delayMs: 200),
            const SizedBox(height: 6),
            Text(
              'An $totalDays verschiedenen Tagen am Wasser',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ).cardIn(delayMs: 260),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ApexColors.strike.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ApexColors.strike.withAlpha(70)),
              ),
              child: Text(
                days >= 14
                    ? '🏅 Legende'
                    : days >= 7
                    ? '⚡ Hardcore-Angler'
                    : days >= 4
                    ? '💪 Hobby-Profi'
                    : '🌱 Auf dem Weg!',
                style: const TextStyle(
                  color: ApexColors.strike,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ).cardIn(delayMs: 340),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _AvgDrillCard extends StatelessWidget {
  const _AvgDrillCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final avgSec = data['avgSec'] as int;
    final count = data['count'] as int;
    return _BaseCard(
      glowColor: ApexColors.primary,
      backgroundImage: backgroundImage,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _cardLabel('Durchschnittlicher Drill', c).swoopIn(),
                ),
                _SpinWidget(
                  duration: 4000,
                  child: const Text('⏱️', style: TextStyle(fontSize: 36)),
                ).cardIn(delayMs: 80),
              ],
            ),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: avgSec.toDouble()),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (_, val, __) {
                final s = val.round();
                final min = s ~/ 60;
                final sec = s % 60;
                final timeLabel = min > 0
                    ? '${min}m ${sec.toString().padLeft(2, '0')}s'
                    : '${s}s';
                return _glowText(timeLabel, fontSize: 52, letterSpacing: -1);
              },
            ).cardIn(delayMs: 150),
            const SizedBox(height: 4),
            Text(
              'aus $count Drills',
              style: TextStyle(color: c.textMuted, fontSize: 14),
            ).cardIn(delayMs: 240),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ApexColors.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ApexColors.primary.withAlpha(60)),
              ),
              child: Text(
                avgSec <= 20
                    ? '⚡ Blitzschnell'
                    : avgSec <= 45
                    ? '🎯 Kontrolliert'
                    : avgSec <= 90
                    ? '💪 Ausdauer-Profi'
                    : '🧘 Geduld ist eine Tugend',
                style: const TextStyle(
                  color: ApexColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ).cardIn(delayMs: 320),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _TempRangeCard extends StatelessWidget {
  const _TempRangeCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final minC = data['minC'] as double;
    final maxC = data['maxC'] as double;
    return _BaseCard(
      glowColor: const Color(0xFF60D8FF),
      backgroundImage: backgroundImage,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF051530), Color(0xFF200808)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardLabel('Wassertemperatur-Spanne', c).swoopIn(),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _glowText(
                      '${minC.toStringAsFixed(1)} °C',
                      fontSize: 34,
                      color: const Color(0xFF60D8FF),
                      letterSpacing: -0.5,
                    ),
                    Text(
                      'kalt',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    '→',
                    style: TextStyle(
                      fontSize: 24,
                      color: c.textMuted,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _glowText(
                      '${maxC.toStringAsFixed(1)} °C',
                      fontSize: 34,
                      color: const Color(0xFFFF8060),
                      letterSpacing: -0.5,
                    ),
                    Text(
                      'warm',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ).cardIn(delayMs: 120),
            const SizedBox(height: 10),
            Text(
              '🌡️ Differenz: ${(maxC - minC).toStringAsFixed(1)} °C',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ).cardIn(delayMs: 220),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (_, val, __) => Opacity(
                opacity: val,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: 10,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF60D8FF),
                              Color(0xFF40CC80),
                              Color(0xFFFF8060),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Optimal für Raubfisch: 15–20 °C',
                      style: TextStyle(color: c.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ).cardIn(delayMs: 320),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.data, this.backgroundImage});
  final Map<String, dynamic> data;
  final String? backgroundImage;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final current = data['current'] as int;
    final prev = data['prev'] as int;
    final periodLabel = data['periodLabel'] as String;
    final diff = current - prev;
    final isUp = diff > 0;
    final isSame = diff == 0;
    final pct = prev > 0 ? ((diff.abs() / prev) * 100).round() : null;
    final pctText = pct != null && pct > 0
        ? isUp
              ? ' (+$pct%)'
              : ' (-$pct%)'
        : '';
    final diffLabel = isSame
        ? 'Genauso viele wie zuvor'
        : isUp
        ? '+$diff mehr als $periodLabel$pctText'
        : '${diff.abs()} weniger als $periodLabel$pctText';
    final accentColor = isSame
        ? c.textSecondary
        : isUp
        ? ApexColors.primary
        : ApexColors.strike;
    return _BaseCard(
      glowColor: accentColor,
      backgroundImage: backgroundImage,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isUp
            ? [ApexColors.primary.withAlpha(28), const Color(0xFF061018)]
            : isSame
            ? [const Color(0xFF0C1320), const Color(0xFF061018)]
            : [ApexColors.strike.withAlpha(28), const Color(0xFF061018)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardLabel('Vergleich mit Vorperiode', c).swoopIn(),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              builder: (_, val, child) =>
                  Transform.scale(scale: 0.6 + val * 0.4, child: child),
              child: _FloatWidget(
                amplitude: 9,
                period: 2800,
                child: Text(
                  isSame
                      ? '🤝'
                      : isUp
                      ? '📈'
                      : '📉',
                  style: const TextStyle(fontSize: 52),
                ),
              ),
            ).cardIn(delayMs: 80),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _AnimatedBigNumber(
                  current,
                  color: c.textPrimary,
                  fontSize: 64,
                  delayMs: 160,
                ).cardIn(delayMs: 160),
                if (prev > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    'vs $prev',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: c.textMuted,
                    ),
                  ).cardIn(delayMs: 200),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              diffLabel,
              style: TextStyle(
                color: accentColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ).cardIn(delayMs: 280),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// JAHRES-PICKER-DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _MonthPickerDialog extends StatelessWidget {
  const _MonthPickerDialog({required this.selected, required this.months});

  final DateTime selected;
  final List<DateTime> months;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    const monthNames = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Monat wählen',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: months.length,
                itemBuilder: (ctx, i) {
                  final m = months[i];
                  final isSelected =
                      m.year == selected.year && m.month == selected.month;
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${monthNames[m.month - 1]} ${m.year}',
                      style: TextStyle(
                        color: isSelected ? ApexColors.primary : c.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check,
                            color: ApexColors.primary,
                            size: 18,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(m),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearPickerDialog extends StatelessWidget {
  const _YearPickerDialog({required this.selectedYear, required this.years});

  final int selectedYear;
  final List<int> years;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Jahr wählen',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: years.length,
                itemBuilder: (ctx, i) {
                  final year = years[i];
                  final isSelected = year == selectedYear;
                  return ListTile(
                    dense: true,
                    title: Text(
                      '$year',
                      style: TextStyle(
                        color: isSelected ? ApexColors.primary : c.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check,
                            color: ApexColors.primary,
                            size: 18,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(year),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARE-KARTE (9:16, offscreen gerendert für Share-Bild)
// ═══════════════════════════════════════════════════════════════════════════

class _ShareCardWidget extends StatelessWidget {
  const _ShareCardWidget({required this.stats, this.pbPhotoFile});

  final RevierStats stats;
  final File? pbPhotoFile;

  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    RevierCard? countCard,
        weightCard,
        speciesCard,
        longestCard,
        biggestCard,
        weekdayCard,
        daytimeCard,
        lureCard,
        retrieveCard,
        streakCard,
        drillCard;
    for (final c in stats.cards) {
      switch (c.type) {
        case RevierCardType.catchCount:
          countCard = c;
        case RevierCardType.totalWeight:
          weightCard = c;
        case RevierCardType.topSpecies:
          speciesCard = c;
        case RevierCardType.longestCatch:
          longestCard = c;
        case RevierCardType.biggestCatch:
          biggestCard = c;
        case RevierCardType.bestWeekday:
          weekdayCard = c;
        case RevierCardType.bestDaytime:
          daytimeCard = c;
        case RevierCardType.topLure:
          lureCard = c;
        case RevierCardType.topRetrieve:
          retrieveCard = c;
        case RevierCardType.streak:
          streakCard = c;
        case RevierCardType.avgDrill:
          drillCard = c;
        default:
          break;
      }
    }

    // PB: bevorzugt longestCatch (cm), Fallback biggestCatch (kg)
    final pbLengthCm = longestCard?.data['lengthCm'] as double?;
    final pbLengthEntry = longestCard?.data['entry'] as CatchEntry?;
    final pbWeightG = biggestCard?.data['weightG'] as int?;
    final pbWeightEntry = biggestCard?.data['entry'] as CatchEntry?;
    final hasCmPb = pbLengthCm != null && pbLengthEntry != null;

    final totalCount = countCard?.data['count'] as int? ?? 0;
    final topSpecies = speciesCard?.data['species'] as FishSpecies?;

    // Hintergrundbild (longestCatch-Foto bevorzugt via pbPhotoFile)
    ImageProvider? bgImage;
    final photo = pbPhotoFile;
    if (photo != null && photo.existsSync()) {
      bgImage = FileImage(photo);
    } else {
      final fallbackEntry = hasCmPb ? pbLengthEntry : pbWeightEntry;
      final asset = fallbackEntry?.species.imageAsset;
      if (asset != null) bgImage = AssetImage(asset);
    }

    // Stats-Tiles aus allen verfügbaren Wrapped-Karten
    final statItems = <({String value, String label})>[];
    statItems.add((value: '$totalCount', label: 'Fänge'));
    if (weightCard != null) {
      final g = weightCard.data['totalG'] as int;
      final s = g >= 10000
          ? '${(g / 1000).toStringAsFixed(1)} kg'
          : '${(g / 1000).toStringAsFixed(2)} kg';
      statItems.add((value: s, label: 'Gesamt'));
    }
    if (topSpecies != null) {
      statItems.add((value: topSpecies.emoji, label: topSpecies.displayName));
    }
    // Wenn cm als Hero → auch kg als Stat zeigen (und umgekehrt)
    if (hasCmPb && pbWeightG != null) {
      final s = pbWeightG >= 10000
          ? '${(pbWeightG / 1000).toStringAsFixed(1)} kg'
          : '${(pbWeightG / 1000).toStringAsFixed(2)} kg';
      statItems.add((value: s, label: 'Schwerster'));
    } else if (!hasCmPb && pbLengthCm != null) {
      final cmStr = pbLengthCm % 1 == 0
          ? '${pbLengthCm.toInt()} cm'
          : '${pbLengthCm.toStringAsFixed(1).replaceAll('.', ',')} cm';
      statItems.add((value: cmStr, label: 'Längster'));
    }
    if (streakCard != null) {
      final d = streakCard.data['days'] as int;
      statItems.add((value: '$d 🔥', label: 'Streak'));
    }
    if (weekdayCard != null) {
      final wd = weekdayCard.data['weekday'] as int;
      statItems.add((value: _weekdays[wd - 1], label: 'Bester Tag'));
    }
    if (daytimeCard != null) {
      final raw = daytimeCard.data['label'] as String;
      statItems.add((value: raw.split(' ').first, label: 'Beste Zeit'));
    }
    if (lureCard != null) {
      final lure = lureCard.data['lure'] as String;
      final short = lure.length > 11 ? '${lure.substring(0, 10)}…' : lure;
      statItems.add((value: short, label: 'Top Köder'));
    }
    if (retrieveCard != null) {
      final style = retrieveCard.data['style'] as RetrieveStyle;
      final name = style.displayName;
      final short = name.length > 11 ? '${name.substring(0, 10)}…' : name;
      statItems.add((value: short, label: 'Technik'));
    }
    if (drillCard != null) {
      final sec = drillCard.data['avgSec'] as int;
      statItems.add((value: '${sec}s', label: 'Ø Drill'));
    }

    return SizedBox(
      width: 360,
      height: 640,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF06090F)),
            if (bgImage != null)
              Image(
                image: bgImage,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.28, 0.55, 1.0],
                  colors: [
                    Color(0xCC06090F),
                    Color(0x2206090F),
                    Color(0xBB06090F),
                    Color(0xFA06090F),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: ApexColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'hooked',
                            style: TextStyle(
                              color: ApexColors.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3349),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          stats.label,
                          style: const TextStyle(
                            color: Color(0xFF90B8D8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // PB-Hero: cm bevorzugt
                  if (hasCmPb) ...[
                    Text(
                      'PB',
                      style: TextStyle(
                        color: ApexColors.strike.withAlpha(220),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pbLengthCm % 1 == 0
                          ? '${pbLengthCm.toInt()} cm'
                          : '${pbLengthCm.toStringAsFixed(1).replaceAll('.', ',')} cm',
                      style: const TextStyle(
                        color: ApexColors.primary,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        height: 0.9,
                        shadows: [
                          Shadow(color: ApexColors.primary, blurRadius: 32),
                          Shadow(color: ApexColors.primary, blurRadius: 80),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          pbLengthEntry.species.emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pbLengthEntry.species.displayName,
                            style: const TextStyle(
                              color: Color(0xFFDFECF8),
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatShortDate(pbLengthEntry.caughtAt),
                      style: const TextStyle(
                        color: Color(0xFF5280A0),
                        fontSize: 12,
                      ),
                    ),
                  ] else if (pbWeightG != null && pbWeightEntry != null) ...[
                    Text(
                      'PB',
                      style: TextStyle(
                        color: ApexColors.strike.withAlpha(220),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pbWeightG >= 10000
                          ? '${(pbWeightG / 1000).toStringAsFixed(1)} kg'
                          : '${(pbWeightG / 1000).toStringAsFixed(2)} kg',
                      style: const TextStyle(
                        color: ApexColors.primary,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        height: 0.9,
                        shadows: [
                          Shadow(color: ApexColors.primary, blurRadius: 32),
                          Shadow(color: ApexColors.primary, blurRadius: 80),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          pbWeightEntry.species.emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pbWeightEntry.species.displayName,
                            style: const TextStyle(
                              color: Color(0xFFDFECF8),
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatShortDate(pbWeightEntry.caughtAt),
                      style: const TextStyle(
                        color: Color(0xFF5280A0),
                        fontSize: 12,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'ANGELBILANZ',
                      style: TextStyle(
                        color: ApexColors.primary.withAlpha(200),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$totalCount',
                      style: const TextStyle(
                        color: ApexColors.primary,
                        fontSize: 80,
                        fontWeight: FontWeight.w900,
                        height: 0.9,
                        shadows: [
                          Shadow(color: ApexColors.primary, blurRadius: 32),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Fische gefangen',
                      style: TextStyle(
                        color: Color(0xFFDFECF8),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Stats-Grid
                  if (statItems.isNotEmpty) _buildStatsGrid(statItems),
                  const SizedBox(height: 12),
                  // Footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '#Angeln  #Angelbilanz',
                        style: TextStyle(
                          color: Color(0xFF3D6080),
                          fontSize: 11,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: ApexColors.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: ApexColors.primary.withAlpha(60),
                          ),
                        ),
                        child: const Text(
                          'via hooked',
                          style: TextStyle(
                            color: ApexColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(List<({String value, String label})> items) {
    const cols = 3;
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += cols) {
      final row = items.sublist(i, (i + cols).clamp(0, items.length));
      rows.add(
        Row(
          children: [
            for (int j = 0; j < row.length; j++) ...[
              if (j > 0)
                Container(width: 1, height: 28, color: const Color(0xFF1E3349)),
              Expanded(child: _statCell(row[j].value, row[j].label)),
            ],
            // fill empty slots so alignment stays consistent
            if (row.length < cols)
              for (int k = row.length; k < cols; k++) ...[
                Container(width: 1, height: 28, color: Colors.transparent),
                const Expanded(child: SizedBox()),
              ],
          ],
        ),
      );
      if (i + cols < items.length) {
        rows.add(Container(height: 1, color: const Color(0xFF1A2A3A)));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1320).withAlpha(210),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3349)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  Widget _statCell(String value, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFDFECF8),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF5280A0), fontSize: 9),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
