import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

class QuizResultScreen extends StatelessWidget {
  final int correctCount;
  final int totalCount;
  final String bundesland;
  final VoidCallback onRestart;

  const QuizResultScreen({
    super.key,
    required this.correctCount,
    required this.totalCount,
    required this.bundesland,
    required this.onRestart,
  });

  double get _accuracy => totalCount == 0 ? 0 : correctCount / totalCount;

  String get _medal {
    if (_accuracy >= 0.9) return '🏆';
    if (_accuracy >= 0.7) return '🥈';
    if (_accuracy >= 0.5) return '🥉';
    return '🎣';
  }

  String get _headline {
    if (_accuracy >= 0.9) return 'Ausgezeichnet!';
    if (_accuracy >= 0.7) return 'Gut gemacht!';
    if (_accuracy >= 0.5) return 'Weiter so!';
    return 'Übung macht den Meister!';
  }

  int get _xpEarned {
    int xp = correctCount * AppConstants.xpPerCorrectAnswer;
    if (correctCount == totalCount) xp += AppConstants.xpPerfectRoundBonus;
    return xp;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text(_medal, style: const TextStyle(fontSize: 80)),
              const SizedBox(height: 24),
              Text(
                _headline,
                style: AppTextStyles.displayLarge
                    .copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$correctCount von $totalCount Fragen richtig',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              // Fortschrittsring
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: _accuracy,
                      strokeWidth: 12,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _accuracy >= 0.7
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                    Center(
                      child: Text(
                        '${(_accuracy * 100).round()}%',
                        style: AppTextStyles.headlineLarge
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // XP-Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      '+$_xpEarned XP',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onRestart,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Nochmal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => context.go('/home'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Home'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
