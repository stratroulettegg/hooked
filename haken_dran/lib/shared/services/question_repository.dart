import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/question.dart';
import 'local_database_service.dart';

/// Firestore-Collection + sqflite-Cache für Fragen.
/// Strategie: Cache zuerst (offline-first), im Hintergrund mit Firestore sync.
class QuestionRepository {
  final FirebaseFirestore _firestore;
  final LocalDatabaseService _localDb;

  QuestionRepository({
    required FirebaseFirestore firestore,
    required LocalDatabaseService localDb,
  })  : _firestore = firestore,
        _localDb = localDb;

  // ── Firestore ──────────────────────────────────────────────────────────────

  /// Alle Fragen eines Bundeslandes. Gibt gecachte Fragen zurück,
  /// triggert im Hintergrund eine Sync wenn eine neue Katalogversion vorliegt.
  Future<List<Question>> getQuestionsForBundesland(String bundesland) async {
    final cached = await _localDb.getCachedQuestions(bundesland: bundesland);
    if (cached.isNotEmpty) return cached;
    return _fetchAndCache(bundesland: bundesland);
  }

  /// Fragen nach Kategorie (optional bundesland-gefiltert).
  Future<List<Question>> getQuestionsByCategory({
    required String category,
    String? bundesland,
  }) async {
    final cached = await _localDb.getCachedQuestions(
      category: category,
      bundesland: bundesland,
    );
    if (cached.isNotEmpty) return cached;
    return _fetchAndCache(category: category, bundesland: bundesland);
  }

  /// Einzelne Frage per ID.
  Future<Question?> getQuestionById(String id) async {
    final cached = await _localDb.getCachedQuestionById(id);
    if (cached != null) return cached;

    final doc = await _firestore.collection('questions').doc(id).get();
    if (!doc.exists) return null;
    final q = Question.fromFirestore(doc);
    await _localDb.cacheQuestions([q]);
    return q;
  }

  /// Lädt Fragen von Firestore und speichert sie in sqflite.
  Future<List<Question>> _fetchAndCache({
    String? bundesland,
    String? category,
  }) async {
    Query<Map<String, dynamic>> query = _firestore.collection('questions');

    if (bundesland != null) {
      query = query.where(
        Filter.or(
          Filter('bundesland', isEqualTo: bundesland),
          Filter('bundesland', isNull: true),
        ),
      );
    }
    if (category != null) {
      query = query.where('category', isEqualTo: category);
    }

    final snapshot = await query.get();
    final questions =
        snapshot.docs.map((d) => Question.fromFirestore(d)).toList();
    if (questions.isNotEmpty) {
      await _localDb.cacheQuestions(questions);
    }
    return questions;
  }

  /// Prüft ob der lokale Cache aktuell ist (Versionsnummer in Firestore-Metadata).
  Future<bool> isCacheStale(String bundesland, int localVersion) async {
    final meta = await _firestore
        .collection('meta')
        .doc('catalog_$bundesland')
        .get();
    if (!meta.exists) return false;
    final remoteVersion = (meta.data()?['version'] as int?) ?? 0;
    return remoteVersion > localVersion;
  }

  /// Vollständige Neu-Synchronisierung für ein Bundesland.
  Future<List<Question>> forceSync(String bundesland) async {
    await _localDb.clearQuestionsForBundesland(bundesland);
    return _fetchAndCache(bundesland: bundesland);
  }
}

// ── Riverpod-Provider ──────────────────────────────────────────────────────

final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return QuestionRepository(
    firestore: FirebaseFirestore.instance,
    localDb: ref.watch(localDatabaseServiceProvider),
  );
});
