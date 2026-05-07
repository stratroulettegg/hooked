import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/engines/predator_score_engine.dart';
import '../models/trip.dart';

class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  Future<WeatherData?> fetchCurrent(double lat, double lng) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: {
          'latitude': lat.toString(),
          'longitude': lng.toString(),
          'current':
              'temperature_2m,surface_pressure,wind_speed_10m,wind_direction_10m,weather_code,precipitation',
          // Stündliche Luftdruckdaten der letzten 3h für 3h-Tendenzberechnung
          'hourly': 'surface_pressure',
          'past_hours': '3',
          'forecast_hours': '0',
          'timezone': 'auto',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      final currentPressure = (current['surface_pressure'] as num?)?.toDouble();

      // 3h-Drucktendenz: aktueller Druck minus ältester stündlicher Wert (~3h zurück)
      double? tendency;
      try {
        final hourly = json['hourly'] as Map<String, dynamic>?;
        final pressures = (hourly?['surface_pressure'] as List?)
            ?.map((e) => (e as num?)?.toDouble())
            .whereType<double>()
            .toList();
        if (pressures != null &&
            pressures.isNotEmpty &&
            currentPressure != null) {
          // pressures[0] = ältester Wert (~3h zurück), Tendenz = Δ zum aktuellen Druck
          tendency = currentPressure - pressures.first;
        }
      } catch (_) {
        // Tendenz nicht verfügbar — graceful degradation
      }

      return WeatherData(
        airTempC: (current['temperature_2m'] as num?)?.toDouble(),
        pressureHpa: currentPressure,
        pressureTendency3hHpa: tendency,
        windSpeedKmh: (current['wind_speed_10m'] as num?)?.toDouble(),
        windDirectionDeg: (current['wind_direction_10m'] as num?)?.toDouble(),
        precipitationMm: (current['precipitation'] as num?)?.toDouble(),
        weatherCode: current['weather_code'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Holt die Tagesvorhersage für ein bestimmtes Datum (bis ca. 16 Tage voraus).
  /// Gibt `null` zurück, wenn das Datum außerhalb des Vorhersagehorizonts liegt
  /// oder die API fehlschlägt.
  Future<DailyForecast?> fetchDailyForecast(
    double lat,
    double lng,
    DateTime day,
  ) async {
    try {
      final target = DateTime(day.year, day.month, day.day);
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);
      final diff = target.difference(todayDay).inDays;
      if (diff < 0 || diff > 15) return null;

      final dateStr =
          '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';

      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: {
          'latitude': lat.toString(),
          'longitude': lng.toString(),
          'daily':
              'temperature_2m_min,temperature_2m_max,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,weather_code,sunrise,sunset',
          'hourly': 'surface_pressure',
          'start_date': dateStr,
          'end_date': dateStr,
          'timezone': 'auto',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final daily = json['daily'] as Map<String, dynamic>?;
      if (daily == null) return null;

      double? firstDouble(String key) {
        final list = daily[key] as List?;
        if (list == null || list.isEmpty) return null;
        return (list.first as num?)?.toDouble();
      }

      int? firstInt(String key) {
        final list = daily[key] as List?;
        if (list == null || list.isEmpty) return null;
        return (list.first as num?)?.toInt();
      }

      DateTime? firstDate(String key) {
        final list = daily[key] as List?;
        if (list == null || list.isEmpty) return null;
        final raw = list.first as String?;
        if (raw == null) return null;
        return DateTime.tryParse(raw);
      }

      // Mittlerer Luftdruck über den Tag + Tendenz (Ende - Anfang).
      double? pressureMean;
      double? pressureTrend;
      try {
        final hourly = json['hourly'] as Map<String, dynamic>?;
        final pressures = (hourly?['surface_pressure'] as List?)
            ?.map((e) => (e as num?)?.toDouble())
            .whereType<double>()
            .toList();
        if (pressures != null && pressures.isNotEmpty) {
          pressureMean = pressures.reduce((a, b) => a + b) / pressures.length;
          if (pressures.length >= 2) {
            pressureTrend = pressures.last - pressures.first;
          }
        }
      } catch (e) {
        debugPrint('weather pressure parse: $e');
      }

      return DailyForecast(
        date: target,
        tempMinC: firstDouble('temperature_2m_min'),
        tempMaxC: firstDouble('temperature_2m_max'),
        precipitationSumMm: firstDouble('precipitation_sum'),
        precipitationProbabilityMaxPct: firstDouble(
          'precipitation_probability_max',
        ),
        windSpeedMaxKmh: firstDouble('wind_speed_10m_max'),
        windDirectionDominantDeg: firstDouble('wind_direction_10m_dominant'),
        weatherCode: firstInt('weather_code'),
        sunrise: firstDate('sunrise'),
        sunset: firstDate('sunset'),
        pressureHpaMean: pressureMean,
        pressureTrendHpa24h: pressureTrend,
      );
    } catch (_) {
      return null;
    }
  }
}
