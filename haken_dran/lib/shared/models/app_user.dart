import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String bundesland;
  final int xp;
  final int streak;
  final DateTime? lastActive;
  final bool isPremium;
  final DateTime? examDate;
  final int dailyGoalMinutes;

  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    required this.bundesland,
    this.xp = 0,
    this.streak = 0,
    this.lastActive,
    this.isPremium = false,
    this.examDate,
    this.dailyGoalMinutes = 10,
  });

  int get level {
    if (xp < 100) return 1;
    if (xp < 250) return 2;
    if (xp < 500) return 3;
    if (xp < 900) return 4;
    if (xp < 1400) return 5;
    if (xp < 2000) return 6;
    if (xp < 2800) return 7;
    if (xp < 3800) return 8;
    if (xp < 5000) return 9;
    if (xp < 6500) return 10;
    if (xp < 8500) return 11;
    if (xp < 11000) return 12;
    if (xp < 14000) return 13;
    if (xp < 17500) return 14;
    if (xp < 21500) return 15;
    if (xp < 26000) return 16;
    if (xp < 31500) return 17;
    if (xp < 38000) return 18;
    if (xp < 45500) return 19;
    return 20;
  }

  String get levelTitle {
    final l = level;
    if (l <= 5) return 'Wurmwerfer';
    if (l <= 10) return 'Spinner';
    if (l <= 20) return 'Petri-Jünger';
    if (l <= 35) return 'Kescher-König';
    if (l <= 50) return 'Meisterangler';
    return 'Legende am Wasser';
  }

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] as String?,
      displayName: data['display_name'] as String?,
      bundesland: (data['bundesland'] as String?) ?? 'Brandenburg',
      xp: (data['xp'] as int?) ?? 0,
      streak: (data['streak'] as int?) ?? 0,
      lastActive: (data['last_active'] as Timestamp?)?.toDate(),
      isPremium: (data['is_premium'] as bool?) ?? false,
      examDate: (data['exam_date'] as Timestamp?)?.toDate(),
      dailyGoalMinutes: (data['daily_goal_minutes'] as int?) ?? 10,
    );
  }

  Map<String, dynamic> toMap() => {
    if (email != null) 'email': email,
    if (displayName != null) 'display_name': displayName,
    'bundesland': bundesland,
    'xp': xp,
    'streak': streak,
    if (lastActive != null) 'last_active': Timestamp.fromDate(lastActive!),
    'is_premium': isPremium,
    if (examDate != null) 'exam_date': Timestamp.fromDate(examDate!),
    'daily_goal_minutes': dailyGoalMinutes,
  };

  AppUser copyWith({
    String? displayName,
    String? bundesland,
    int? xp,
    int? streak,
    DateTime? lastActive,
    bool? isPremium,
    DateTime? examDate,
    int? dailyGoalMinutes,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      bundesland: bundesland ?? this.bundesland,
      xp: xp ?? this.xp,
      streak: streak ?? this.streak,
      lastActive: lastActive ?? this.lastActive,
      isPremium: isPremium ?? this.isPremium,
      examDate: examDate ?? this.examDate,
      dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
    );
  }
}
