import 'package:cloud_firestore/cloud_firestore.dart';

class Question {
  final String id;
  final String text;
  final List<String> options;
  final int correctIndex;
  final String category;
  final String? bundesland; // null = für alle Bundesländer
  final String? explanation;
  final int difficulty; // 1 = einfach, 2 = mittel, 3 = schwer

  const Question({
    required this.id,
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.category,
    this.bundesland,
    this.explanation,
    this.difficulty = 1,
  });

  factory Question.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Question(
      id: doc.id,
      text: data['text'] as String,
      options: List<String>.from(data['options'] as List),
      correctIndex: data['correct_index'] as int,
      category: data['category'] as String,
      bundesland: data['bundesland'] as String?,
      explanation: data['explanation'] as String?,
      difficulty: (data['difficulty'] as int?) ?? 1,
    );
  }

  factory Question.fromMap(Map<String, dynamic> map, String id) {
    return Question(
      id: id,
      text: map['text'] as String,
      options: List<String>.from(map['options'] as List),
      correctIndex: map['correct_index'] as int,
      category: map['category'] as String,
      bundesland: map['bundesland'] as String?,
      explanation: map['explanation'] as String?,
      difficulty: (map['difficulty'] as int?) ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'text': text,
    'options': options,
    'correct_index': correctIndex,
    'category': category,
    if (bundesland != null) 'bundesland': bundesland,
    if (explanation != null) 'explanation': explanation,
    'difficulty': difficulty,
  };
}
