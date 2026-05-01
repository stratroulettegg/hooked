/// Kategorien lokaler Benachrichtigungen.
///
/// Werden nicht einzeln vom User getoggelt, sondern über
/// [NotificationProfile]-Presets gruppiert.
enum NotificationCategory {
  tripReminder(
    id: 'trip_reminder',
    label: 'Trip-Erinnerungen',
    description:
        'Am Vorabend (20:00) und am Morgen (5:30) deines geplanten Trips.',
  ),
  docNudge(
    id: 'doc_nudge',
    label: 'Doku-Erinnerung',
    description:
        'Folgetag 18:00, falls ein Fang ohne Foto oder Notiz erfasst wurde.',
  ),
  weeklyRecap(
    id: 'weekly_recap',
    label: 'Wochen-Recap',
    description: 'Sonntag 19:00 — Zusammenfassung deiner Woche.',
  ),
  streakProtection(
    id: 'streak_protection',
    label: 'Streak-Schutz',
    description:
        'Wenn dein Streak (Tage am Wasser) am Folgetag ablaufen würde.',
  ),
  onThisDay(
    id: 'on_this_day',
    label: 'Vor einem Jahr',
    description:
        'Sonntags 17:00 — wenn du vor genau einem Jahr in derselben Woche '
        'einen Fang erfasst hattest.',
  ),
  firstWaterOfMonth(
    id: 'first_water_of_month',
    label: 'Neuer Monat',
    description: '1. des Monats 09:00 — Lust auf eine kurze Trip-Planung?',
  ),
  monthlyRecap(
    id: 'monthly_recap',
    label: 'Monats-Recap',
    description: '1. des Monats 19:00 — der vergangene Monat in Zahlen.',
  );

  const NotificationCategory({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

/// Charakter-Presets, die festlegen, welche Kategorien aktiv sind.
enum NotificationProfile {
  focused(
    id: 'focused',
    label: 'Fokussiert',
    emoji: '🎯',
    description: 'Nur Trip-Reminder und Streak-Schutz.',
  ),
  standard(
    id: 'standard',
    label: 'Standard',
    emoji: '🎣',
    description: 'Trip, Doku, Streak und freundliche Saison-Nudges.',
  ),
  full(
    id: 'full',
    label: 'Voll dabei',
    emoji: '📬',
    description: 'Alles inkl. Wochen- und Monats-Recaps & On-this-Day.',
  );

  const NotificationProfile({
    required this.id,
    required this.label,
    required this.emoji,
    required this.description,
  });

  final String id;
  final String label;
  final String emoji;
  final String description;

  /// Liefert die für dieses Profil aktiven Kategorien.
  Set<NotificationCategory> get categories {
    switch (this) {
      case NotificationProfile.focused:
        return const {
          NotificationCategory.tripReminder,
          NotificationCategory.streakProtection,
        };
      case NotificationProfile.standard:
        return const {
          NotificationCategory.tripReminder,
          NotificationCategory.streakProtection,
          NotificationCategory.docNudge,
          NotificationCategory.onThisDay,
          NotificationCategory.firstWaterOfMonth,
        };
      case NotificationProfile.full:
        return const {
          NotificationCategory.tripReminder,
          NotificationCategory.streakProtection,
          NotificationCategory.docNudge,
          NotificationCategory.onThisDay,
          NotificationCategory.firstWaterOfMonth,
          NotificationCategory.weeklyRecap,
          NotificationCategory.monthlyRecap,
        };
    }
  }

  bool includes(NotificationCategory c) => categories.contains(c);
}
