import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/engines/predator_score_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/services/app_providers.dart';

// Score wird über globalen predatorScoreProvider aus app_providers.dart bezogen

// ─── Predator Index ──────────────────────────────────────────────────────────

class PredatorIndexCard extends ConsumerWidget {
  const PredatorIndexCard({super.key, required this.score});
  final PredatorScore score;

  Color get _scoreColor {
    if (score.score >= 70) return ApexColors.scoreHigh;
    if (score.score >= 40) return ApexColors.scoreMid;
    return ApexColors.scoreLow;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final manualTemp = ref.watch(waterTempProvider);
    final airTemp = score.weather.airTempC;
    final isDark = context.isDark;
    final sc = _scoreColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [sc.withAlpha(28), c.surface, c.surface]
              : [Colors.white, sc.withAlpha(14)],
        ),
        border: Border.all(color: sc.withAlpha(isDark ? 60 : 45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: sc.withAlpha(isDark ? 30 : 25),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          if (!isDark)
            BoxShadow(
              color: c.cardShadow,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          // Score + Gauge Row
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: sc.withAlpha(isDark ? 35 : 25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'PREDATOR INDEX',
                              style: TextStyle(
                                fontFamily: 'Rajdhani',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: sc,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${score.score}',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 86,
                          fontWeight: FontWeight.w700,
                          color: sc,
                          height: 0.9,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: sc.withAlpha(isDark ? 30 : 22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          score.label,
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: sc,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _ScoreGauge(score: score.score, color: sc, bgColor: c.border),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Weather chips row
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              children: [
                _WeatherChip(
                  emoji: score.weather.conditionEmoji,
                  label: score.weather.conditionLabel,
                  c: c,
                ),
                const SizedBox(width: 8),
                if (manualTemp != null) ...[
                  _WeatherChip(
                    emoji: '💧',
                    label: '${manualTemp.round()}°C Wasser',
                    highlight: true,
                    c: c,
                  ),
                  const SizedBox(width: 8),
                ] else if (airTemp != null) ...[
                  _WeatherChip(
                    emoji: '🌡',
                    label: 'Ges. ≈${airTemp.round()}°C',
                    c: c,
                  ),
                  const SizedBox(width: 8),
                ],
                _WeatherChip(emoji: '🌙', label: score.moonPhaseLabel, c: c),
                if (score.weather.pressureTendency3hHpa != null) ...[
                  const SizedBox(width: 8),
                  _WeatherChip(
                    emoji: score.weather.pressureTrendArrow,
                    label: score.weather.pressureTrendLabel,
                    highlight: score.weather.pressureTendency3hHpa! > 1.0,
                    c: c,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: c.border.withAlpha(120)),

          // Score Breakdown
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            child: _ScoreBreakdownBar(breakdown: score.scoreBreakdown),
          ),
        ],
      ),
    );
  }
}

class _ScoreGauge extends StatelessWidget {
  const _ScoreGauge({
    required this.score,
    required this.color,
    required this.bgColor,
  });
  final int score;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: CustomPaint(
        painter: _GaugePainter(
          value: score / 100,
          color: color,
          bgColor: bgColor,
        ),
        child: Center(
          child: Icon(Icons.wb_twilight, color: color.withAlpha(160), size: 28),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.value,
    required this.color,
    required this.bgColor,
  });
  final double value;
  final Color color;
  final Color bgColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi * 0.75,
      pi * 1.5,
      false,
      bgPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi * 0.75,
      pi * 1.5 * value,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

class _WeatherChip extends StatelessWidget {
  const _WeatherChip({
    required this.emoji,
    required this.label,
    required this.c,
    this.highlight = false,
  });
  final String emoji;
  final String label;
  final ApexColors c;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? ApexColors.primary.withAlpha(22) : c.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: highlight
            ? Border.all(color: ApexColors.primary.withAlpha(100))
            : Border.all(color: c.border.withAlpha(140)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: highlight ? ApexColors.primary : c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBreakdownBar extends StatelessWidget {
  const _ScoreBreakdownBar({required this.breakdown});
  final Map<String, double> breakdown;

  static const _maxes = {
    'circadian': 30.0,
    'pressure_trend': 18.0,
    'temperature': 25.0,
    'clarity': 12.0,
    'wind': 8.0,
    'sky': 7.0,
    'moon': 2.0,
  };
  static const _labels = {
    'circadian': 'Rhythmus',
    'pressure_trend': 'Tendenz',
    'temperature': 'Temp',
    'clarity': 'Sicht',
    'wind': 'Wind',
    'sky': 'Himmel',
    'moon': 'Mond',
  };

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SCORE-FAKTOREN',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: c.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _maxes.entries.map((e) {
            final val = breakdown[e.key] ?? 0;
            final pct = val / e.value;
            Color col;
            if (pct >= 0.7) {
              col = ApexColors.scoreHigh;
            } else if (pct >= 0.4) {
              col = ApexColors.scoreMid;
            } else {
              col = ApexColors.scoreLow;
            }
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _FactorBar(
                  label: _labels[e.key] ?? e.key,
                  percent: pct,
                  color: col,
                  c: c,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _FactorBar extends StatelessWidget {
  const _FactorBar({
    required this.label,
    required this.percent,
    required this.color,
    required this.c,
  });
  final String label;
  final double percent;
  final Color color;
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 5,
            backgroundColor: c.border,
            color: color,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Water Conditions Card ───────────────────────────────────────────────────

/// Manuelle Eingabe von Wassertemperatur und Sichttiefe.
/// Beeinflusst direkt den Predator Index (via waterTempProvider / waterClarityProvider).
class WaterConditionsCard extends ConsumerStatefulWidget {
  const WaterConditionsCard({super.key});

  @override
  ConsumerState<WaterConditionsCard> createState() =>
      _WaterConditionsCardState();
}

class _WaterConditionsCardState extends ConsumerState<WaterConditionsCard> {
  double? _draggingTemp;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final manualTemp = ref.watch(waterTempProvider);
    final manualClarity = ref.watch(waterClarityProvider);
    final manualBodyType = ref.watch(waterBodyTypeProvider);
    final airTemp =
        ref.watch(currentWeatherProvider).valueOrNull?.airTempC ?? 15.0;
    final displayTemp = (_draggingTemp ?? manualTemp ?? airTemp).clamp(
      0.0,
      30.0,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WASSERBEDINGUNGEN',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 12),

          // ── Wassertemperatur ────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.water_drop_outlined, size: 14, color: c.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Wassertemperatur',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              if (manualTemp == null)
                Text(
                  'Gesch. ≈${airTemp.round()}°C',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                )
              else ...[
                Text(
                  '${manualTemp.round()}°C',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ApexColors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() => _draggingTemp = null);
                    ref.read(waterTempProvider.notifier).state = null;
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: c.textMuted,
                  ),
                ),
              ],
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: ApexColors.primary,
              inactiveTrackColor: c.border,
              thumbColor: manualTemp != null ? ApexColors.primary : c.textMuted,
              overlayColor: ApexColors.primary.withAlpha(30),
              valueIndicatorColor: ApexColors.primary,
              valueIndicatorTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: displayTemp,
              min: 0,
              max: 30,
              divisions: 60,
              label: '${displayTemp.round()}°C',
              onChanged: (v) => setState(() => _draggingTemp = v),
              onChangeEnd: (v) {
                setState(() => _draggingTemp = null);
                ref.read(waterTempProvider.notifier).state = v;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0°C', style: TextStyle(fontSize: 9, color: c.textMuted)),
                Text('15°C', style: TextStyle(fontSize: 9, color: c.textMuted)),
                Text('30°C', style: TextStyle(fontSize: 9, color: c.textMuted)),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: c.border.withAlpha(100)),
          const SizedBox(height: 14),

          // ── Sichttiefe ──────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 14, color: c.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Sichttiefe',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              if (manualClarity == null)
                Text(
                  'Auto (Wind/Regen)',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                )
              else
                GestureDetector(
                  onTap: () =>
                      ref.read(waterClarityProvider.notifier).state = null,
                  child: Row(
                    children: [
                      Text(
                        'Zurücksetzen',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.close_rounded, size: 14, color: c.textMuted),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: WaterClarity.values.map((clarity) {
              final isSelected = manualClarity == clarity;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () => ref.read(waterClarityProvider.notifier).state =
                        isSelected ? null : clarity,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? ApexColors.primary.withAlpha(35)
                            : c.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? ApexColors.primary : c.border,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            clarity.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? ApexColors.primary
                                  : c.textSecondary,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            clarity.depthLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: isSelected
                                  ? ApexColors.primary.withAlpha(180)
                                  : c.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: c.border.withAlpha(100)),
          const SizedBox(height: 14),

          // ── Gewässertyp ─────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.waves_outlined, size: 14, color: c.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Gewässertyp',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              if (manualBodyType == null)
                Text(
                  'Neutral',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                )
              else
                GestureDetector(
                  onTap: () =>
                      ref.read(waterBodyTypeProvider.notifier).state = null,
                  child: Row(
                    children: [
                      Text(
                        'Zurücksetzen',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.close_rounded, size: 14, color: c.textMuted),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: WaterBodyType.values.map((type) {
              final isSelected = manualBodyType == type;
              final icon = type == WaterBodyType.standing
                  ? Icons.pool_outlined
                  : Icons.waves_rounded;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(waterBodyTypeProvider.notifier).state =
                            isSelected ? null : type,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? ApexColors.primary.withAlpha(35)
                            : c.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? ApexColors.primary : c.border,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 18,
                            color: isSelected
                                ? ApexColors.primary
                                : c.textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            type.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? ApexColors.primary
                                  : c.textSecondary,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            type.hint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: isSelected
                                  ? ApexColors.primary.withAlpha(180)
                                  : c.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
