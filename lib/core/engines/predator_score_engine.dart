import 'dart:math';

import 'package:flutter/material.dart' show IconData;

import '../format/app_formats.dart';

/// Berechnet Solunar-Peaks (Major/Minor) basierend auf Mondstand.
/// Vereinfachte Formel: Mondtransit ± 1h = Major, Auf/Untergag = Minor
class SolunarEngine {
  /// Gibt eine Liste von Peak-Zeitfenstern für den angegebenen Tag zurück.
  static List<SolunarPeak> peaksForDay(DateTime date) {
    final julianDay = _toJulianDay(date);
    final moonTransit = _moonTransit(julianDay);

    final dateBase = DateTime(date.year, date.month, date.day);

    // Major Peaks: Mondtransit ± 12h
    final major1 = dateBase.add(
      Duration(
        hours: moonTransit.round(),
        minutes: ((moonTransit - moonTransit.floorToDouble()) * 60).round(),
      ),
    );
    final major2 = major1.subtract(const Duration(hours: 12));

    // Minor Peaks: ~6h versetzt
    final minor1 = major1.subtract(const Duration(hours: 6));
    final minor2 = major1.add(const Duration(hours: 6));

    return [
      SolunarPeak(time: major1, isMajor: true, durationMin: 90),
      SolunarPeak(time: major2, isMajor: true, durationMin: 90),
      SolunarPeak(time: minor1, isMajor: false, durationMin: 45),
      SolunarPeak(time: minor2, isMajor: false, durationMin: 45),
    ]..sort((a, b) => a.time.compareTo(b.time));
  }

  /// Moonphase 0..1 (0=Neumond, 0.5=Vollmond)
  static double moonPhase(DateTime date) {
    final jd = _toJulianDay(date);
    final cycle = (jd - 2451550.1) / 29.530588853;
    return cycle - cycle.floorToDouble();
  }

  /// Mondphasen-Label
  static String moonPhaseLabel(DateTime date) {
    final phase = moonPhase(date);
    if (phase < 0.03 || phase > 0.97) return 'Neumond';
    if (phase < 0.22) return 'Zunehmend (Sichel)';
    if (phase < 0.28) return 'Erstes Viertel';
    if (phase < 0.47) return 'Zunehmend (Gibbous)';
    if (phase < 0.53) return 'Vollmond';
    if (phase < 0.72) return 'Abnehmend (Gibbous)';
    if (phase < 0.78) return 'Letztes Viertel';
    return 'Abnehmend (Sichel)';
  }

  static double _toJulianDay(DateTime date) {
    final a = (14 - date.month) ~/ 12;
    final y = date.year + 4800 - a;
    final m = date.month + 12 * a - 3;
    return date.day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045.toDouble();
  }

  static double _moonTransit(double jd) {
    // Vereinfachte Mondtransit-Zeit in Stunden (0–24)
    final l0 = (218.316 + 13.176396 * (jd - 2451545.0)) % 360;
    final transit = (l0 / 15.0) % 24;
    return transit;
  }
}

class SolunarPeak {
  final DateTime time;
  final bool isMajor;
  final int durationMin;

  const SolunarPeak({
    required this.time,
    required this.isMajor,
    required this.durationMin,
  });
}

/// Gewässertyp nach Hydrologie. Beeinflusst Sauerstoffhaushalt:
/// - Fließgewässer: kontinuierliche Durchmischung, stabiler O₂-Gehalt
/// - Stillgewässer: Sauerstoff abhängig von Wind/Temperatur (Schichtung)
enum WaterBodyType {
  standing, // Stehendes Gewässer (See, Teich, Weiher)
  flowing, // Fließgewässer (Fluss, Bach, Strom)
}

extension WaterBodyTypeExtension on WaterBodyType {
  String get label {
    switch (this) {
      case WaterBodyType.standing:
        return 'Stehend';
      case WaterBodyType.flowing:
        return 'Fließend';
    }
  }

  String get hint {
    switch (this) {
      case WaterBodyType.standing:
        return 'See, Teich';
      case WaterBodyType.flowing:
        return 'Fluss, Bach';
    }
  }
}

/// 4-stufige Gewässertrübung nach limnologischer Klassifikation
/// Grundlage: OECD (1982) Trophiestufensystem, Secchi-Tiefe nach Carlson (1977)
enum WaterClarity {
  oligotroph, // Sehr klar: Sichttiefe >4m, <1 NTU
  mesotroph, // Klar: Sichttiefe 2–4m
  eutroph, // Trüb: Sichttiefe <2m, ≥5 NTU
  hypertroph, // Sehr trüb: Sichttiefe <0.5m, Algenblüte
}

extension WaterClarityExtension on WaterClarity {
  /// Normierter Trübungsindex 0.0 (klar) … 1.0 (undurchsichtig)
  double get turbidity {
    switch (this) {
      case WaterClarity.oligotroph:
        return 0.05;
      case WaterClarity.mesotroph:
        return 0.30;
      case WaterClarity.eutroph:
        return 0.70;
      case WaterClarity.hypertroph:
        return 0.95;
    }
  }

  String get label {
    switch (this) {
      case WaterClarity.oligotroph:
        return 'Sehr klar';
      case WaterClarity.mesotroph:
        return 'Klar';
      case WaterClarity.eutroph:
        return 'Trüb';
      case WaterClarity.hypertroph:
        return 'Sehr trüb';
    }
  }

  String get depthLabel {
    switch (this) {
      case WaterClarity.oligotroph:
        return '>4m';
      case WaterClarity.mesotroph:
        return '2–4m';
      case WaterClarity.eutroph:
        return '<2m';
      case WaterClarity.hypertroph:
        return '<0.5m';
    }
  }
}

/// Artspezifisches Scoring-Profil
///
/// Quellenangaben je Art:
///   Hecht:   Casselman & Lewis 1996, Raat 1988
///   Zander:  Lehtonen 1992, Lappalainen et al. 2001
///   Barsch:  Gliwicz & Rykowska 1992, Persson 1986
///   Wels:    Copp & Vilizzi 2004, Alp et al. 2008
///   Forelle: Elliott 1981, EIFAC 1969, Jonsson & Jonsson 2011
///   Huchen:  Marconato et al. 1993, Holčík et al. 1988
///   Aal:     Deelder 1984, Tesch 2003
class SpeciesProfile {
  const SpeciesProfile({
    required this.name,
    required this.tempOptMin,
    required this.tempOptMax,
    required this.tempOkMin,
    required this.tempOkMax,
    required this.dawnWeight, // 0..2 — circadiane Morgenaktivität
    required this.duskWeight, // 0..2 — circadiane Abendaktivität
    required this.nightWeight, // 0..2 — circadiane Nachtaktivität
    required this.pressureSensitivity, // 0..1 — Reaktion auf Druckänderungen
    required this.turbidityTolerance, // 0..1 — 0=klares Wasser nötig, 1=Trübe toleriert
    required this.windMax, // km/h — Windgrenze für guten Score
    this.hint = '',
  });

  final String name;
  final double tempOptMin; // Optimaler Temperaturbereich (volle Punkte)
  final double tempOptMax;
  final double tempOkMin; // Tolerierter Bereich (reduzierte Punkte)
  final double tempOkMax;
  final double dawnWeight;
  final double duskWeight;
  final double nightWeight;
  final double pressureSensitivity;
  final double turbidityTolerance;
  final double windMax;
  final String hint;
}

/// Artprofile basierend auf Freilandstudien und Aquakulturliteratur
class SpeciesProfiles {
  // Hecht (Esox lucius): crepuskulärer Lauerjäger, Kaltwasser, Barorezeptor-sensitiv
  // pressureSensitivity korrigiert: 0.8→0.6 (physostome Schwimmblase, Collins et al. 1998: pike reagieren auf Druck, aber weniger als Percidae)
  // turbidityTolerance korrigiert: 0.4→0.5 (Nahkampf-Laterallinie, aktiv auch in trüben Poldergewässern, Raat 1988)
  // dawnWeight korrigiert: 1.8→1.4 (bei Kälte <8°C verschiebt sich Aktivität Richtung Mittag; Casselman & Lewis 1996;
  //   tempMultiplier dämpft zusätzlich bei <tempOkMin)
  static const hecht = SpeciesProfile(
    name: 'Hecht',
    tempOptMin: 8,
    tempOptMax: 18,
    tempOkMin: 4,
    tempOkMax: 22,
    dawnWeight: 1.4,
    duskWeight: 2.0,
    nightWeight: 0.5,
    pressureSensitivity: 0.6,
    turbidityTolerance: 0.5,
    windMax: 20,
    hint: 'Dämmerungspredator · 8–18 °C · reagiert auf Druckabfall',
  );

  // Zander (Sander lucioperca): Nacht & Dämmerung, Tapetum lucidum
  // tempOptMax korrigiert: 20→22 (Lyach & Čech 2018, Fisheries Research: Fangrate-Peak bis 22 °C)
  // pressureSensitivity korrigiert: 0.7→0.85 (physoclist = geschlossene Schwimmblase, träge Kompensation → höchste Druckreaktion; Nishi et al. 2005, Lappalainen et al. 2001)
  // turbidityTolerance korrigiert: 0.6→0.85 (Tapetum lucidum: optimaler Jagdvorteil in trübem Wasser; Lehtonen 1992, Pinder & Gozlan 2003)
  // windMax korrigiert: 25→30 (Wind erzeugt Trübung → partieller Vorteil für Tapetum-Jäger;
  //   Wind-Abzug wird durch Trübungs-Bonus im clarity-Score teilweise kompensiert)
  static const zander = SpeciesProfile(
    name: 'Zander',
    tempOptMin: 12,
    tempOptMax: 22,
    tempOkMin: 6,
    tempOkMax: 24,
    dawnWeight: 1.5,
    duskWeight: 2.0,
    nightWeight: 1.8,
    pressureSensitivity: 0.85,
    turbidityTolerance: 0.85,
    windMax: 30,
    hint: 'Nacht- & Dämmerungsräuber · Tapetum lucidum · 12–22 °C',
  );

  // Barsch (Perca fluviatilis): diurnal, Schwarmjäger, klares Wasser
  // pressureSensitivity korrigiert: 0.7→0.80 (physoclist = geschlossene Schwimmblase; Nishi et al. 2005: Percidae zeigen starke Verhaltensänderungen bei Druckabfall)
  // windMax korrigiert: 30→25 (visueller Schwarmjäger; Wellengang stört Beutekohärenz, Gliwicz & Rykowska 1992)
  // nightWeight korrigiert: 0.3→0.1 (reine Augentiere ohne Tapetum lucidum; stellen Jagd bei Dunkelheit fast vollständig ein, Persson 1986)
  static const barsch = SpeciesProfile(
    name: 'Barsch',
    tempOptMin: 14,
    tempOptMax: 22,
    tempOkMin: 8,
    tempOkMax: 26,
    dawnWeight: 1.8,
    duskWeight: 1.4,
    nightWeight: 0.1,
    pressureSensitivity: 0.80,
    turbidityTolerance: 0.3,
    windMax: 25,
    hint: 'Tagaktiv · klares Wasser bevorzugt · 14–22 °C',
  );

  // Wels (Silurus glanis): nachtaktiv, warm, druckunempfindlich, Trübe vorteilhaft
  // tempOptMin korrigiert: 16→18 (Copp & Vilizzi 2004: Fressoptimum 18–28 °C)
  // tempOkMin korrigiert: 12→10 (Wels in Praxis ab ~10 °C fangbar; Alp et al. 2008: Aktivität ab 10 °C nachgewiesen)
  static const wels = SpeciesProfile(
    name: 'Wels',
    tempOptMin: 18,
    tempOptMax: 26,
    tempOkMin: 10,
    tempOkMax: 30,
    dawnWeight: 0.8,
    duskWeight: 1.6,
    nightWeight: 2.0,
    pressureSensitivity: 0.3,
    turbidityTolerance: 0.9,
    windMax: 40,
    hint:
        'Nachtaktiv · ab 10 °C aktiv · Fressoptimum 18–26 °C · kaum druckempfindlich',
  );

  // Forelle (Salmo trutta): Kaltwasser, morgenaktiv, sehr druckempfindlich
  // tempOkMax korrigiert: 20→18 (Elliott 1994: Stressreaktion ab 18,6 °C, Fressaktivität sinkt >18 °C)
  // pressureSensitivity korrigiert: 1.0→0.85 (physostome Schwimmblase = schnellere Gasregulation; hohe Verhaltenssensitivität empirisch belegt, aber physiologisch nicht Maximum; Elliott 1994)
  static const forelle = SpeciesProfile(
    name: 'Forelle',
    tempOptMin: 8,
    tempOptMax: 16,
    tempOkMin: 4,
    tempOkMax: 18,
    dawnWeight: 2.0,
    duskWeight: 1.6,
    nightWeight: 0.3,
    pressureSensitivity: 0.85,
    turbidityTolerance: 0.1,
    windMax: 15,
    hint:
        'Kaltwasserspezialist · 8–16 °C · Stressgrenze 18 °C · stark druckempfindlich',
  );

  // Huchen (Hucho hucho): Fließgewässer, Kaltwasser, druckempfindlich
  // pressureSensitivity korrigiert: 0.9→0.75 (physostomer Salmonide = schnellere Druckausgleich; Holčík et al. 1988: hohe Verhaltenssensitivität in alpinen Systemen, aber physostom)
  static const huchen = SpeciesProfile(
    name: 'Huchen',
    tempOptMin: 6,
    tempOptMax: 14,
    tempOkMin: 2,
    tempOkMax: 18,
    dawnWeight: 1.8,
    duskWeight: 1.5,
    nightWeight: 0.6,
    pressureSensitivity: 0.75,
    turbidityTolerance: 0.2,
    windMax: 20,
    hint: 'Alpiner Großsalmonide · 6–14 °C · Hochdruck + Kälte ideal',
  );

  // Aal (Anguilla anguilla): nachtaktiv, bentisch, druckunempfindlich
  // tempOptMin korrigiert: 16→14 (Tesch 2003: aktive Nahrungsaufnahme ab 12–14 °C, Optimal >18 °C)
  static const aal = SpeciesProfile(
    name: 'Aal',
    tempOptMin: 14,
    tempOptMax: 24,
    tempOkMin: 10,
    tempOkMax: 28,
    dawnWeight: 0.5,
    duskWeight: 1.3,
    nightWeight: 2.0,
    pressureSensitivity: 0.2,
    turbidityTolerance: 0.8,
    windMax: 40,
    hint: 'Klassischer Nachtfisch · 14–24 °C · kaum druckabhängig',
  );

  static const andere = SpeciesProfile(
    name: 'Andere',
    tempOptMin: 10,
    tempOptMax: 20,
    tempOkMin: 5,
    tempOkMax: 25,
    dawnWeight: 1.4,
    duskWeight: 1.4,
    nightWeight: 0.8,
    pressureSensitivity: 0.6,
    turbidityTolerance: 0.4,
    windMax: 30,
    hint: '',
  );
}

/// Predator-Index-Engine — wissenschaftlich fundiertes Scoring-Modell
///
/// SCORING-FAKTOREN UND QUELLENANGABEN:
///
/// 1. TAGESRHYTHMUS (max 30 Pkt.)
///    Circadiane Aktivitätsmuster durch Radiotelemetrie-Studien vielfach belegt.
///    Quelle: Lucas & Baras (2001) "Migration of Freshwater Fishes";
///    Schulz et al. (2003) "Diel activity patterns in juvenile burbot"
///
/// 2. LUFTDRUCKTENDENZ (max 18 Pkt.)
///    Fische haben Schwimmblasen als Barorezeptoren und reagieren auf
///    ÄNDERUNGEN des Luftdrucks, nicht auf absolute Werte.
///    Sinkt der Druck → Frontenannäherung → Stressreaktion → weniger Aktivität.
///    Steigt der Druck → Schönwetter → erhöhte Aktivität.
///    Quelle: Collins et al. (1998); Schreer et al. (2004); Klimley et al. (2001)
///    Schwellwerte: ±1 hPa/3h stabil, ±3 hPa/3h klare Tendenz.
///
/// 3. TEMPERATUR (max 25 Pkt.)
///    Artspezifische Thermaloptima und Toleranzbereiche gut dokumentiert.
///    Quelle: Elliott (1981) "Freshwater fish temperature";
///    Alabaster & Lloyd (1980) "Water quality criteria for freshwater fish"
///
/// 4. SICHTTIEFE / TRÜBUNG (max 12 Pkt.)
///    Artspezifisch optimale Trübung: optTurb = turbidityTolerance × 0.7
///    Score = 12 × max(0, 1 − 1.5 × |turbidity − optTurb|)
///    Hecht (optTurb=0.35): Klar=11.4, Sehr trüb=4.8 → Spread ~7 Pkt.
///    Forelle (optTurb=0.07): Sehr klar=11.6, Sehr trüb=0 → Spread ~12 Pkt.
///    Auto-Fallback: Niederschlag als Trübstoffeintrag-Proxy (ohne Wind).
///    Quelle: Carlson (1977) Secchi-Trophiestufen; OECD (1982)
///
/// 5. WIND (max 8 Pkt.)
///    Windstärke gegen artspezifisches windMax-Limit.
///    Effekte: Druckwellen, Uferüberströmung, Sauerstoffverteilung, Beutekohärenz.
///    Quelle: Gliwicz & Rykowska (1992); Barber & Sherrat (1997)
///
/// 6. HIMMELSBILD / BEWÖLKUNG (max 5 / 7 Pkt.)
///    Bewölkung reguliert UV-Eintrag und Lichtintensität am Gewässergrund.
///    Räuber sind bei mäßiger Bewölkung mutiger (weniger Schatten-Kontraste),
///    "Bluebird"-Hochdrucktage mit praller Sonne zeigen empirisch schwächere
///    Fangraten. Aktives Gewitter ist stark kontraproduktiv (Sicherheit +
///    Fisch zieht in Tiefe / Struktur).
///    TAGSÜBER wird das Maximum auf 7 Pkt. angehoben, weil die Mondphase
///    dann keine Rolle spielt und diese 2 Pkt. auf das Himmelsbild umgelegt
///    werden — so bleiben stets 100 Pkt. erreichbar.
///    Quelle: Helfman (1981) "Twilight activities and temporal structure";
///            Reebs (2002) "Plasticity of diel and circadian activity"
///
/// 7. MONDPHASE (max 2 Pkt., NUR NACHTS)
///    Metaanalysen zeigen KEINEN reproduzierbaren Effekt bei Süßwasserfischen.
///    Tagsüber irrelevant → 0 Pkt.
///    Nachts bekommt Voll-/Neumond den vollen Bonus, Viertelmonde keinen
///    (Mondlicht bzw. Solunar-Tradition), ohne den Score zu dominieren.
///    Quelle: Yeh et al. (2020) "Evidence against the lunar effect on fish"
class PredatorScoreEngine {
  static PredatorScore calculate({
    required WeatherData weather,
    required DateTime now,
    SpeciesProfile? species,
    double?
    waterTempC, // Manuelle Wassertemperatur (überschreibt Lufttemp-Proxy)
    WaterClarity?
    waterClarity, // Manuelle Sichttiefe (überschreibt windbasierte Schätzung)
    WaterBodyType?
    waterBodyType, // Stehend/Fließend (beeinflusst Sauerstoff-Modell)
  }) {
    final sp = species ?? SpeciesProfiles.andere;
    final scores = <String, double>{};

    // ── 1. Tagesrhythmus / Circadiane Aktivität (max 30 Pkt.) ──────────────
    final hour = now.hour + now.minute / 60.0;
    double circadian;
    if (hour >= 5.0 && hour <= 9.5) {
      // Morgendämmerung: Gaußsche Kurve um 07:00
      circadian = 30 * _bellCurve(hour, 7.0, 1.2) * sp.dawnWeight;
    } else if (hour >= 17.0 && hour <= 22.0) {
      // Abenddämmerung: Gaußsche Kurve um 19:30
      circadian = 30 * _bellCurve(hour, 19.5, 1.4) * sp.duskWeight;
    } else if (hour >= 22.5 || hour <= 4.5) {
      // Nacht: flacher constanter Score
      circadian = 18 * sp.nightWeight;
    } else {
      // Tagzeit: Grundaktivität
      circadian = 6;
    }
    scores['circadian'] = circadian.clamp(0, 30);

    // ── 2. Luftdrucktendenz (max 18 Pkt.) ──────────────────────────────────
    // Delta = Druckänderung der letzten 3 Stunden (hPa)
    // Positiv = steigend (Post-Front), Negativ = fallend (Frontenannäherung)
    double pressureScore = 9; // Neutralwert ohne Datenlage
    final tendency = weather.pressureTendency3hHpa;
    if (tendency != null) {
      double base;
      if (tendency > 3.0) {
        base = 18;
      } // Stark steigend: Post-Front
      else if (tendency > 1.0) {
        base = 15;
      } // Schwach steigend: gut
      else if (tendency >= -1.0) {
        base = 10;
      } // Stabil: neutral
      else if (tendency >= -3.0) {
        base = 5;
      } // Fallend: Frontannäherung
      else {
        base = 2;
      } // Stark fallend: schlecht
      // Druckunempfindliche Arten weichen weniger vom Neutralwert ab
      pressureScore = 9 + (base - 9) * sp.pressureSensitivity;
    }
    scores['pressure_trend'] = pressureScore.clamp(0, 18);

    // ── 3. Wassertemperatur (max 25 Pkt.) ───────────────────────────────────
    // Lufttemperatur als Proxy (Gewässertemp. schwankt langsamer, kein direkter Sensor)
    double tempScore = 8; // Neutralwert ohne Daten
    // waterTempC (manuell) hat Vorrang vor Lufttemperatur-Proxy
    final effectiveTemp = waterTempC ?? weather.airTempC;

    // tempMultiplier: Temperatur wirkt als Multiplikator auf alle Verhaltensfaktoren.
    // Bei physiologischer Torpor (außerhalb Toleranz) sind Tagesrhythmus und
    // Druck weitgehend irrelevant — der Fisch ist inaktiv.
    //   Optimal    → 1.0 (volle Wirkung)
    //   Toleranzrand → 0.5 (halbierte Wirkung)
    //   Außerhalb  → 0.15 (Torpor — kaum noch zu fangen)
    //   Eis (≤1°C) → 0.02 (Wasser gefriert, Stoffwechsel nahe 0,
    //                 Stillgewässer ggf. zu)
    //   Kein Wert  → 0.85 (leichte Unsicherheitsdämpfung)
    double tempMultiplier;
    if (effectiveTemp == null) {
      tempMultiplier = 0.85;
    } else {
      final t = effectiveTemp;
      if (t <= 1.0) {
        // Eisgrenze: Süßwasser gefriert, kein sinnvoller Fang möglich.
        tempScore = 0;
        tempMultiplier = 0.02;
      } else if (t >= sp.tempOptMin && t <= sp.tempOptMax) {
        tempMultiplier = 1.0;
        tempScore = 25;
      } else if (t >= sp.tempOkMin && t <= sp.tempOkMax) {
        final distLow = (t < sp.tempOptMin)
            ? (t - sp.tempOkMin) / (sp.tempOptMin - sp.tempOkMin)
            : 1.0;
        final distHigh = (t > sp.tempOptMax)
            ? (sp.tempOkMax - t) / (sp.tempOkMax - sp.tempOptMax)
            : 1.0;
        final dist = min(distLow, distHigh);
        tempScore = 10 + 15 * dist;
        tempMultiplier = 0.5 + 0.5 * dist; // 0.5 am Rand → 1.0 am Optimum
      } else {
        tempScore = 0; // Keine Punkte — physiologisch inaktiv
        tempMultiplier = 0.15;
      }
    }
    scores['temperature'] = tempScore.clamp(0, 25);

    // ── 4. Sichttiefe / Trübung (max 12 Pkt.) ───────────────────────────────
    // optTurbidity = artspezifische "Lieblingleistrübung"
    // Forelle (0.07) → mag glasklares Wasser
    // Hecht (0.35)   → leichte Trübe ideal (Hinterhalt)
    // Wels (0.63)    → mag trübes Wasser
    // Score dreht sich symmetrisch um dieses Optimum.
    double turbidity;
    if (waterClarity != null) {
      turbidity = waterClarity.turbidity;
    } else {
      // Niederschlag als Trübstoffeintrag-Proxy (Carlson 1977)
      final precip = weather.precipitationMm ?? 0.0;
      if (precip > 20) {
        turbidity = 0.95;
      } // Hypertroph
      else if (precip > 5) {
        turbidity = 0.70;
      } // Eutroph
      else if (precip > 1) {
        turbidity = 0.30;
      } // Mesotroph
      else {
        turbidity = 0.05;
      } // Oligotroph (kein Regen)
    }
    final optTurbidity = sp.turbidityTolerance * 0.7;
    scores['clarity'] =
        (12.0 * max(0.0, 1.0 - 1.5 * (turbidity - optTurbidity).abs())).clamp(
          0,
          12,
        );

    // ── 5. Wind (max 8 Pkt.) ─────────────────────────────────────────────────
    // Windstärke vs. artspezifisches windMax (Druckwellen, Beutekohäsion, Sauerstoff)
    double windScore = 5.0; // Neutralwert ohne Daten
    if (weather.windSpeedKmh != null) {
      final w = weather.windSpeedKmh!;
      if (w <= sp.windMax * 0.4) {
        windScore = 8.0;
      } // Leichter Wind: ideal
      else if (w <= sp.windMax * 0.7) {
        windScore = 6.0;
      } // Mäßiger Wind: gut
      else if (w <= sp.windMax) {
        windScore = 4.0;
      } // Starker Wind: grenzwertig
      else {
        windScore = 1.0;
      } // Über Limit: schlecht
    }
    scores['wind'] = windScore;

    // ── Gewässertyp-Modifikator (Sauerstoffhaushalt) ─────────────────────────
    // Fließgewässer: Turbulenz sorgt für konstante O₂-Sättigung — Wind weniger
    //   relevant, Trübung nach Regen stärker (Feinsedimenteintrag).
    // Stillgewässer: Bei Hitze + Windstille entsteht thermische Schichtung mit
    //   O₂-Defizit in tieferen Zonen → Aktivitätsdämpfung.
    //   Quelle: Wetzel (2001) Limnology, Kap. 9 (Oxygen Dynamics)
    if (waterBodyType == WaterBodyType.flowing) {
      // Fließgewässer: Wind ist weitgehend egal → Score-Boden anheben
      scores['wind'] = max(scores['wind']!, 6.0);
    }

    // ── 6. Himmelsbild / Bewölkung (max 5 nachts, 7 tagsüber) ───────────────
    // Auswertung des WMO-Weather-Codes (Open-Meteo-Konvention).
    // "Bluebird"-Tage mit voll Sonne bringen 2 Pkt., leichte bis mäßige
    // Bewölkung 5 Pkt. (Optimum), aktives Gewitter nur 1 Pkt.
    // Tag/Nacht-Heuristik: 20:00–06:00 = Nacht. Tagsüber wird der Mond-Slot
    // (2 Pkt.) auf das Himmelsbild umgelegt → Maximum 7 Pkt.
    final isNight = hour >= 20.0 || hour < 6.0;
    double skyScore = 3.0; // Neutralwert ohne Daten
    final code = weather.weatherCode;
    if (code != null) {
      if (code == 0) {
        skyScore = 2.0;
      } // Klar (Bluebird)
      else if (code == 1) {
        skyScore = 3.5;
      } // Heiter
      else if (code == 2) {
        skyScore = 5.0;
      } // Leicht bewölkt – Optimum
      else if (code == 3) {
        skyScore = 4.0;
      } // Bedeckt
      else if (code >= 45 && code <= 49) {
        skyScore = 3.0;
      } // Nebel
      else if (code >= 51 && code <= 67) {
        skyScore = 4.0;
      } // Niesel/Regen
      else if (code >= 71 && code <= 77) {
        skyScore = 2.0;
      } // Schnee
      else if (code >= 80 && code <= 82) {
        skyScore = 4.0;
      } // Regenschauer
      else if (code >= 95 && code <= 99) {
        skyScore = 1.0;
      } // Gewitter
    }
    // Sichtjäger-Bonus bewusst NICHT pauschal angewandt: Wels/Aal orientieren
    // sich chemo-/mechanorezeptiv (Barteln, Seitenlinie), Zander nutzt sein
    // Tapetum lucidum gerade bei Trübe/Bedeckung und ist bei hellem Vollmond
    // eher schwerer zu fangen. Eine artübergreifende Mondlicht-Regel ist
    // daher nicht sauber abbildbar – wir bleiben bei den WMO-Code-Punkten.
    if (!isNight) {
      // Tagsüber: Maximum 7 Pkt. (Mond-Slot wird umgelegt)
      skyScore = skyScore * 1.4;
    }
    scores['sky'] = skyScore.clamp(0, isNight ? 5 : 7).toDouble();

    // ── 7. Mondphase (max 2 Pkt., nur nachts) ────────────────────────────────
    // Sehr schwaches Gewicht (Evidenz dünn): Tagsüber irrelevant (= 0).
    // Nachts erhalten Voll- und Neumond den vollen Bonus, Viertelmonde keinen.
    double moonScore = 0.0;
    if (isNight) {
      final phase = SolunarEngine.moonPhase(now);
      // Distanz zur nächsten "runden" Phase (0 = Neumond, 0.5 = Vollmond).
      final distToKey = min(
        (phase - 0.0).abs(),
        min((phase - 0.5).abs(), (phase - 1.0).abs()),
      );
      // 0.0 → voll (2 Pkt.), 0.25 → null.
      moonScore = (2.0 * max(0.0, 1.0 - distToKey * 4.0))
          .clamp(0, 2)
          .toDouble();
    }
    scores['moon'] = moonScore;
    // Mondphase-Label weiterhin berechnen (für Anzeige).
    final phase = SolunarEngine.moonPhase(now);

    // Stillgewässer: Hitze + Flaute → Sauerstoffmangel → Verhaltensdämpfung
    if (waterBodyType == WaterBodyType.standing) {
      final w = weather.windSpeedKmh ?? 10.0;
      final t = effectiveTemp ?? 15.0;
      if (t > 22 && w < 5) {
        tempMultiplier *= 0.85;
      }
    }

    // Verhaltensfaktoren (Rhythmus, Druck, Sicht, Wind, Himmelsbild) werden
    // durch tempMultiplier skaliert — bei Torpor sind diese faktisch wertlos.
    // Mond ist astronomisch und wird nicht mit tempMultiplier gedämpft.
    final behavioralScore =
        (scores['circadian']! +
            scores['pressure_trend']! +
            scores['clarity']! +
            scores['wind']! +
            scores['sky']!) *
        tempMultiplier;
    final total = (behavioralScore + scores['temperature']! + scores['moon']!)
        .clamp(0, 100);

    return PredatorScore(
      score: total.round(),
      moonPhase: phase,
      moonPhaseLabel: SolunarEngine.moonPhaseLabel(now),
      nextPeak: _nextActivityWindow(sp, now),
      scoreBreakdown: scores,
      weather: weather,
      speciesProfile: sp,
    );
  }

  /// Nächstes circadianes Aktivitätsfenster basierend auf Artprofil.
  /// Wissenschaftlich fundiert durch Radiotelemetrie-Studien (Lucas & Baras 2001).
  static SolunarPeak? _nextActivityWindow(SpeciesProfile sp, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final candidates = <SolunarPeak>[];

    for (var d = 0; d <= 1; d++) {
      final base = today.add(Duration(days: d));
      if (sp.dawnWeight >= 1.3) {
        candidates.add(
          SolunarPeak(
            time: base.add(const Duration(hours: 6, minutes: 30)),
            isMajor: sp.dawnWeight >= 1.8,
            durationMin: 90,
          ),
        );
      }
      if (sp.duskWeight >= 1.3) {
        candidates.add(
          SolunarPeak(
            time: base.add(const Duration(hours: 19, minutes: 30)),
            isMajor: sp.duskWeight >= 1.8,
            durationMin: 90,
          ),
        );
      }
      if (sp.nightWeight >= 1.5) {
        candidates.add(
          SolunarPeak(
            time: base.add(const Duration(hours: 23)),
            isMajor: sp.nightWeight >= 1.8,
            durationMin: 120,
          ),
        );
      }
    }

    return candidates
        .where((p) => p.time.isAfter(now))
        .fold<SolunarPeak?>(
          null,
          (prev, curr) =>
              prev == null || curr.time.isBefore(prev.time) ? curr : prev,
        );
  }

  static double _bellCurve(double x, double center, double width) {
    return exp(-0.5 * pow((x - center) / width, 2));
  }
}

class WeatherData {
  final double? airTempC;
  final double? pressureHpa;
  final double?
  pressureTendency3hHpa; // Druckänderung letzte 3h (hPa, + = steigend)
  final double? windSpeedKmh;
  final double? windDirectionDeg;
  final double? precipitationMm;
  final String? description;
  final int? weatherCode;

  const WeatherData({
    this.airTempC,
    this.pressureHpa,
    this.pressureTendency3hHpa,
    this.windSpeedKmh,
    this.windDirectionDeg,
    this.precipitationMm,
    this.description,
    this.weatherCode,
  });

  /// Drucktendenz als Kurztext
  String get pressureTrendLabel => PressureTrend.label(pressureTendency3hHpa);

  /// Drucktendenz als Pfeilsymbol (mit VS15 erzwungene Text-Darstellung,
  /// damit iOS keine Emoji-Glyphe nutzt, die die Zeilenhöhe vergrößert).
  String get pressureTrendArrow => PressureTrend.arrow(pressureTendency3hHpa);

  /// Himmelsrichtung als Kurzbezeichnung (N, NO, O, SO, S, SW, W, NW)
  String get windDirectionLabel {
    final deg = windDirectionDeg;
    if (deg == null) return '–';
    const dirs = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    return dirs[((deg + 22.5) / 45).floor() % 8];
  }

  String get conditionLabel {
    final code = weatherCode;
    if (code == null) return 'Unbekannt';
    if (code == 0) return 'Klar';
    if (code == 1) return 'Heiter';
    if (code == 2) return 'Leicht bewölkt';
    if (code == 3) return 'Bedeckt';
    if (code <= 49) return 'Nebel';
    if (code <= 69) return 'Regen';
    if (code <= 79) return 'Schnee';
    if (code <= 99) return 'Gewitter';
    return 'Unbekannt';
  }

  String get conditionEmoji {
    final code = weatherCode;
    if (code == null) return '❓';
    if (code == 0) return '☀️';
    if (code == 1) return '🌤';
    if (code == 2) return '⛅';
    if (code == 3) return '☁️';
    if (code <= 49) return '🌫';
    if (code <= 69) return '🌧';
    if (code <= 79) return '❄️';
    if (code <= 99) return '⛈';
    return '❓';
  }

  /// Material-Icon, das zum [weatherCode] passt – einzige Quelle für
  /// Icon-Darstellung in der App, damit Label/Emoji/Icon synchron bleiben.
  IconData get conditionIconData => weatherCodeIcon(weatherCode);
}

class PredatorScore {
  final int score;
  final double moonPhase;
  final String moonPhaseLabel;
  final SolunarPeak? nextPeak;
  final Map<String, double> scoreBreakdown;
  final WeatherData weather;
  final SpeciesProfile speciesProfile;

  const PredatorScore({
    required this.score,
    required this.moonPhase,
    required this.moonPhaseLabel,
    this.nextPeak,
    required this.scoreBreakdown,
    required this.weather,
    required this.speciesProfile,
  });

  String get label {
    if (score >= 80) return 'OPTIMAL';
    if (score >= 60) return 'GUT';
    if (score >= 40) return 'MITTEL';
    if (score >= 20) return 'SCHWACH';
    return 'UNGÜNSTIG';
  }
}
