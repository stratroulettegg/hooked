import '../../core/engines/predator_score_engine.dart';

/// Kompakte Lexikon-Daten zu jeder im Predator-Index aufgeführten Art.
///
/// Verbindet die wissenschaftlichen Profile aus [SpeciesProfile] mit
/// anglerisch relevanten Quick-Tipps & Fakten. Fakten basieren auf
/// gängiger Fischerei- und Aquakulturliteratur (Lucas & Baras 2001,
/// Tesch 2003, Holčík et al. 1988, Casselman & Lewis 1996, Elliott 1994).
class SpeciesLexiconEntry {
  const SpeciesLexiconEntry({
    required this.profile,
    required this.latin,
    required this.imagePath,
    required this.summary,
    required this.habitat,
    required this.bestSeason,
    required this.topLures,
    required this.tips,
    this.recordSizeCm,
    this.legalNote =
        'Schonzeit & Mindestmaß je Bundesland verschieden – '
        'aktuelles Landesfischereirecht prüfen.',
  });

  /// Verbindet mit dem Score-Profil (Temperatur, Aktivität, Druck …)
  final SpeciesProfile profile;
  final String latin;
  final String imagePath;

  /// 1–2 Sätze: was für ein Räuber/Fisch ist das, wie jagt er.
  final String summary;
  final String habitat;
  final String bestSeason;
  final List<String> topLures;
  final List<String> tips;
  final int? recordSizeCm;
  final String legalNote;
}

class SpeciesLexicon {
  static final List<SpeciesLexiconEntry> entries = [
    SpeciesLexiconEntry(
      profile: SpeciesProfiles.hecht,
      latin: 'Esox lucius',
      imagePath: 'assets/fische/hecht.png',
      summary:
          'Solitärer Lauerjäger mit explosiver Beschleunigung. Nutzt Krautkanten, '
          'Holzstrukturen und Druckabfälle vor Fronten zur Jagd.',
      habitat: 'Krautkanten, Schilf, Totholz, Übergänge flach → tief',
      bestSeason: 'Herbst (Sept–Nov) & Frühjahr nach der Schonzeit',
      topLures: [
        'Großer Gummifisch 15–23 cm',
        'Jerkbait',
        'Spinnerbait',
        'Köderfisch (tot/lebend wo erlaubt)',
      ],
      recordSizeCm: 150,
      tips: [
        'Bei Druckabfall vor einer Front ans Wasser – Beißzeit nutzen.',
        'Im Sommer flache Kanten meiden, an Sprungschicht (4–8 m) suchen.',
        'Bei <8 °C verschiebt sich Aktivität in die Mittagsstunden.',
        'Stahl- oder Hardmono-Vorfach Pflicht – Hechtzähne durchtrennen Mono.',
      ],
    ),
    SpeciesLexiconEntry(
      profile: SpeciesProfiles.zander,
      latin: 'Sander lucioperca',
      imagePath: 'assets/fische/zander.png',
      summary:
          'Dämmerungs- und Nachtjäger. Tapetum lucidum (reflektierende Schicht im Auge) '
          'gibt ihm bei Trübung und Dunkelheit klaren Vorteil gegenüber Beutefischen.',
      habitat: 'Tiefe Rinnen, Fahrrinnenkanten, Steinpackungen, Buhnenfelder',
      bestSeason: 'Spätfrühjahr nach Laichschonzeit, Herbst',
      topLures: [
        'Gummifisch 8–14 cm am Jigkopf',
        'Köderfisch auf Grund',
        'Wobbler suspending',
      ],
      recordSizeCm: 130,
      tips: [
        'Bei steigendem Wasserstand & Trübung am Tag aktiv – sonst Dämmerung.',
        'Geschlossene Schwimmblase → reagiert stark auf Druckwechsel.',
        'Vertikalfischen über Schwarmfischen (Brassen, Lauben) im Winter.',
        'Feines Fluorocarbon-Vorfach 0,28–0,35 mm – Zander sind sichtscheu.',
      ],
    ),
    SpeciesLexiconEntry(
      profile: SpeciesProfiles.barsch,
      latin: 'Perca fluviatilis',
      imagePath: 'assets/fische/barsch.png',
      summary:
          'Tagaktiver Schwarmjäger ohne Tapetum lucidum. Treibt Beutefische ans '
          'Ufer oder an die Oberfläche und attackiert in Gruppen.',
      habitat:
          'Steg- & Spundwandkanten, Krautfelder, Hindernisse, Strömungskanten',
      bestSeason: 'Spätsommer bis Herbst (Barschbarsch-Zeit)',
      topLures: [
        'Mini-Gummifisch 5–8 cm',
        'Spinner Gr. 1–3',
        'Drop-Shot mit Wurm/Creature',
        'Chatterbait micro',
      ],
      recordSizeCm: 60,
      tips: [
        'Wenn ein Barsch beißt – Stelle weiter befischen, Schwarm bleibt oft.',
        'Bei Sonne Jagd auf Brut sichtbar (Oberflächenboils) – schnell reagieren.',
        'Bei Dunkelheit nahezu inaktiv – kein Tapetum lucidum.',
        'Klares Wasser bevorzugt – stark trübe Gewässer meiden.',
      ],
    ),
    SpeciesLexiconEntry(
      profile: SpeciesProfiles.wels,
      latin: 'Silurus glanis',
      imagePath: 'assets/fische/wels.png',
      summary:
          'Größter Süßwasserräuber Europas. Nachtaktiver Jäger mit ausgeprägtem '
          'Geruchs-, Geschmacks- und Seitenliniensinn – jagt auch in völliger Dunkelheit.',
      habitat:
          'Tiefe Kolke, Buhnenkessel, Holzbarrieren, warme Kraftwerksausläufe',
      bestSeason: 'Hochsommer (Juni–August) bei warmen Nächten',
      topLures: [
        'Tauwurmbündel auf Unterwasserpose',
        'Köderfisch 15–25 cm',
        'Großer Gummifisch 20+ cm',
        'Klopfholz am Boot',
      ],
      recordSizeCm: 280,
      tips: [
        'Ab 18 °C Wassertemperatur ernsthaft auf Fressrate – darunter zäh.',
        'Druck spielt kaum eine Rolle – auf Mondphase + Wassertemperatur fokussieren.',
        'Mehrere Bissanzeiger / Glocken: Welse rauben mit Anlauf, kein Vorbiss.',
        'Schnur min. 0,50 mm Mono / 70 lb Geflecht – Gewicht & Fluchten extrem.',
      ],
    ),
    SpeciesLexiconEntry(
      profile: SpeciesProfiles.forelle,
      latin: 'Salmo trutta',
      imagePath: 'assets/fische/forelle.png',
      summary:
          'Kaltwasserspezialist mit hohem Sauerstoffbedarf. Standfisch hinter Strömungs'
          'bremsen, sehr druck- und sichtempfindlich.',
      habitat: 'Klare Bäche & Seen, Stromrinnen, Gumpen, Einläufe',
      bestSeason: 'Frühjahr bis Frühsommer & Herbst (außerhalb Schonzeit)',
      topLures: [
        'Trockenfliege',
        'Nymphe',
        'Spinner Gr. 0–2',
        'Sbirolino mit Made/Bienenmade',
      ],
      recordSizeCm: 80,
      tips: [
        'Über 18 °C Wassertemperatur Stress – Fang & Release nur mit Vorsicht.',
        'Stark druckempfindlich – fallender Druck = aktiver Fisch.',
        'Tarnung wichtig: gedämpfte Kleidung, Schatten meiden, leise treten.',
        'Aufstrom werfen, mit der Strömung präsentieren.',
      ],
    ),
    SpeciesLexiconEntry(
      profile: SpeciesProfiles.huchen,
      latin: 'Hucho hucho',
      imagePath: 'assets/fische/huchen.png',
      summary:
          'Größter Salmonide Europas, alpiner Donau-Endemit. Standfisch in tiefen '
          'Gumpen, jagt morgens & in der Dämmerung auf Weißfisch.',
      habitat: 'Donau-Zuflüsse, tiefe Gumpen mit Strömungskante',
      bestSeason: 'Spätherbst & Winter (Saison meist Okt–Feb)',
      topLures: [
        'Großer Streamer 20+ cm',
        'Großer Wobbler',
        'Köderfisch wo erlaubt',
      ],
      recordSizeCm: 180,
      tips: [
        'Hochdruck + kaltes Wasser = ideale Kombination.',
        'Sehr lokal – einmal Standplatz gefunden, immer wieder probieren.',
        'Strenge Schonbestimmungen, oft Catch & Release Pflicht.',
        'Geduldsfisch – oft tagelange Sessions für einen Biss.',
      ],
    ),
    SpeciesLexiconEntry(
      profile: SpeciesProfiles.aal,
      latin: 'Anguilla anguilla',
      imagePath: 'assets/fische/aal.png',
      summary:
          'Klassischer Nachtfisch, bentisch (Grund), wandert tausende Kilometer in die '
          'Sargasso-See zum Laichen. Bestand stark gefährdet.',
      habitat: 'Schlammige Gründe, Krautränder, Schleusen, Hafenbecken',
      bestSeason: 'Mai bis September, warme Sommernächte',
      topLures: ['Tauwurm auf Grund', 'Köderfischfetzen', 'Bienenmaden-Bündel'],
      recordSizeCm: 130,
      tips: [
        'Druck spielt kaum eine Rolle – auf Wassertemperatur (>14 °C) achten.',
        'Bewölkte, warme Nächte mit Gewitter-Vorlauf = Top-Bedingungen.',
        'Schonend behandeln & möglichst zurücksetzen – Bestand kollabiert.',
        'Hakenlöser & Lappen bereithalten – Aal verknotet sich mit Vorfach.',
      ],
    ),
  ];

  /// Findet den Eintrag passend zu einem Score-Profil (oder null).
  static SpeciesLexiconEntry? entryFor(SpeciesProfile profile) {
    for (final e in entries) {
      if (e.profile.name == profile.name) return e;
    }
    return null;
  }
}
