import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/engines/predator_score_engine.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/daily_forecast_card.dart';
import '../../shared/widgets/water_location_field.dart';
import 'widgets/predator_index_widgets.dart'
    show WaterConditionsCard, PredatorIndexCard;

final _forecastWeatherProvider = FutureProvider<WeatherData?>((ref) async {
  return ref.watch(currentWeatherProvider.future);
});

class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(_forecastWeatherProvider);
    final species = ref.watch(selectedSpeciesProvider);
    final scoreAsync = ref.watch(predatorScoreProvider);

    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_forecastWeatherProvider),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: weatherAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ApexColors.primary),
        ),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (weather) {
          final now = DateTime.now();
          final waterTemp = ref.watch(waterTempProvider);
          final waterClarity = ref.watch(waterClarityProvider);
          final waterBodyType = ref.watch(waterBodyTypeProvider);
          final score = scoreAsync.maybeWhen(
            data: (s) => s,
            orElse: () => PredatorScoreEngine.calculate(
              weather: weather ?? const WeatherData(),
              now: now,
              species: species,
              waterTempC: waterTemp,
              waterClarity: waterClarity,
              waterBodyType: waterBodyType,
            ),
          );
          return RefreshIndicator(
            color: ApexColors.primary,
            backgroundColor: ApexColors.of(context).surface,
            onRefresh: () async {
              ref.invalidate(locationProvider);
              ref.invalidate(currentWeatherProvider);
              ref.invalidate(predatorScoreProvider);
              ref.invalidate(_forecastWeatherProvider);
              await ref.read(currentWeatherProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Location-Picker mit Gewässer-Suche
                const _LocationPickerCard(),
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

                // Haupt-Score
                PredatorIndexCard(score: score),
                const SizedBox(height: 16),

                // Circadiane Aktivitätsfenster
                _CircadianCard(species: species, now: now),
                const SizedBox(height: 16),

                // Wetter-Details
                if (weather != null) ...[
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
                        date: now,
                        title: 'WETTER HEUTE',
                        // Aktuelle 3h-Tendenz priorisieren – f\u00fcr Angler relevanter
                        // als der 24h-Tagesmittelwert, weil sie Frontdurchg\u00e4nge zeigt.
                        liveTrend3hHpa: weather.pressureTendency3hHpa,
                        liveAbsoluteHpa: weather.pressureHpa,
                        liveWeather: weather,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

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
