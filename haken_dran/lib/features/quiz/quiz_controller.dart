import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/question.dart';
import '../../shared/models/user_progress.dart';
import '../../shared/services/question_repository.dart';
import '../../shared/services/user_repository.dart';
import '../../core/constants/app_constants.dart';

enum QuizStatus { loading, running, paused, finished }

class QuizState {
  final QuizStatus status;
  final List<Question> questions;
  final int currentIndex;
  final int? selectedAnswer;
  final bool isAnswered;
  final int secondsRemaining;
  final int correctCount;
  final Map<String, bool> answerMap; // questionId → correct
  final String? error;

  const QuizState({
    this.status = QuizStatus.loading,
    this.questions = const [],
    this.currentIndex = 0,
    this.selectedAnswer,
    this.isAnswered = false,
    this.secondsRemaining = AppConstants.blitzTimeLimitSeconds,
    this.correctCount = 0,
    this.answerMap = const {},
    this.error,
  });

  bool get isLastQuestion => currentIndex >= questions.length - 1;
  bool get isDone => currentIndex >= questions.length || status == QuizStatus.finished;
  Question? get currentQuestion =>
      questions.isNotEmpty && currentIndex < questions.length
          ? questions[currentIndex]
          : null;

  double get accuracy =>
      questions.isEmpty ? 0 : correctCount / questions.length;

  QuizState copyWith({
    QuizStatus? status,
    List<Question>? questions,
    int? currentIndex,
    int? selectedAnswer,
    bool? isAnswered,
    int? secondsRemaining,
    int? correctCount,
    Map<String, bool>? answerMap,
    String? error,
  }) {
    return QuizState(
      status: status ?? this.status,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      selectedAnswer: selectedAnswer,
      isAnswered: isAnswered ?? this.isAnswered,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      correctCount: correctCount ?? this.correctCount,
      answerMap: answerMap ?? this.answerMap,
      error: error ?? this.error,
    );
  }
}

class QuizController extends StateNotifier<QuizState> {
  final QuestionRepository _questionRepository;
  final UserRepository _userRepository;
  final String bundesland;

  Timer? _timer;

  QuizController({
    required QuestionRepository questionRepository,
    required UserRepository userRepository,
    required this.bundesland,
  })  : _questionRepository = questionRepository,
        _userRepository = userRepository,
        super(const QuizState()) {
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final all =
          await _questionRepository.getQuestionsForBundesland(bundesland);
      all.shuffle();
      final selected = all.take(AppConstants.blitzQuestionCount).toList();

      state = state.copyWith(
        status: QuizStatus.running,
        questions: selected,
        secondsRemaining: AppConstants.blitzTimeLimitSeconds,
      );
      _startTimer();
    } catch (e) {
      state = state.copyWith(
        status: QuizStatus.finished,
        error: 'Fragen konnten nicht geladen werden: $e',
      );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (state.secondsRemaining <= 1) {
        t.cancel();
        _finish();
      } else {
        state = state.copyWith(
            secondsRemaining: state.secondsRemaining - 1);
      }
    });
  }

  void selectAnswer(int index) {
    if (state.isAnswered || state.status != QuizStatus.running) return;
    final q = state.currentQuestion;
    if (q == null) return;

    final isCorrect = index == q.correctIndex;
    final newMap = Map<String, bool>.from(state.answerMap)
      ..[q.id] = isCorrect;

    state = state.copyWith(
      selectedAnswer: index,
      isAnswered: true,
      correctCount:
          isCorrect ? state.correctCount + 1 : state.correctCount,
      answerMap: newMap,
    );
  }

  void next() {
    if (!state.isAnswered) return;
    if (state.isLastQuestion) {
      _finish();
      return;
    }
    state = state.copyWith(
      currentIndex: state.currentIndex + 1,
      isAnswered: false,
      selectedAnswer: null,
    );
  }

  Future<void> _finish() async {
    _timer?.cancel();
    state = state.copyWith(status: QuizStatus.finished);
    await _persistResults();
  }

  Future<void> _persistResults() async {
    try {
      // XP vergeben
      int xp = state.correctCount * AppConstants.xpPerCorrectAnswer;
      if (state.correctCount == state.questions.length) {
        xp += AppConstants.xpPerfectRoundBonus;
      }
      await _userRepository.addXp(xp);

      // Lernfortschritt Leitner aktualisieren
      final progressUpdates = <UserProgress>[];
      for (final entry in state.answerMap.entries) {
        progressUpdates.add(
          UserProgress(
            questionId: entry.key,
            bundesland: bundesland,
          ).afterAnswer(correct: entry.value),
        );
      }
      if (progressUpdates.isNotEmpty) {
        await _userRepository.saveProgressBatch(progressUpdates);
      }
    } catch (_) {
      // Persistence-Fehler still ignorieren – Hauptfluss nicht unterbrechen
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Riverpod-Provider ──────────────────────────────────────────────────────

// Wird per `.family` mit dem Bundesland parametrisiert.
final quizControllerProvider = StateNotifierProvider.family<
    QuizController, QuizState, String>((ref, bundesland) {
  return QuizController(
    questionRepository: ref.watch(questionRepositoryProvider),
    userRepository: ref.watch(userRepositoryProvider),
    bundesland: bundesland,
  );
});
