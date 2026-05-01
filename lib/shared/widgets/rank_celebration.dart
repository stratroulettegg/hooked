import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../models/player_rank.dart';
import '../services/app_providers.dart';
import 'pb_celebration.dart';

/// Globaler Controller — erlaubt das Auslösen der Party von überall.
final rankCelebrationControllerProvider = Provider<RankCelebrationController>(
  (_) => RankCelebrationController(),
);

class RankCelebrationController {
  final ValueNotifier<PlayerRank?> current = ValueNotifier<PlayerRank?>(null);

  void trigger(PlayerRank rank) {
    current.value = rank;
  }

  void dismiss() {
    current.value = null;
  }
}

/// Wrapper, der die App umschließt und bei Rang-Aufstiegen Konfetti zeigt.
class RankCelebrationHost extends ConsumerStatefulWidget {
  const RankCelebrationHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<RankCelebrationHost> createState() =>
      _RankCelebrationHostState();
}

class _RankCelebrationHostState extends ConsumerState<RankCelebrationHost> {
  static const _prefsKey = 'rank_last_seen_min_points';
  int? _lastSeenMinPoints;
  bool _loaded = false;
  bool _baselineSynced = false;

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
  }

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSeenMinPoints = prefs.getInt(_prefsKey);
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCelebrate());
  }

  Future<void> _persist(int minPoints) async {
    _lastSeenMinPoints = minPoints;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, minPoints);
  }

  int? _computePoints() {
    final statsAsync = ref.read(catchStatsProvider);
    final missionsAsync = ref.read(missionProvider);
    // Erst rechnen, wenn beide Provider tatsächlich Daten geliefert haben.
    // Sonst würden wir bei jedem (Hot-)Start zuerst 0 Punkte „sehen" und
    // danach beim Daten-Nachschub fälschlich eine Rangerhöhung erkennen.
    if (!statsAsync.hasValue || !missionsAsync.hasValue) return null;
    final stats = statsAsync.value!;
    final missions = missionsAsync.value!;
    final missionPoints = missions
        .where((m) => m.isCompleted)
        .fold<int>(0, (s, m) => s + m.pointsReward);
    return stats.total * 50 + missionPoints;
  }

  void _maybeCelebrate() {
    if (!_loaded || !mounted) return;
    final points = _computePoints();
    if (points == null) return; // Daten noch nicht bereit

    final rank = PlayerRank.forPoints(points);

    // Allererster vollständig geladener Check nach App-Start: Baseline still
    // mit dem echten aktuellen Rang synchronisieren. Dadurch triggert kein
    // Hot-Restart / Kaltstart die Party, selbst wenn die alte Baseline durch
    // frühere Läufe verrutscht war.
    if (!_baselineSynced) {
      _baselineSynced = true;
      if (_lastSeenMinPoints != rank.minPoints) {
        _persist(rank.minPoints);
      }
      return;
    }

    if (_lastSeenMinPoints == null) {
      _persist(rank.minPoints);
      return;
    }

    if (rank.minPoints > _lastSeenMinPoints!) {
      _persist(rank.minPoints);
      ref.read(rankCelebrationControllerProvider).trigger(rank);
    } else if (rank.minPoints < _lastSeenMinPoints!) {
      _persist(rank.minPoints);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(catchStatsProvider, (_, __) => _maybeCelebrate());
    ref.listen(missionProvider, (_, __) => _maybeCelebrate());

    final controller = ref.watch(rankCelebrationControllerProvider);
    final pbController = ref.watch(pbCelebrationControllerProvider);

    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        // Rang-Overlay wartet, bis eine PB-Party fertig ist, damit sich beide
        // Feuerwerke nicht überlagern.
        AnimatedBuilder(
          animation: Listenable.merge([
            controller.current,
            pbController.current,
          ]),
          builder: (_, __) {
            final rank = controller.current.value;
            final pbActive = pbController.current.value != null;
            if (rank == null || pbActive) return const SizedBox.shrink();
            return _RankUpOverlay(
              key: ValueKey(rank.minPoints),
              rank: rank,
              onDismiss: controller.dismiss,
            );
          },
        ),
      ],
    );
  }
}

// ─── Overlay ─────────────────────────────────────────────────────────────────

class _RankUpOverlay extends StatefulWidget {
  const _RankUpOverlay({
    super.key,
    required this.rank,
    required this.onDismiss,
  });
  final PlayerRank rank;
  final VoidCallback onDismiss;

  @override
  State<_RankUpOverlay> createState() => _RankUpOverlayState();
}

class _RankUpOverlayState extends State<_RankUpOverlay>
    with TickerProviderStateMixin {
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
      duration: const Duration(milliseconds: 500),
    )..forward();
    // Konfetti fällt lange genug, dass alle Partikel den unteren Rand passieren.
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..forward();
    // Separater Fade-Controller für ein sanftes Ausblenden.
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );

    final rnd = Random();
    _particles = List.generate(90, (_) => _Particle.random(rnd));

    // Karte bleibt ~2,6s, danach sanfter Fade; Konfetti läuft parallel zu Ende.
    Future.delayed(const Duration(milliseconds: 2600), _dismiss);
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
    final rank = widget.rank;
    return Positioned.fill(
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
        child: Stack(
          children: [
            // Abgedunkelter Hintergrund (fadet mit dem Overlay).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: Container(color: Colors.black.withAlpha(140)),
              ),
            ),
            // Konfetti-Layer (über Hintergrund, tap-transparent).
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
            // Rang-Karte
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
                    child: _RankCard(rank: rank),
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

class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank});
  final PlayerRank rank;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
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
            'NEUER RANG',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: ApexColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(rank.emoji, style: const TextStyle(fontSize: 54)),
          ),
          const SizedBox(height: 18),
          Text(
            rank.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: ApexColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Du bist jetzt ${rank.title}!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Confetti ─────────────────────────────────────────────────────────────────

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
      // Start knapp über dem Screen, fällt linear mit vy und passiert den
      // unteren Rand bevor die Animation endet.
      final dy = (-0.08 + p.vy * t * 1.35) * size.height;

      if (dy > size.height + 40)
        continue; // komplett durch → nicht mehr zeichnen

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
