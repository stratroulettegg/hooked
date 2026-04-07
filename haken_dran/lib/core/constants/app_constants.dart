abstract class AppConstants {
  // App-Metadaten
  static const String appName = 'Haken Dran';
  static const String appVersion = '1.0.0';

  // Firestore Collections
  static const String colQuestions = 'questions';
  static const String colUsers = 'users';
  static const String colUserProgress = 'user_progress';
  static const String colAchievements = 'achievements';
  static const String colUserAchievements = 'user_achievements';
  static const String colEvents = 'events';
  static const String colDuels = 'duels';

  // Remote Config Keys
  static const String rcCatalogVersion = 'catalog_version';
  static const String rcDuelEnabled = 'feature_duel_enabled';
  static const String rcPremiumEnabled = 'premium_enabled';

  // Gamification
  static const int xpPerCorrectAnswer = 10;
  static const int xpPerSimulationPassed = 150;
  static const int xpPerDailyGoal = 50;
  static const int xpPerfectRoundBonus = 75;
  static const int xpDailyStreak = 20;

  // Level-Schwellenwerte (XP zum Erreichen des Levels)
  static const List<int> levelThresholds = [
    0,     // Lvl 1
    100,   // Lvl 2
    250,   // Lvl 3
    500,   // Lvl 4
    900,   // Lvl 5  → Ende "Wurmwerfer"
    1400,  // Lvl 6
    2000,  // Lvl 7
    2800,  // Lvl 8
    3800,  // Lvl 9
    5000,  // Lvl 10 → Ende "Spinner"
    6500,  // Lvl 11
    8500,  // Lvl 12
    11000, // Lvl 13
    14000, // Lvl 14
    17500, // Lvl 15
    21500, // Lvl 16
    26000, // Lvl 17
    31500, // Lvl 18
    38000, // Lvl 19
    45500, // Lvl 20 → Ende "Petri-Jünger"
  ];

  static const List<String> levelTitles = [
    'Wurmwerfer',    // 1–5
    'Spinner',       // 6–10
    'Petri-Jünger',  // 11–20
    'Kescher-König',  // 21–35
    'Meisterangler', // 36–50
    'Legende am Wasser', // 50+
  ];

  // Lernziele (Minuten pro Tag)
  static const List<int> dailyGoalOptions = [5, 10, 20];

  // Blitzrunde
  static const int blitzQuestionCount = 10;
  static const int blitzTimeLimitSeconds = 300; // 5 Minuten

  // Duell
  static const int duelQuestionCount = 10;

  // MVP-Bundesländer (Phase 1)
  static const List<String> mvpBundeslaender = [
    'Brandenburg',
    'Mecklenburg-Vorpommern',
    'Sachsen-Anhalt',
  ];

  // Alle Bundesländer
  static const List<String> allBundeslaender = [
    'Baden-Württemberg',
    'Bayern',
    'Berlin',
    'Brandenburg',
    'Bremen',
    'Hamburg',
    'Hessen',
    'Mecklenburg-Vorpommern',
    'Niedersachsen',
    'Nordrhein-Westfalen',
    'Rheinland-Pfalz',
    'Saarland',
    'Sachsen',
    'Sachsen-Anhalt',
    'Schleswig-Holstein',
    'Thüringen',
  ];

  // Fragenkategorien
  static const String catFischkunde = 'fischkunde';
  static const String catGewaesserkunde = 'gewaesserkunde';
  static const String catTierschutz = 'tierschutz';
  static const String catFischereirecht = 'fischereirecht';
  static const String catNaturschutz = 'naturschutz';
  static const String catGeraetekunde = 'geraetekunde';

  static const List<String> categoriesBase = [
    catFischkunde,
    catGewaesserkunde,
    catTierschutz,
    catFischereirecht,
    catNaturschutz,
  ];

  static const Map<String, String> categoryLabels = {
    catFischkunde: 'Fischkunde',
    catGewaesserkunde: 'Gewässerkunde & Ökologie',
    catTierschutz: 'Tierschutz & Waidgerechtigkeit',
    catFischereirecht: 'Fischereirecht',
    catNaturschutz: 'Naturschutz',
    catGeraetekunde: 'Gerätekunde',
  };
}
