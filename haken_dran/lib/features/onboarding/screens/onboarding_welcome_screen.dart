import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Mascot
              Image.asset(
                'assets/images/hektor.png',
                height: 200,
                errorBuilder: (_, __, ___) => const _HektorPlaceholder(),
              ),
              const SizedBox(height: 32),
              Text(
                'Haken Dran!',
                style: AppTextStyles.displayLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Dein smarter Begleiter zur\nAngelprüfung.',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 3),
              _FeatureRow(
                icon: Icons.quiz_outlined,
                label: 'Über 500 Prüfungsfragen',
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.local_fire_department_outlined,
                label: 'Tägliche Streaks & XP',
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.offline_bolt_outlined,
                label: '100 % offline verfügbar',
              ),
              const Spacer(flex: 2),
              FilledButton(
                onPressed: () => context.go(Routes.onboardingBundesland),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Los geht\'s',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(width: 12),
        Text(
          label,
          style: AppTextStyles.bodyLarge.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

// Platzhalter bis echtes Hektor-Asset vorhanden ist.
class _HektorPlaceholder extends StatelessWidget {
  const _HektorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.phishing, size: 80, color: Colors.white),
    );
  }
}
