import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/question.dart';

/// SQLite-Datenbank für Offline-Caching von Fragen und Lernfortschritt.
class LocalDatabaseService {
  static const _dbName = 'haken_dran.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE questions (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        options TEXT NOT NULL,
        correct_index INTEGER NOT NULL,
        category TEXT NOT NULL,
        bundesland TEXT,
        explanation TEXT,
        difficulty INTEGER NOT NULL DEFAULT 1,
        cached_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_questions_bundesland ON questions(bundesland);
    ''');
    await db.execute('''
      CREATE INDEX idx_questions_category ON questions(category);
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrationspfade werden hier ergänzt wenn nötig.
  }

  // ── Fragen ─────────────────────────────────────────────────────────────

  Future<void> cacheQuestions(List<Question> questions) async {
    final db = await _database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final q in questions) {
      batch.insert(
        'questions',
        {
          'id': q.id,
          'text': q.text,
          'options': q.options.join('|||'),
          'correct_index': q.correctIndex,
          'category': q.category,
          'bundesland': q.bundesland,
          'explanation': q.explanation,
          'difficulty': q.difficulty,
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Question>> getCachedQuestions({
    String? bundesland,
    String? category,
  }) async {
    final db = await _database;
    final where = <String>[];
    final args = <Object>[];

    if (bundesland != null) {
      where.add('(bundesland = ? OR bundesland IS NULL)');
      args.add(bundesland);
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }

    final rows = await db.query(
      'questions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
    return rows.map(_rowToQuestion).toList();
  }

  Future<Question?> getCachedQuestionById(String id) async {
    final db = await _database;
    final rows =
        await db.query('questions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _rowToQuestion(rows.first);
  }

  Future<void> clearQuestionsForBundesland(String bundesland) async {
    final db = await _database;
    await db.delete(
      'questions',
      where: 'bundesland = ?',
      whereArgs: [bundesland],
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────

  Question _rowToQuestion(Map<String, dynamic> row) {
    return Question(
      id: row['id'] as String,
      text: row['text'] as String,
      options: (row['options'] as String).split('|||'),
      correctIndex: row['correct_index'] as int,
      category: row['category'] as String,
      bundesland: row['bundesland'] as String?,
      explanation: row['explanation'] as String?,
      difficulty: row['difficulty'] as int,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

// ── Riverpod-Provider ──────────────────────────────────────────────────────

final localDatabaseServiceProvider = Provider<LocalDatabaseService>((ref) {
  final service = LocalDatabaseService();
  ref.onDispose(service.close);
  return service;
});
