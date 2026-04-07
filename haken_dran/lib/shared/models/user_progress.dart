import 'package:cloud_firestore/cloud_firestore.dart';

class UserProgress {
  final String questionId;
  final int correctCount;
  final int wrongCount;
  final DateTime? lastSeen;
  final String? bundesland;

  /// Leitner-Fach (1–5). Fach 1 = häufige Wiederholung, Fach 5 = gut bekannt.
  final int leitnerBox;

  const UserProgress({
    required this.questionId,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.lastSeen,
    this.bundesland,
    this.leitnerBox = 1,
  });

  bool get isKnown => leitnerBox >= 4;
  double get accuracy =>
      (correctCount + wrongCount) == 0 ? 0 : correctCount / (correctCount + wrongCount);

  factory UserProgress.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProgress(
      questionId: doc.id,
      correctCount: (data['correct_count'] as int?) ?? 0,
      wrongCount: (data['wrong_count'] as int?) ?? 0,
      lastSeen: (data['last_seen'] as Timestamp?)?.toDate(),
      bundesland: data['bundesland'] as String?,
      leitnerBox: (data['leitner_box'] as int?) ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'correct_count': correctCount,
    'wrong_count': wrongCount,
    if (lastSeen != null) 'last_seen': Timestamp.fromDate(lastSeen!),
    if (bundesland != null) 'bundesland': bundesland,
    'leitner_box': leitnerBox,
  };

  UserProgress afterAnswer({required bool correct}) {
    final newBox = correct
        ? (leitnerBox < 5 ? leitnerBox + 1 : 5)
        : 1;
    return UserProgress(
      questionId: questionId,
      correctCount: correct ? correctCount + 1 : correctCount,
      wrongCount: correct ? wrongCount : wrongCount + 1,
      lastSeen: DateTime.now(),
      bundesland: bundesland,
      leitnerBox: newBox,
    );
  }
}
