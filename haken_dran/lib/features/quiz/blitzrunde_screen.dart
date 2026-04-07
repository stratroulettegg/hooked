import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/services/user_repository.dart';
import 'quiz_controller.dart';
import 'quiz_result_screen.dart';

class BlitzrundeScreen extends ConsumerWidget {
  const BlitzrundeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bundesland aus dem aktuell angemeldeten User lesen
    final userAsync = ref.watch(currentUserProvider);
    final bundesland = userAsync.valueOrNull?.bundesland ?? 'Brandenburg';

    final quizState = ref.watch(quizControllerProvider(bundesland));
    final controller =
        ref.read(quizControllerProvider(bundesland).notifier);

    // Quiz beendet → Ergebnis-Screen
    if (quizState.status == QuizStatus.finished) {
      return QuizResultScreen(
        correctCount: quizState.correctCount,
        totalCount: quizState.questions.length,
        bundesland: bundesland,
        onRestart: () => ref.invalidate(quizControllerProvider(bundesland)),
      );
    }

    // Ladescreen
    if (quizState.status == QuizStatus.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Fehler
    if (quizState.error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                Text(quizState.error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(quizControllerProvider(bundesland)),
                  child: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final q = quizState.currentQuestion;
    if (q == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(
          '${quizState.currentIndex + 1} / ${quizState.questions.length}',
        ),
        actions: [
          _TimerBadge(seconds: quizState.secondsRemaining),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Progress
          LinearProgressIndicator(
            value: (quizState.currentIndex + 1) / quizState.questions.length,
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
                  const SizedBox(height: 8),
                  Text(q.text, style: AppTextStyles.headlineMedium),
                  const SizedBox(height: 32),
                  ...List.generate(
                    q.options.length,
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AnswerButton(
                        text: q.options[i],
                        answerState: _resolveAnswerState(
                          index: i,
                          selected: quizState.selectedAnswer,
                          correct: q.correctIndex,
                          isAnswered: quizState.isAnswered,
                        ),
                        onTap: () => controller.selectAnswer(i),
                      ),
                    ),
                  ),
                  if (quizState.isAnswered && q.explanation != null) ...[
                    const SizedBox(height: 16),
                    _ExplanationCard(text: q.explanation!),
                  ],
                ],
              ),
            ),
          ),
          if (quizState.isAnswered)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: FilledButton(
                  onPressed: controller.next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    quizState.isLastQuestion ? 'Auswerten' : 'Weiter',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _AnswerButtonState _resolveAnswerState({
    required int index,
    required int? selected,
    required int correct,
    required bool isAnswered,
  }) {
    if (!isAnswered) return _AnswerButtonState.none;
    if (index == correct) return _AnswerButtonState.correct;
    if (index == selected) return _AnswerButtonState.wrong;
    return _AnswerButtonState.none;
  }
}

// ── Timer-Badge ───────────────────────────────────────────────────────────

class _TimerBadge extends StatelessWidget {
  final int seconds;
  const _TimerBadge({required this.seconds});

  Color _color() {
    if (seconds > 60) return AppColors.primary;
    if (seconds > 20) return Colors.orange;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    final label =
        '$minutes:${secs.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color().withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color()),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 16, color: _color()),
          const SizedBox(width: 4),
          Text(label,
              style: AppTextStyles.labelLarge.copyWith(color: _color())),
        ],
      ),
    );
  }
}

// ── Antwort-Button ─────────────────────────────────────────────────────────

enum _AnswerButtonState { none, correct, wrong }

class _AnswerButton extends StatelessWidget {
  final String text;
  final _AnswerButtonState answerState;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.text,
    required this.answerState,
    required this.onTap,
  });

  Color _bgColor(BuildContext context) {
    switch (answerState) {
      case _AnswerButtonState.correct:
        return AppColors.success.withValues(alpha: 0.15);
      case _AnswerButtonState.wrong:
        return AppColors.error.withValues(alpha: 0.15);
      case _AnswerButtonState.none:
        return Theme.of(context).colorScheme.surface;
    }
  }

  Color _borderColor(BuildContext context) {
    switch (answerState) {
      case _AnswerButtonState.correct:
        return AppColors.success;
      case _AnswerButtonState.wrong:
        return AppColors.error;
      case _AnswerButtonState.none:
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
            if (answerState == _AnswerButtonState.correct)
              const Icon(Icons.check_circle, color: AppColors.success),
            if (answerState == _AnswerButtonState.wrong)
              const Icon(Icons.cancel, color: AppColors.error),
          ],
        ),
      ),
    );
  }
}

// ── Erklärungs-Card ────────────────────────────────────────────────────────

class _ExplanationCard extends StatelessWidget {
  final String text;
  const _ExplanationCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: AppTextStyles.bodyMedium),
          ),
        ],
      ),
    );
  }
}
