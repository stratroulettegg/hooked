// Zufalls-Simulation für den PredatorScoreEngine.
// Läuft 100 Fälle je Art, prüft auf Plausibilitätsprobleme und druckt
// eine Zusammenfassung.
//
// Start:  dart run tool/simulate_predator_scores.dart
//         dart run tool/simulate_predator_scores.dart --seed 42 --cases 100

// ignore_for_file: avoid_print, unused_element_parameter

import 'dart:math';

import 'package:hooked/core/engines/predator_score_engine.dart';

void main(List<String> args) {
  int seed = 42;
  int cases = 100;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--seed') seed = int.parse(args[i + 1]);
    if (args[i] == '--cases') cases = int.parse(args[i + 1]);
  }

  final species = <SpeciesProfile>[
    SpeciesProfiles.hecht,
    SpeciesProfiles.zander,
    SpeciesProfiles.barsch,
    SpeciesProfiles.wels,
    SpeciesProfiles.forelle,
    SpeciesProfiles.huchen,
    SpeciesProfiles.aal,
    SpeciesProfiles.andere,
  ];

  final rng = Random(seed);
  final globalFlags = <String>[];

  for (final sp in species) {
    final results = <_Run>[];
    for (var i = 0; i < cases; i++) {
      results.add(_simulate(sp, rng));
    }
    _report(sp, results, globalFlags);
  }

  print('\n═══════════════════════════════════════════════════════════');
  print('EDGE CASES');
  print('═══════════════════════════════════════════════════════════');
  _runEdgeCases(species, globalFlags);

  print('\n═══════════════════════════════════════════════════════════');
  print('GLOBAL CHECKS  (${globalFlags.length} Auffälligkeiten)');
  print('═══════════════════════════════════════════════════════════');
  if (globalFlags.isEmpty) {
    print('  ✓ keine Plausibilitätsprobleme gefunden');
  } else {
    for (final f in globalFlags) {
      print('  ⚠  $f');
    }
  }
}

class _Run {
  final PredatorScore score;
  final WeatherData weather;
  final DateTime now;
  final WaterBodyType body;
  final WaterClarity clarity;
  final double waterTempC;
  _Run(
    this.score,
    this.weather,
    this.now,
    this.body,
    this.clarity,
    this.waterTempC,
  );
}

_Run _simulate(SpeciesProfile sp, Random rng) {
  // Tageszeit gleichverteilt über 24h
  final hour = rng.nextInt(24);
  final minute = rng.nextInt(60);
  final now = DateTime(2025, 6, 15, hour, minute);

  // Lufttemperatur −5..35 °C
  final airT = -5.0 + rng.nextDouble() * 40.0;
  // Wassertemperatur: meistens leicht gekoppelt an Lufttemp, sonst null
  final waterT = (airT + (rng.nextDouble() * 4 - 2)).clamp(0.0, 32.0);

  // Druck 990..1035 hPa
  final pressure = 990.0 + rng.nextDouble() * 45.0;
  // Drucktendenz −8..+8 hPa
  final tend = -8.0 + rng.nextDouble() * 16.0;

  // Wind 0..50 km/h
  final wind = rng.nextDouble() * 50.0;
  final windDeg = rng.nextDouble() * 360.0;

  // Niederschlag (geometrisch verteilt, meist 0)
  final precip = rng.nextDouble() < 0.6 ? 0.0 : rng.nextDouble() * 30.0;

  // WMO weather codes aus dem gemappten Set
  const codes = [0, 1, 2, 3, 45, 51, 61, 71, 80, 95];
  final code = codes[rng.nextInt(codes.length)];

  final weather = WeatherData(
    airTempC: airT,
    pressureHpa: pressure,
    pressureTendency3hHpa: tend,
    windSpeedKmh: wind,
    windDirectionDeg: windDeg,
    precipitationMm: precip,
    weatherCode: code,
  );

  final body = rng.nextBool() ? WaterBodyType.standing : WaterBodyType.flowing;
  final clarity = WaterClarity.values[rng.nextInt(WaterClarity.values.length)];

  final score = PredatorScoreEngine.calculate(
    weather: weather,
    now: now,
    species: sp,
    waterTempC: waterT,
    waterClarity: clarity,
    waterBodyType: body,
  );

  return _Run(score, weather, now, body, clarity, waterT);
}

void _report(SpeciesProfile sp, List<_Run> runs, List<String> globalFlags) {
  final scores = runs.map((r) => r.score.score).toList()..sort();
  final mean = scores.reduce((a, b) => a + b) / scores.length;
  final minS = scores.first;
  final maxS = scores.last;
  final p25 = scores[(scores.length * 0.25).floor()];
  final p50 = scores[(scores.length * 0.50).floor()];
  final p75 = scores[(scores.length * 0.75).floor()];

  // Faktor-Mittelwerte
  final factors = [
    'circadian',
    'pressure_trend',
    'temperature',
    'clarity',
    'wind',
    'sky',
    'moon',
  ];
  final avg = <String, double>{};
  for (final f in factors) {
    final sum = runs
        .map((r) => r.score.scoreBreakdown[f] ?? 0.0)
        .reduce((a, b) => a + b);
    avg[f] = sum / runs.length;
  }

  print('\n─── ${sp.name} (${runs.length} Fälle) ──────────────────────');
  print(
    '  Score:   min=$minS  p25=$p25  med=$p50  p75=$p75  max=$maxS  '
    'μ=${mean.toStringAsFixed(1)}',
  );
  print('  Faktor-Mittel:');
  for (final f in factors) {
    print('    ${f.padRight(16)} ${avg[f]!.toStringAsFixed(2)}');
  }

  // ── Sanity checks ─────────────────────────────────────────────
  final flags = <String>[];

  // 1. Score immer in [0..100]
  if (minS < 0 || maxS > 100) {
    flags.add('${sp.name}: Score außerhalb [0..100] (min=$minS max=$maxS)');
  }

  // 2. Faktoren müssen in ihren Budgets bleiben
  const budget = {
    'circadian': 30.0,
    'pressure_trend': 18.0,
    'temperature': 25.0,
    'clarity': 12.0,
    'wind': 8.0,
    'sky': 7.0, // tagsüber bis 7
    'moon': 2.0,
  };
  for (final r in runs) {
    for (final f in factors) {
      final v = r.score.scoreBreakdown[f] ?? 0.0;
      if (v < -0.001 || v > budget[f]! + 0.001) {
        flags.add(
          '${sp.name}: $f=${v.toStringAsFixed(2)} außerhalb '
          '[0..${budget[f]}]  '
          '(hour=${r.now.hour}, code=${r.weather.weatherCode})',
        );
        break;
      }
    }
  }

  // 3. Mondwert tagsüber muss 0 sein (06–20 Uhr).
  for (final r in runs) {
    final h = r.now.hour + r.now.minute / 60.0;
    final isNight = h >= 20.0 || h < 6.0;
    final moon = r.score.scoreBreakdown['moon'] ?? 0.0;
    if (!isNight && moon > 0.001) {
      flags.add('${sp.name}: Mond tagsüber >0 (h=$h moon=$moon)');
      break;
    }
  }

  // 4. Sky-Max je nach Tag/Nacht
  for (final r in runs) {
    final h = r.now.hour + r.now.minute / 60.0;
    final isNight = h >= 20.0 || h < 6.0;
    final sky = r.score.scoreBreakdown['sky'] ?? 0.0;
    final cap = isNight ? 5.0 : 7.0;
    if (sky > cap + 0.001) {
      flags.add(
        '${sp.name}: sky=${sky.toStringAsFixed(2)} > '
        '${cap.toStringAsFixed(0)} (night=$isNight)',
      );
      break;
    }
  }

  // 5. Temperaturscore: bei optimaler Wassertemp sollte >=0.9*25 erreichbar
  final optRuns = runs.where(
    (r) => r.waterTempC >= sp.tempOptMin && r.waterTempC <= sp.tempOptMax,
  );
  if (optRuns.isNotEmpty) {
    final bestT = optRuns
        .map((r) => r.score.scoreBreakdown['temperature'] ?? 0.0)
        .reduce(max);
    if (bestT < 22.0) {
      flags.add(
        '${sp.name}: bei tempOpt nie temperature>=22 erreicht '
        '(max=${bestT.toStringAsFixed(1)})',
      );
    }
  }

  // 6. Circadian-Peak in Dämmerungsfenster muss für dämmerungsaktive Arten
  //    höher sein als tagsüber (Grundaktivität = 6).
  final dawnRuns = runs.where((r) => r.now.hour >= 5 && r.now.hour <= 9);
  final dayRuns = runs.where((r) => r.now.hour >= 10 && r.now.hour <= 16);
  if (dawnRuns.isNotEmpty && dayRuns.isNotEmpty && sp.dawnWeight >= 1.2) {
    final dawnMax = dawnRuns
        .map((r) => r.score.scoreBreakdown['circadian'] ?? 0.0)
        .reduce(max);
    final dayMax = dayRuns
        .map((r) => r.score.scoreBreakdown['circadian'] ?? 0.0)
        .reduce(max);
    if (dawnMax <= dayMax) {
      flags.add(
        '${sp.name}: Dämmerung (max=$dawnMax) nicht höher als '
        'Tag (max=$dayMax) trotz dawnWeight=${sp.dawnWeight}',
      );
    }
  }

  // 7. Pressure: starker Abfall sollte schlechteren Score als stabil geben
  //    (bei Arten mit pressureSensitivity >= 0.5)
  if (sp.pressureSensitivity >= 0.5) {
    final falling = runs.where(
      (r) => (r.weather.pressureTendency3hHpa ?? 0) <= -3.0,
    );
    final stable = runs.where(
      (r) => ((r.weather.pressureTendency3hHpa ?? 0).abs()) < 1.0,
    );
    if (falling.isNotEmpty && stable.isNotEmpty) {
      final fMean =
          falling
              .map((r) => r.score.scoreBreakdown['pressure_trend']!)
              .reduce((a, b) => a + b) /
          falling.length;
      final sMean =
          stable
              .map((r) => r.score.scoreBreakdown['pressure_trend']!)
              .reduce((a, b) => a + b) /
          stable.length;
      if (fMean >= sMean) {
        flags.add(
          '${sp.name}: pressure_trend bei Abfall (μ=$fMean) '
          '≥ stabil (μ=$sMean)',
        );
      }
    }
  }

  if (flags.isEmpty) {
    print('  ✓ keine Plausibilitätsprobleme');
  } else {
    print('  ⚠ ${flags.length} Problem(e):');
    for (final f in flags) {
      print('    · $f');
    }
    globalFlags.addAll(flags);
  }
}

// ═══════════════════════════════════════════════════════════════════
// Edge-Case-Suite: deterministische Grenzfälle
// ═══════════════════════════════════════════════════════════════════

class _EdgeCase {
  final String name;
  final WeatherData weather;
  final DateTime now;
  final double? waterTempC;
  final WaterBodyType body;
  final WaterClarity? clarity;
  // Prüfen: Score muss <=expectMax oder >=expectMin bzw. ==0 sein
  final int? expectMax;
  final int? expectMin;
  final String? note;
  const _EdgeCase({
    required this.name,
    required this.weather,
    required this.now,
    required this.body,
    this.waterTempC,
    this.clarity,
    this.expectMax,
    this.expectMin,
    this.note,
  });
}

void _runEdgeCases(List<SpeciesProfile> species, List<String> globalFlags) {
  final june3pm = DateTime(2025, 6, 15, 15, 0);
  final june3am = DateTime(2025, 6, 15, 3, 0);
  final june7pm = DateTime(2025, 6, 15, 19, 0);
  final jan10am = DateTime(2025, 1, 15, 10, 0);

  // Standard-Wetter (neutral, brauchbar)
  const good = WeatherData(
    airTempC: 16,
    pressureHpa: 1015,
    pressureTendency3hHpa: 0.0,
    windSpeedKmh: 10,
    windDirectionDeg: 180,
    precipitationMm: 0,
    weatherCode: 2,
  );

  final cases = <_EdgeCase>[
    _EdgeCase(
      name: 'Eis (Wasser 0 °C, Januar 10 Uhr)',
      weather: WeatherData(
        airTempC: -5,
        pressureHpa: 1025,
        pressureTendency3hHpa: 1.0,
        windSpeedKmh: 5,
        windDirectionDeg: 0,
        precipitationMm: 0,
        weatherCode: 3,
      ),
      now: jan10am,
      body: WaterBodyType.standing,
      waterTempC: 0.0,
      expectMax: 10,
      note: 'Wasser gefroren → Fang praktisch unmöglich',
    ),
    _EdgeCase(
      name: 'Knapp über Eis (Wasser 1.0 °C)',
      weather: good,
      now: jan10am,
      body: WaterBodyType.standing,
      waterTempC: 1.0,
      expectMax: 10,
      note: 'An der Eisgrenze',
    ),
    _EdgeCase(
      name: 'Hitzekollaps (35 °C, Flaute, Stillgewässer)',
      weather: WeatherData(
        airTempC: 35,
        pressureHpa: 1012,
        pressureTendency3hHpa: 0.0,
        windSpeedKmh: 1,
        windDirectionDeg: 0,
        precipitationMm: 0,
        weatherCode: 0,
      ),
      now: june3pm,
      body: WaterBodyType.standing,
      waterTempC: 30.0,
      expectMax: 25,
      note: 'Sauerstoffmangel + Hitzestress (Wels toleriert 30 °C → ~20)',
    ),
    _EdgeCase(
      name: 'Gewitter mittags',
      weather: WeatherData(
        airTempC: 20,
        pressureHpa: 1000,
        pressureTendency3hHpa: -5.0,
        windSpeedKmh: 25,
        windDirectionDeg: 270,
        precipitationMm: 15,
        weatherCode: 95,
      ),
      now: june3pm,
      body: WaterBodyType.standing,
      waterTempC: 18.0,
      expectMax: 60,
      note: 'Druckabfall + Gewitter: schlechte Sky-Punkte, aber kein Null',
    ),
    _EdgeCase(
      name: 'Optimale Abenddämmerung',
      weather: WeatherData(
        airTempC: 18,
        pressureHpa: 1018,
        pressureTendency3hHpa: 2.5,
        windSpeedKmh: 8,
        windDirectionDeg: 180,
        precipitationMm: 0,
        weatherCode: 2,
      ),
      now: june7pm,
      body: WaterBodyType.standing,
      waterTempC: 17.0,
      expectMin: 55,
      note: 'Alle Faktoren grün (Huchen knapp wg. Kaltwasser-Präferenz)',
    ),
    _EdgeCase(
      name: 'Null-Daten (alles null)',
      weather: const WeatherData(),
      now: june3pm,
      body: WaterBodyType.standing,
      note: 'Engine darf nicht crashen, Score in [0..100]',
    ),
    _EdgeCase(
      name: 'Extremer Sturm (80 km/h)',
      weather: WeatherData(
        airTempC: 14,
        pressureHpa: 995,
        pressureTendency3hHpa: -6.0,
        windSpeedKmh: 80,
        windDirectionDeg: 270,
        precipitationMm: 20,
        weatherCode: 82,
      ),
      now: june3pm,
      body: WaterBodyType.standing,
      waterTempC: 14.0,
      note: 'Orkan, sicherheitskritisch',
    ),
    _EdgeCase(
      name: 'Tiefe Nacht klar (3 Uhr, Vollmond-Fenster)',
      weather: WeatherData(
        airTempC: 16,
        pressureHpa: 1018,
        pressureTendency3hHpa: 0.5,
        windSpeedKmh: 5,
        windDirectionDeg: 0,
        precipitationMm: 0,
        weatherCode: 0,
      ),
      now: june3am,
      body: WaterBodyType.standing,
      waterTempC: 16.0,
      note: 'Nacht → Mond kann Punkte beisteuern',
    ),
    _EdgeCase(
      name: 'Hitze + Wind (Stillgewässer sollte Multiplikator bekommen)',
      weather: WeatherData(
        airTempC: 28,
        pressureHpa: 1010,
        pressureTendency3hHpa: 0.0,
        windSpeedKmh: 15,
        windDirectionDeg: 90,
        precipitationMm: 0,
        weatherCode: 1,
      ),
      now: june3pm,
      body: WaterBodyType.standing,
      waterTempC: 24.0,
      note: 'Wind bricht Schichtung — Score nicht zusätzlich gedeckelt',
    ),
  ];

  for (final ec in cases) {
    print('\n▸ ${ec.name}');
    if (ec.note != null) print('  (${ec.note})');
    for (final sp in species) {
      final r = PredatorScoreEngine.calculate(
        weather: ec.weather,
        now: ec.now,
        species: sp,
        waterTempC: ec.waterTempC,
        waterClarity: ec.clarity,
        waterBodyType: ec.body,
      );
      final score = r.score;
      final tag = <String>[];
      if (score < 0 || score > 100) tag.add('OUT-OF-RANGE');
      if (ec.expectMax != null && score > ec.expectMax!) {
        tag.add('>max(${ec.expectMax})');
      }
      if (ec.expectMin != null && score < ec.expectMin!) {
        tag.add('<min(${ec.expectMin})');
      }
      final mark = tag.isEmpty ? '✓' : '⚠';
      print(
        '    $mark ${sp.name.padRight(8)} '
        '→ $score  ${tag.isEmpty ? '' : '  [${tag.join(", ")}]'}',
      );
      if (tag.isNotEmpty) {
        globalFlags.add(
          '${ec.name} / ${sp.name}: score=$score '
          '${tag.join(", ")}',
        );
      }
    }
  }
}
