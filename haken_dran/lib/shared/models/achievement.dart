import 'package:cloud_firestore/cloud_firestore.dart';

class Achievement {
  final String id;
  final String title;
  final String description;
  final String iconAsset;
  final AchievementCategory category;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.iconAsset,
    required this.category,
  });

  factory Achievement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Achievement(
      id: doc.id,
      title: data['title'] as String,
      description: data['description'] as String,
      iconAsset: (data['icon_asset'] as String?) ?? 'assets/icons/badge_default.png',
      category: AchievementCategory.fromString(data['category'] as String? ?? 'skill'),
    );
  }
}

class UserAchievement {
  final String achievementId;
  final DateTime unlockedAt;

  const UserAchievement({
    required this.achievementId,
    required this.unlockedAt,
  });

  factory UserAchievement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserAchievement(
      achievementId: doc.id,
      unlockedAt: (data['unlocked_at'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'unlocked_at': Timestamp.fromDate(unlockedAt),
  };
}

enum AchievementCategory {
  knowledge,
  endurance,
  skill;

  static AchievementCategory fromString(String value) {
    return AchievementCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AchievementCategory.skill,
    );
  }
}
