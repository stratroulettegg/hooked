import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../onboarding_controller.dart';

// Statische Demofragen für die Diagnose (kein Firestore-Call nötig).
const _diagnosisQuestions = [
  _DiagnosisQuestion(
    text: 'Was ist bei einem Fisch das Seitenlinienorgan?',
    options: [
      'Ein Geruchsorgan',
      'Ein Sinnesorgan für Druckwellen im Wasser',
      'Ein Atemorgan',
      'Ein Teil der Schwimmblase',
    ],
    correctIndex: 1,
  ),
  _DiagnosisQuestion(
    text: 'Was versteht man unter dem Begriff "Schonzeit"?',
    options: [
      'Zeit, in der das Angeln verboten ist',
      'Zeitraum, in dem bestimmte Fischarten nicht gefangen werden dürfen',
      'Zeitraum, in dem kein Angelschein benötigt wird',
      'Zeit, in der nur mit Kunstköder geangelt werden darf',
    ],
    correctIndex: 1,
  ),
  _DiagnosisQuestion(
    text: 'Welche der folgenden Angaben beschreibt das Mindestmaß korrekt?',
    options: [
      'Die minimale Ruten­länge beim Angeln',
      'Das Mindest­gewicht eines Fisches',
      'Die Mindest­länge, ab der ein Fisch entnommen werden darf',
      'Die Mindest­tiefe eines Gewässers',
    ],
    correctIndex: 2,
  ),
  _DiagnosisQuestion(
    text: 'Was ist ein pH-Wert im Kontext von Gewässern?',
    options: [
      'Ein Maß für den Sauerstoff­gehalt',
      'Ein Maß für den Säure-/Basen-Gehalt des Wassers',
      'Ein Maß für die Wassertemperatur',
      'Ein Maß für die Wassertiefe',
    ],
    correctIndex: 1,
  ),
  _DiagnosisQuestion(
    text: 'Welches Verhalten ist beim Fang eines unter dem Mindestmaß liegenden Fisches korrekt?',
    options: [
      'Den Fisch behalten und als Aasfisch verwenden',
      'Den Fisch sofort schonend zurücksetzen',
      'Den Fisch erst nach Hause nehmen und dann entscheiden',
      'Den Fisch an andere Angler weitergeben',
    ],
    correctIndex: 1,
  ),
];

class _DiagnosisQuestion {
  final String text;
  final List<String> options;
  final int correctIndex;

  const _DiagnosisQuestion({
    required this.text,
    required this.options,
    required this.correctIndex,
  });
}

// ── Diagnosis State ─────────────────────────────────────────────────────────

class _DiagnosisState {
  final int currentIndex;
  final int? selectedAnswer;
  final bool isAnswered;
  final List<bool> results;

  const _DiagnosisState({
    this.currentIndex = 0,
    this.selectedAnswer,
    this.isAnswered = false,
    this.results = const [],
  });

  bool get isDone => currentIndex >= _diagnosisQuestions.length;

  int get correctCount => results.where((r) => r).length;

  _DiagnosisState copyWith({
    int? currentIndex,
    int? selectedAnswer,
    bool? isAnswered,
    List<bool>? results,
  }) {
    return _DiagnosisState(
      currentIndex: currentIndex ?? this.currentIndex,
      selectedAnswer: selectedAnswer,
      isAnswered: isAnswered ?? this.isAnswered,
      results: results ?? this.results,
    );
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class OnboardingDiagnosisScreen extends ConsumerStatefulWidget {
  const OnboardingDiagnosisScreen({super.key});

  @override
  ConsumerState<OnboardingDiagnosisScreen> createState() =>
      _OnboardingDiagnosisScreenState();
}

class _OnboardingDiagnosisScreenState
    extends ConsumerState<OnboardingDiagnosisScreen> {
  _DiagnosisState _state = const _DiagnosisState();

  void _selectAnswer(int index) {
    if (_state.isAnswered) return;
    setState(() {
      _state = _state.copyWith(selectedAnswer: index, isAnswered: true);
    });
  }

  void _next() {
    if (!_state.isAnswered) return;
    final isCorrect =
        _state.selectedAnswer ==
            _diagnosisQuestions[_state.currentIndex].correctIndex;
    final updatedResults = [..._state.results, isCorrect];

    setState(() {
      _state = _state.copyWith(
        currentIndex: _state.currentIndex + 1,
        isAnswered: false,
        selectedAnswer: null,
        results: updatedResults,
      );
    });

    if (_state.isDone) {
      _finishDiagnosis();
    }
  }

  Future<void> _finishDiagnosis() async {
    final success = await ref
        .read(onboardingControllerProvider.notifier)
        .completeOnboarding();
    if (success && mounted) {
      context.go(Routes.home);
    }
  }

  void _skip() {
    _finishDiagnosis();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(
        onboardingControllerProvider.select((s) => s.isLoading));

    if (_state.isDone || isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final q = _diagnosisQuestions[_state.currentIndex];
    final progress =
        (_state.currentIndex + 1) / _diagnosisQuestions.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Diagnose ${_state.currentIndex + 1}/${_diagnosisQuestions.length}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _skip,
            child: const Text('Überspringen'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress Bar
          LinearProgressIndicator(
            value: progress,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            color: AppColors.primary,
            minHeight: 4,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    q.text,
                    style: AppTextStyles.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  ...List.generate(
                    q.options.length,
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AnswerButton(
                        text: q.options[i],
                        state: _getAnswerState(i, q.correctIndex),
                        onTap: () => _selectAnswer(i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_state.isAnswered)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _state.currentIndex + 1 == _diagnosisQuestions.length
                        ? 'Fertig'
                        : 'Weiter',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _AnswerState _getAnswerState(int index, int correctIndex) {
    if (!_state.isAnswered) return _AnswerState.none;
    if (index == correctIndex) return _AnswerState.correct;
    if (index == _state.selectedAnswer) return _AnswerState.wrong;
    return _AnswerState.none;
  }
}

enum _AnswerState { none, correct, wrong }

class _AnswerButton extends StatelessWidget {
  final String text;
  final _AnswerState state;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.text,
    required this.state,
    required this.onTap,
  });

  Color _bgColor(BuildContext context) {
    switch (state) {
      case _AnswerState.correct:
        return AppColors.success.withValues(alpha: 0.15);
      case _AnswerState.wrong:
        return AppColors.error.withValues(alpha: 0.15);
      case _AnswerState.none:
        return Theme.of(context).colorScheme.surface;
    }
  }

  Color _borderColor(BuildContext context) {
    switch (state) {
      case _AnswerState.correct:
        return AppColors.success;
      case _AnswerState.wrong:
        return AppColors.error;
      case _AnswerState.none:
        return Theme.of(context).colorScheme.outline.withValues(alpha: 0.3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor(context), width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: AppTextStyles.bodyLarge)),
            if (state == _AnswerState.correct)
              const Icon(Icons.check_circle, color: AppColors.success),
            if (state == _AnswerState.wrong)
              const Icon(Icons.cancel, color: AppColors.error),
          ],
        ),
      ),
    );
  }
}
