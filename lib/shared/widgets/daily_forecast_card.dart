import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/engines/predator_score_engine.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../services/app_providers.dart';

/// Tagesvorhersage-Karte (Emoji, Min/Max, Wind, Regen, Drucktendenz,
/// Sonnenauf-/-untergang). Wird sowohl im Trip-Detail als auch auf dem
/// Home-Screen genutzt.
class DailyForecastCard extends ConsumerWidget {
  const DailyForecastCard({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.date,
    this.title = 'WETTER',
    this.liveTrend3hHpa,
    this.liveAbsoluteHpa,
    this.liveWeather,
  });

  final double latitude;
  final double longitude;
  final DateTime date;
  final String title;

  /// Optional: aktuelle 3h-Drucktendenz (überschreibt 24h-Tagesmittel).
  /// Wird auf der Forecast-Seite für „heute“ verwendet, damit Angler die
  /// kurzfristige Frontentwicklung sehen.
  final double? liveTrend3hHpa;

  /// Optional: aktueller absoluter Druck (passend zu [liveTrend3hHpa]).
  final double? liveAbsoluteHpa;

  /// Optional: aktuelle Wetterdaten (Wind, Regen, Bewölkung).
  /// Überschreibt — wenn vorhanden — die Tagesaggregate für Wind, Regen und
  /// Bedingung (Emoji + Label). So zeigt die Karte den Jetzt-Zustand statt des
  /// Tagesresümees, sofern kein explizites Datum (z.B. Trip) verlangt ist.
  final WeatherData? liveWeather;

  /// Format: "↗ +1.5 hPa · 1018"
  static String _formatTrend(double deltaHpa, double? absoluteHpa) {
    final sign = deltaHpa >= 0 ? '+' : '';
    final arrow = deltaHpa >= 1.0
        ? '↗'
        : deltaHpa <= -1.0
        ? '↘'
        : '→';
    final delta = '$arrow $sign${deltaHpa.toStringAsFixed(1)} hPa';
    if (absoluteHpa == null) return delta;
    return '$delta · ${absoluteHpa.round()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final key = TripForecastKey(lat: latitude, lng: longitude, date: date);
    final forecastAsync = ref.watch(tripForecastProvider(key));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: forecastAsync.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(
            child: CircularProgressIndicator(color: ApexColors.primary),
          ),
        ),
        error: (e, _) => Text(
          'Wetter nicht verfügbar: $e',
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        data: (f) {
          if (f == null) {
            return Row(
              children: [
                Icon(Icons.cloud_off, color: c.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Wettervorhersage nur bis ~15 Tage im Voraus verfügbar.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 12,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700,
                      color: c.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    AppDateFormats.dayMonthShort.format(f.date),
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    liveWeather?.conditionEmoji ?? f.conditionEmoji,
                    style: const TextStyle(fontSize: 40),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          liveWeather?.conditionLabel ?? f.conditionLabel,
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${f.tempMinC?.round() ?? '–'}° / ${f.tempMaxC?.round() ?? '–'}° C',
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _ForecastMetric(
                    icon: Icons.air,
                    label: liveWeather?.windSpeedKmh != null
                        ? 'Wind · jetzt'
                        : 'Wind',
                    value: liveWeather?.windSpeedKmh != null
                        ? '${liveWeather!.windSpeedKmh!.round()} km/h ${liveWeather!.windDirectionLabel}'
                        : (f.windSpeedMaxKmh != null
                              ? '${f.windSpeedMaxKmh!.round()} km/h ${f.windDirectionLabel}'
                              : '–'),
                  ),
                  _ForecastMetric(
                    icon: Icons.water_drop_outlined,
                    label: liveWeather?.precipitationMm != null
                        ? 'Regen · jetzt'
                        : 'Regen',
                    value: liveWeather?.precipitationMm != null
                        ? '${liveWeather!.precipitationMm!.toStringAsFixed(1)} mm'
                        : (f.precipitationSumMm != null
                              ? '${f.precipitationSumMm!.toStringAsFixed(1)} mm'
                                    '${f.precipitationProbabilityMaxPct != null ? ' · ${f.precipitationProbabilityMaxPct!.round()}%' : ''}'
                              : '–'),
                  ),
                  if (liveTrend3hHpa != null)
                    _ForecastMetric(
                      icon: Icons.speed,
                      label: 'Luftdruck · 3h',
                      value: _formatTrend(
                        liveTrend3hHpa!,
                        liveAbsoluteHpa ?? f.pressureHpaMean,
                      ),
                    )
                  else if (f.pressureTrendHpa24h != null)
                    _ForecastMetric(
                      icon: Icons.speed,
                      label: 'Luftdruck · 24h',
                      value: _formatTrend(
                        f.pressureTrendHpa24h!,
                        f.pressureHpaMean,
                      ),
                    )
                  else if (f.pressureHpaMean != null)
                    _ForecastMetric(
                      icon: Icons.speed,
                      label: 'Luftdruck',
                      value: '${f.pressureHpaMean!.round()} hPa',
                    ),
                  if (f.sunrise != null)
                    _ForecastMetric(
                      icon: Icons.wb_twilight,
                      label: 'Sonnenaufg.',
                      value: AppDateFormats.hourMinute.format(f.sunrise!),
                    ),
                  if (f.sunset != null)
                    _ForecastMetric(
                      icon: Icons.nights_stay_outlined,
                      label: 'Sonnenunterg.',
                      value: AppDateFormats.hourMinute.format(f.sunset!),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ForecastMetric extends StatelessWidget {
  const _ForecastMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SizedBox(
      width: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ApexColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: c.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
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
