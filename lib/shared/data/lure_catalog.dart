/// Gemeinsame Köder-Taxonomie, wird sowohl vom Fangeintrag-Picker als auch
/// von der Köderlevel-Seite verwendet.
const Map<String, List<String>> kLureCatalog = {
  'Metallköder': [
    'Klassischer Blinker',
    'Spoon (Forellenblinker)',
    'Standard-Spinner',
    'Weitwurf-Spinner',
    'Zocker / Vertikalpilker',
    'Zikade (Blade Bait)',
    'Jig-Spinner (Tail-Spinner)',
  ],
  'Wobbler': [
    'Minnow',
    'Crankbait',
    'Twitchbait',
    'Deep Diver',
    'Micro-Wobbler',
    'Wakebait',
  ],
  'Oberflächenköder': ['Stickbait', 'Popper', 'Propellerbait / Torpedo'],
  'Jerkbaits & Hard-Swimbaits': [
    'Glider (Jerkbait)',
    'Diver (Jerkbait)',
    'Hard-Swimbait',
    'Hybrid-Swimbait',
  ],
  'Gummifische': [
    'Action-Shad (Paddletail)',
    'Low-Action-Shad',
    'Twister (Grub)',
    'Curltail-Shad',
    'Soft-Swimbait (Big Bait)',
  ],
  'Finesse-Gummis': ['V-Tail Shad', 'Pin-Tail Shad', 'Softjerk', 'Tube'],
  'Creature Baits & Frösche': [
    'Gummi-Krebs (Craw)',
    'Finesse-Wurm',
    'Insekten-Imitation',
    'Creature Bait',
    'Hollow Body Frog',
  ],
  'Fransen- & Drahtköder': [
    'Chatterbait (Bladed Jig)',
    'Spinnerbait',
    'Skirted Jig',
  ],
  'Naturköder': ['Wurm', 'Dead Bait'],
};

/// Anzahl Fänge pro Level-Stufe (Level 1 = 1-5 Fänge, Level 2 = 6-10, …).
const int kLureCatchesPerLevel = 5;

/// Max. Level (Endgame).
const int kLureMaxLevel = 10;

/// Liefert das Level (0–10) für eine gegebene Fangzahl.
int lureLevelFor(int catches) {
  if (catches <= 0) return 0;
  final lvl = (catches / kLureCatchesPerLevel).ceil();
  return lvl > kLureMaxLevel ? kLureMaxLevel : lvl;
}

/// Wie viele Fänge noch bis zum nächsten Level (null wenn Max erreicht).
int? lureToNextLevel(int catches) {
  final lvl = lureLevelFor(catches);
  if (lvl >= kLureMaxLevel) return null;
  // Level N startet bei (N-1)*5+1, endet bei N*5.
  // Nächstes Level (lvl+1) startet bei lvl*5 + 1.
  return (lvl * kLureCatchesPerLevel + 1) - catches;
}
