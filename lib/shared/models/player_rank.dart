/// Rang-Stufen für den Spieler. Punkte = Fänge × 50 + Summe der Missions-Rewards.
class PlayerRank {
  final String title;
  final String emoji;
  final int minPoints;

  const PlayerRank({
    required this.title,
    required this.emoji,
    required this.minPoints,
  });

  static const all = <PlayerRank>[
    PlayerRank(title: 'NEULING', emoji: '🐣', minPoints: 0),
    PlayerRank(title: 'ANFÄNGER', emoji: '🪝', minPoints: 200),
    PlayerRank(title: 'FREIZEITANGLER', emoji: '🧰', minPoints: 500),
    PlayerRank(title: 'FORTGESCHRITTEN', emoji: '📈', minPoints: 1000),
    PlayerRank(title: 'ERFAHRENER ANGLER', emoji: '🎯', minPoints: 2000),
    PlayerRank(title: 'EXPERTE', emoji: '🧭', minPoints: 3500),
    PlayerRank(title: 'SCHARFSCHÜTZE', emoji: '🏹', minPoints: 5000),
    PlayerRank(title: 'MEISTER', emoji: '🏆', minPoints: 7500),
    PlayerRank(title: 'GROSSMEISTER', emoji: '🥇', minPoints: 10000),
    PlayerRank(title: 'RAUBFISCH-KENNER', emoji: '🎣', minPoints: 15000),
    PlayerRank(title: 'ELITE-JÄGER', emoji: '⚔️', minPoints: 20000),
    PlayerRank(title: 'PREDATOR', emoji: '🗡️', minPoints: 27500),
    PlayerRank(title: 'APEX PREDATOR', emoji: '👑', minPoints: 35000),
    PlayerRank(title: 'LEGENDE', emoji: '🌟', minPoints: 50000),
    PlayerRank(title: 'MYTHOS', emoji: '🔱', minPoints: 75000),
  ];

  /// Ermittelt den aktuellen Rang anhand der Punkte.
  static PlayerRank forPoints(int points) {
    var current = all.first;
    for (final r in all) {
      if (points >= r.minPoints) current = r;
    }
    return current;
  }

  /// Nächster Rang (oder null, wenn bereits höchster).
  static PlayerRank? nextAfter(PlayerRank rank) {
    final idx = all.indexOf(rank);
    if (idx == -1 || idx == all.length - 1) return null;
    return all[idx + 1];
  }
}
