import 'package:cloud_firestore/cloud_firestore.dart';

enum DuelStatus { pending, active, completed, expired }

class Duel {
  final String id;
  final String challengerId;
  final String? challengeeId;
  final DuelStatus status;
  final String bundesland;
  final List<String> questionIds;
  final Map<String, int> scores; // userId -> score
  final DateTime createdAt;
  final DateTime? completedAt;

  const Duel({
    required this.id,
    required this.challengerId,
    this.challengeeId,
    required this.status,
    required this.bundesland,
    required this.questionIds,
    required this.scores,
    required this.createdAt,
    this.completedAt,
  });

  factory Duel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Duel(
      id: doc.id,
      challengerId: data['challenger_id'] as String,
      challengeeId: data['challengee_id'] as String?,
      status: DuelStatus.values.firstWhere(
        (s) => s.name == (data['status'] as String? ?? 'pending'),
        orElse: () => DuelStatus.pending,
      ),
      bundesland: data['bundesland'] as String,
      questionIds: List<String>.from(data['question_ids'] as List? ?? []),
      scores: Map<String, int>.from(data['scores'] as Map? ?? {}),
      createdAt: (data['created_at'] as Timestamp).toDate(),
      completedAt: (data['completed_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'challenger_id': challengerId,
    'challengee_id': challengeeId,
    'status': status.name,
    'bundesland': bundesland,
    'question_ids': questionIds,
    'scores': scores,
    'created_at': Timestamp.fromDate(createdAt),
    if (completedAt != null) 'completed_at': Timestamp.fromDate(completedAt!),
  };

  String? get winnerId {
    if (status != DuelStatus.completed || scores.length < 2) return null;
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted[0].value == sorted[1].value) return null; // draw
    return sorted.first.key;
  }
}
