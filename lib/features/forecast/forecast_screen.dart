import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../core/engines/predator_score_engine.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/pro/pro_providers.dart';
import '../../shared/services/weather_service.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/daily_forecast_card.dart';
import '../../shared/widgets/water_location_field.dart';
import '../pro/pro_gate.dart';
import 'widgets/predator_index_widgets.dart'
    show WaterConditionsCard, PredatorIndexCard;

// Smarter Weather-Provider: heute → Live-Daten, Folgetage → DailyForecast-API.
// Reagiert reaktiv auf Änderungen an selectedForecastDateTimeProvider und
// forecastLocationOverrideProvider.
final _forecastWeatherProvider = FutureProvider<WeatherData?>((ref) async {
  final selected = ref.watch(selectedForecastDateTimeProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final selectedDay = DateTime(selected.year, selected.month, selected.day);

  if (selectedDay == today) {
    // Aktuelles Wetter vom Live-Provider
    return ref.watch(currentWeatherProvider.future);
  }

  // Für Folgetage: Standort ermitteln, dann DailyForecast laden.
  final override = ref.watch(forecastLocationOverrideProvider);
  final pos = await ref.watch(locationProvider.future);
  final lat = override?.latitude ?? pos?.latitude ?? 48.137154;
  final lng = override?.longitude ?? pos?.longitude ?? 11.576124;

  final forecast = await WeatherService().fetchDailyForecast(lat, lng, selected);
  if (forecast == null) return null;

  // Temperatur stündlich interpolieren (Peak ~14 Uhr, Minimum ~5 Uhr).
  double? temp;
  if (forecast.tempMinC != null && forecast.tempMaxC != null) {
    final h = selected.hour.toDouble();
    final double factor;
    if (h <= 14) {
      factor = ((h - 5) / 9.0).clamp(0.0, 1.0); // Aufwärmen 5→14 Uhr
    } else {
      factor = ((24 - h) / 10.0).clamp(0.0, 1.0); // Abkühlen 14→24 Uhr
    }
    temp = forecast.tempMinC! +
        (forecast.tempMaxC! - forecast.tempMinC!) * factor;
  } else {
    temp = forecast.tempMaxC ?? forecast.tempMinC;
  }

  return WeatherData(
    airTempC: temp,
    pressureHpa: forecast.pressureHpaMean,
    // 24h-Tendenz auf 3h-Fenster skalieren.
    pressureTendency3hHpa: forecast.pressureTrendHpa24h != null
        ? forecast.pressureTrendHpa24h! / 8.0
        : null,
    windSpeedKmh: forecast.windSpeedMaxKmh,
    windDirectionDeg: forecast.windDirectionDominantDeg,
    precipitationMm: forecast.precipitationSumMm,
    weatherCode: forecast.weatherCode,
  );
});

class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  static bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(_forecastWeatherProvider);
    final species = ref.watch(selectedSpeciesProvider);
    final selectedDt = ref.watch(selectedForecastDateTimeProvider);

    return Scaffold(
      appBar: const ApexAppBar(),
      body: weatherAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(
          child: CircularProgressIndicator(color: ApexColors.primary),
        ),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (weather) {
          final waterTemp = ref.watch(waterTempProvider);
          final waterClarity = ref.watch(waterClarityProvider);
          final waterBodyType = ref.watch(waterBodyTypeProvider);
          final score = PredatorScoreEngine.calculate(
            weather: weather ?? const WeatherData(),
            now: selectedDt,
            species: species,
            waterTempC: waterTemp,
            waterClarity: waterClarity,
            waterBodyType: waterBodyType,
          );
          final isToday = _isToday(selectedDt);

          return RefreshIndicator(
            color: ApexColors.primary,
            backgroundColor: ApexColors.of(context).surface,
            onRefresh: () async {
              ref.read(selectedForecastDateTimeProvider.notifier).state =
                  DateTime.now();
              ref.invalidate(locationProvider);
              ref.invalidate(currentWeatherProvider);
              ref.invalidate(predatorScoreProvider);
              await ref.read(currentWeatherProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Location-Picker mit Gewässer-Suche
                const _LocationPickerCard(),
                const SizedBox(height: 12),

                // Datum + Uhrzeit (Pro-Feature)
                const _DateTimePickerCard(),
                const SizedBox(height: 16),

                // Artauswahl
                _SpeciesChips(
                  current: species,
                  onSelect: (p) =>
                      ref.read(selectedSpeciesProvider.notifier).state = p,
                ),
                const SizedBox(height: 16),

                // Wasserbedingungen
                const WaterConditionsCard(),
                const SizedBox(height: 16),

                // Haupt-Score — berechnet für selectedDt
                PredatorIndexCard(score: score),
                const SizedBox(height: 16),

                // Circadiane Aktivitätsfenster für selectedDt
                _CircadianCard(species: species, now: selectedDt),
                const SizedBox(height: 16),

                // Wetter für den gewählten Tag
                Builder(
                  builder: (context) {
                    final override = ref.watch(
                      forecastLocationOverrideProvider,
                    );
                    final pos = ref.watch(locationProvider).valueOrNull;
                    final lat =
                        override?.latitude ?? pos?.latitude ?? 48.137154;
                    final lng =
                        override?.longitude ?? pos?.longitude ?? 11.576124;
                    return DailyForecastCard(
                      latitude: lat,
                      longitude: lng,
                      date: selectedDt,
                      title: isToday ? 'WETTER HEUTE' : 'WETTER',
                      liveTrend3hHpa:
                          isToday ? weather?.pressureTendency3hHpa : null,
                      liveAbsoluteHpa: isToday ? weather?.pressureHpa : null,
                      liveWeather: isToday ? weather : null,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Mondphase
                _MoonPhaseCard(score: score),
                const SizedBox(height: 16),

                // Score-Erklärung
                _ScoreExplanationCard(score: score),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Circadiane Aktivitätsfenster — wissenschaftlich fundiert durch Radiotelemetrie-Studien.
/// Ersetzt die nicht belegte "Solunar"-Theorie.
class _CircadianCard extends StatelessWidget {
  const _CircadianCard({required this.species, required this.now});
  final SpeciesProfile species;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final today = DateTime(now.year, now.month, now.day);

    // Aktivitätsfenster aus Artprofil ableiten
    final windows = <_ActivityWindow>[];
    if (species.dawnWeight >= 1.3) {
      windows.add(
        _ActivityWindow(
          'Morgendämmerung',
          today.add(const Duration(hours: 5)),
          today.add(const Duration(hours: 9, minutes: 30)),
          species.dawnWeight >= 1.8,
        ),
      );
    }
    if (species.duskWeight >= 1.3) {
      windows.add(
        _ActivityWindow(
          'Abendämmerung',
          today.add(const Duration(hours: 17)),
          today.add(const Duration(hours: 22)),
          species.duskWeight >= 1.8,
        ),
      );
    }
    if (species.nightWeight >= 1.5) {
      windows.add(
        _ActivityWindow(
          'Nacht',
          today.add(const Duration(hours: 22)),
          today.add(const Duration(days: 1, hours: 4)),
          species.nightWeight >= 1.8,
        ),
      );
    }
    if (windows.isEmpty) {
      windows.add(
        _ActivityWindow(
          'Tagzeit (diurnal)',
          today.add(const Duration(hours: 7)),
          today.add(const Duration(hours: 19)),
          false,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AKTIVITÄTSFENSTER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message:
                    'Basierend auf circadianen Aktivitätsmustern (Lucas & Baras 2001)',
                child: Icon(Icons.info_outline, size: 14, color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...windows.map((w) {
            final isActive = now.isAfter(w.start) && now.isBefore(w.end);
            final isPast = now.isAfter(w.end);
            final color = isActive
                ? ApexColors.primary
                : isPast
                ? c.textMuted
                : c.textSecondary;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    w.isPeak ? Icons.wb_twilight : Icons.access_time,
                    color: color,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                        Text(
                          '${AppDateFormats.hourMinute.format(w.start)} – ${AppDateFormats.hourMinute.format(w.end)}',
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ApexColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'JETZT',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: c.background,
                          letterSpacing: 1,
                        ),
                      ),
                    )
                  else if (w.isPeak && !isPast)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.primaryGlow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: ApexColors.primary.withAlpha(80),
                        ),
                      ),
                      child: Text(
                        'PRIME',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: ApexColors.primary,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ActivityWindow {
  const _ActivityWindow(this.label, this.start, this.end, this.isPeak);
  final String label;
  final DateTime start;
  final DateTime end;
  final bool isPeak; // true = artspezifisch besonders aktivierende Zeit
}

class _ScoreExplanationCard extends StatelessWidget {
  const _ScoreExplanationCard({required this.score});
  final PredatorScore score;

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
    'circadian': 'Tagesrhythmus',
    'pressure_trend': 'Drucktendenz',
    'temperature': 'Temperatur',
    'clarity': 'Sichttiefe',
    'wind': 'Wind',
    'sky': 'Himmelsbild',
    'moon': 'Mondphase',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ApexColors.of(context).surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ApexColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SCORE-AUFSCHLÜSSELUNG',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: ApexColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 12),
          ..._maxes.entries.map((e) {
            final val = score.scoreBreakdown[e.key] ?? 0;
            final pct = val / e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _labels[e.key] ?? e.key,
                        style: TextStyle(
                          fontSize: 13,
                          color: ApexColors.of(context).textSecondary,
                        ),
                      ),
                      Text(
                        '${val.round()} / ${e.value.round()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: pct >= 0.7
                              ? ApexColors.scoreHigh
                              : pct >= 0.4
                              ? ApexColors.scoreMid
                              : ApexColors.scoreLow,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: ApexColors.of(context).border,
                      color: pct >= 0.7
                          ? ApexColors.scoreHigh
                          : pct >= 0.4
                          ? ApexColors.scoreMid
                          : ApexColors.scoreLow,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Artauswahl-Chips ────────────────────────────────────────────────────────

class _SpeciesChips extends StatelessWidget {
  const _SpeciesChips({required this.current, required this.onSelect});

  final SpeciesProfile current;
  final ValueChanged<SpeciesProfile> onSelect;

  static const _profiles = [
    SpeciesProfiles.hecht,
    SpeciesProfiles.zander,
    SpeciesProfiles.barsch,
    SpeciesProfiles.wels,
    SpeciesProfiles.forelle,
    SpeciesProfiles.huchen,
    SpeciesProfiles.aal,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = ApexColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ZIELFISCH',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.4,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _profiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = _profiles[i];
              final selected = p.name == current.name;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: selected ? ApexColors.primary : colors.surface,
                  border: Border.all(
                    color: selected ? ApexColors.primary : colors.border,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: InkWell(
                  onTap: () => onSelect(p),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        p.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.black : colors.textPrimary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (current.hint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            current.hint,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

// ─── Location Picker Card ────────────────────────────────────────────────────

class _LocationPickerCard extends ConsumerWidget {
  const _LocationPickerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(forecastLocationOverrideProvider);
    final gpsAsync = ref.watch(locationProvider);

    final isOverride = override != null;
    final label = isOverride
        ? override.label
        : gpsAsync.maybeWhen(
            data: (p) =>
                p != null ? 'Aktueller Standort' : 'Standardort (München)',
            orElse: () => 'Standort wird ermittelt …',
          );

    return WaterLocationField(
      sectionLabel: isOverride ? 'GEWÄSSER' : 'STANDORT',
      label: label,
      hasLocation: isOverride,
      icon: Icons.water_drop,
      placeholderIcon: Icons.my_location,
      mapInitial: isOverride
          ? LatLng(override.latitude, override.longitude)
          : null,
      onClear: isOverride
          ? () {
              ref.read(forecastLocationOverrideProvider.notifier).state = null;
              ref.invalidate(currentWeatherProvider);
              ref.invalidate(predatorScoreProvider);
            }
          : null,
      onPicked: (p) {
        ref.read(forecastLocationOverrideProvider.notifier).state =
            ForecastLocation(latitude: p.lat, longitude: p.lng, label: p.label);
        ref.invalidate(currentWeatherProvider);
        ref.invalidate(predatorScoreProvider);
      },
    );
  }
}

// ─── Mondphase ────────────────────────────────────────────────────────────────

class _MoonPhaseCard extends StatelessWidget {
  const _MoonPhaseCard({required this.score});
  final PredatorScore score;

  @override
  Widget build(BuildContext context) {
    final phase = score.moonPhase;
    final label = score.moonPhaseLabel;
    final moonScore = score.scoreBreakdown['moon'] ?? 0.0;
    final illum = phase <= 0.5
        ? (phase * 2 * 100).round()
        : ((1 - phase) * 2 * 100).round();
    final influence = (moonScore / 2.0).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1422), Color(0xFF0F1F35), Color(0xFF0B1422)],
          ),
        ),
        child: Stack(
          children: [
            // Sterne-Hintergrund
            Positioned.fill(
              child: CustomPaint(painter: _StarfieldPainter()),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Text(
                    'MONDPHASE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: Color(0xFF8899AA),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      // Mond-Grafik (groß, mit Glow)
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: CustomPaint(
                          painter: _MoonPainter(phase: phase),
                        ),
                      ),
                      const SizedBox(width: 24),

                      // Info-Spalte
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Rajdhani',
                                color: Color(0xFFE8DFC8),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$illum% beleuchtet',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF8899AA),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Einfluss-Label
                            const Text(
                              'EINFLUSS AUF BISSSTIMMUNG',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.4,
                                color: Color(0xFF556677),
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Dot-Anzeige (5 Punkte)
                            Row(
                              children: List.generate(5, (i) {
                                final filled = i < (influence * 5).ceil();
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: filled
                                          ? ApexColors.primary
                                          : const Color(0xFF1E2D40),
                                      boxShadow: filled
                                          ? [
                                              BoxShadow(
                                                color: ApexColors.primary
                                                    .withAlpha(140),
                                                blurRadius: 6,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              influence > 0.7
                                  ? 'Starker Einfluss auf Aktivität'
                                  : influence > 0.4
                                      ? 'Moderater Einfluss'
                                      : 'Geringer Einfluss',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6677AA),
                              ),
                            ),
                          ],
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
}

/// Zeichnet einen realistischen Mond mit Glow, Textur und Sichel-Schatten.
class _MoonPainter extends CustomPainter {
  const _MoonPainter({required this.phase});
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    final circleRect = Rect.fromCircle(center: c, radius: r);

    final illum = (phase <= 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.0, 1.0);
    final waxing = phase <= 0.5;

    // ── Äußerer Glow (vor Clip, damit er außen strahlt) ──────────────────────
    if (illum > 0.05) {
      canvas.drawCircle(
        c,
        r + 14,
        Paint()
          ..color = Color.fromARGB((illum * 55).round().clamp(0, 80), 255, 235, 155)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // ── Alles folgend strikt auf Mondscheibe begrenzen ───────────────────────
    canvas.save();
    canvas.clipPath(Path()..addOval(circleRect));

    // Dunkler Hintergrund
    canvas.drawPaint(Paint()..color = const Color(0xFF070F1C));

    if (illum > 0.01) {
      final litShader = RadialGradient(
        center: const Alignment(-0.25, -0.3),
        radius: 0.95,
        colors: const [Color(0xFFEDE5C5), Color(0xFFBFAF7A)],
      ).createShader(circleRect);
      final litPaint = Paint()..shader = litShader;

      if (illum > 0.99) {
        // Vollmond
        canvas.drawCircle(c, r, litPaint);
      } else {
        // Terminator-Ellipse x-Radius: 0 bei Viertelmond, r bei Neu-/Vollmond
        final xr = max(1.5, r * (1.0 - 2.0 * illum).abs());
        final termRect = Rect.fromCenter(center: c, width: xr * 2, height: r * 2);

        // Lit-Bereich: Außenbogen (Hälfte des Mondkreises) +
        //              Terminatorbogen (Sichelinnenkante).
        //
        // Wachsend (rechts beleuchtet):
        //   Außen = rechte Hälfte CW   (-pi/2, +pi)
        //   Terminator Sichel  = CCW via rechts  (pi/2, -pi)  → biegt rechts
        //   Terminator Gibbous = CW  via links   (pi/2, +pi)  → biegt links
        //
        // Abnehmend (links beleuchtet): gespiegelt
        final path = Path()..moveTo(c.dx, c.dy - r);
        if (waxing) {
          path.arcTo(circleRect, -pi / 2, pi, false);
          path.arcTo(termRect, pi / 2, illum < 0.5 ? -pi : pi, false);
        } else {
          path.arcTo(circleRect, -pi / 2, -pi, false);
          path.arcTo(termRect, pi / 2, illum < 0.5 ? pi : -pi, false);
        }
        path.close();
        canvas.drawPath(path, litPaint);
      }

      // Krater (weich, dezent)
      final craterPaint = Paint()
        ..color = const Color(0x1A000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      for (final cr in [
        (0.20, -0.25, 0.13),
        (-0.28, 0.18, 0.10),
        (0.12, 0.38, 0.08),
        (0.38, 0.07, 0.06),
        (-0.14, -0.08, 0.07),
      ]) {
        canvas.drawCircle(
          Offset(c.dx + cr.$1 * r, c.dy + cr.$2 * r),
          cr.$3 * r,
          craterPaint,
        );
      }
    }

    canvas.restore();

    // ── Atmosphärischer Rand (außerhalb Clip) ────────────────────────────────
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0x35B0A870)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_MoonPainter old) => old.phase != phase;
}

/// Zufällige Sternenpunkte — deterministisch via fester Seed-Positionen.
class _StarfieldPainter extends CustomPainter {
  static const _stars = [
    (0.05, 0.12), (0.92, 0.08), (0.15, 0.75), (0.80, 0.60),
    (0.35, 0.05), (0.68, 0.90), (0.50, 0.30), (0.22, 0.55),
    (0.88, 0.40), (0.10, 0.90), (0.75, 0.20), (0.60, 0.70),
    (0.40, 0.85), (0.95, 0.55), (0.28, 0.35), (0.82, 0.78),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x55AABBCC);
    for (final s in _stars) {
      canvas.drawCircle(
        Offset(s.$1 * size.width, s.$2 * size.height),
        1.2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter _) => false;
}

// ─── Datum + Uhrzeit Picker (Pro-Feature) ────────────────────────────────────

class _DateTimePickerCard extends ConsumerStatefulWidget {
  const _DateTimePickerCard();

  @override
  ConsumerState<_DateTimePickerCard> createState() =>
      _DateTimePickerCardState();
}

class _DateTimePickerCardState extends ConsumerState<_DateTimePickerCard> {
  static const _itemH = 44.0;
  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  late final DateTime _today;
  late final List<DateTime> _days;
  late final FixedExtentScrollController _dayCtrl;
  late final FixedExtentScrollController _hourCtrl;

  int _selDay = 0;
  int _selHour = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _days = List.generate(7, (i) => _today.add(Duration(days: i)));

    final sel = ref.read(selectedForecastDateTimeProvider);
    final selDay = DateTime(sel.year, sel.month, sel.day);
    _selDay = _days.indexWhere((d) => d == selDay).clamp(0, 6);
    _selHour = sel.hour;

    _dayCtrl = FixedExtentScrollController(initialItem: _selDay);
    _hourCtrl = FixedExtentScrollController(initialItem: _selHour);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dayCtrl.dispose();
    _hourCtrl.dispose();
    super.dispose();
  }

  void _onDayChanged(int idx) {
    setState(() => _selDay = idx);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final d = _days[idx];
      ref.read(selectedForecastDateTimeProvider.notifier).state =
          DateTime(d.year, d.month, d.day, _selHour);
    });
  }

  void _onHourChanged(int hour) {
    setState(() => _selHour = hour);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final d = _days[_selDay];
      ref.read(selectedForecastDateTimeProvider.notifier).state =
          DateTime(d.year, d.month, d.day, hour);
    });
  }

  String _dayLabel(int idx) {
    final d = _days[idx];
    if (d == _today) return 'Heute';
    return '${_weekdays[d.weekday - 1]}  ${d.day}.${d.month}.';
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider);
    if (!isPro) return const _DateTimePickerLocked();

    final c = ApexColors.of(context);
    const pickerH = _itemH * 3;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Label + gewählter Zeitpunkt als Summary
          Row(
            children: [
              Text(
                'ZEITPUNKT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: c.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${_dayLabel(_selDay)}  ·  ${_selHour.toString().padLeft(2, '0')}:00 Uhr',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Rajdhani',
                  color: ApexColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Drum-Roll Picker
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: pickerH,
              child: Stack(
                children: [
                  // Hintergrund
                  Container(color: c.background),

                  // Auswahl-Highlight (mittlere Zeile)
                  Positioned(
                    top: _itemH,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: _itemH,
                      decoration: BoxDecoration(
                        color: ApexColors.primary.withAlpha(18),
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: ApexColors.primary.withAlpha(90),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Zwei Scroll-Räder nebeneinander
                  Row(
                    children: [
                      // Tage
                      Expanded(
                        flex: 5,
                        child: ListWheelScrollView.useDelegate(
                          controller: _dayCtrl,
                          itemExtent: _itemH,
                          perspective: 0.002,
                          diameterRatio: 2.5,
                          physics: const FixedExtentScrollPhysics(),
                          onSelectedItemChanged: _onDayChanged,
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: 7,
                            builder: (_, i) => Center(
                              child: Text(
                                _dayLabel(i),
                                style: TextStyle(
                                  fontFamily: 'Rajdhani',
                                  fontSize: i == _selDay ? 16 : 13,
                                  fontWeight: i == _selDay
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: i == _selDay
                                      ? ApexColors.primary
                                      : c.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Trennlinie
                      Container(width: 1, height: pickerH, color: c.border),

                      // Stunden
                      Expanded(
                        flex: 5,
                        child: ListWheelScrollView.useDelegate(
                          controller: _hourCtrl,
                          itemExtent: _itemH,
                          perspective: 0.002,
                          diameterRatio: 2.5,
                          physics: const FixedExtentScrollPhysics(),
                          onSelectedItemChanged: _onHourChanged,
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: 24,
                            builder: (_, h) => Center(
                              child: Text(
                                '${h.toString().padLeft(2, '0')}:00 Uhr',
                                style: TextStyle(
                                  fontFamily: 'Rajdhani',
                                  fontSize: h == _selHour ? 16 : 13,
                                  fontWeight: h == _selHour
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: h == _selHour
                                      ? ApexColors.primary
                                      : c.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Fade-Überblendung oben & unten
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    c.background,
                                    c.background.withAlpha(0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: _itemH),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    c.background,
                                    c.background.withAlpha(0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakter gesperrter Einstiegspunkt für nicht-Pro-User.
class _DateTimePickerLocked extends ConsumerWidget {
  const _DateTimePickerLocked();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showPaywall(context, feature: ProFeature.predatorForecast),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, color: c.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ZEITPUNKT WÄHLEN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: c.textMuted,
                    ),
                  ),
                  Text(
                    '7 Tage · beliebige Uhrzeit',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ApexColors.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ApexColors.primary.withAlpha(80)),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: ApexColors.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


