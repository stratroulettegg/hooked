import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../onboarding_controller.dart';

class OnboardingBundeslandScreen extends ConsumerWidget {
  const OnboardingBundeslandScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref
        .watch(onboardingControllerProvider.select((s) => s.selectedBundesland));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dein Bundesland'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(
              'Wähle dein Bundesland.\nDie Prüfungsfragen werden darauf abgestimmt.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _SectionLabel('Verfügbar'),
                ...AppConstants.mvpBundeslaender.map(
                  (bl) => _BundeslandTile(
                    bundesland: bl,
                    isSelected: selected == bl,
                    isAvailable: true,
                    onTap: () => ref
                        .read(onboardingControllerProvider.notifier)
                        .selectBundesland(bl),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionLabel('Demnächst'),
                ...AppConstants.allBundeslaender
                    .where((bl) =>
                        !AppConstants.mvpBundeslaender.contains(bl))
                    .map(
                      (bl) => _BundeslandTile(
                        bundesland: bl,
                        isSelected: false,
                        isAvailable: false,
                        onTap: null,
                      ),
                    ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(isEnabled: selected != null),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelLarge.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _BundeslandTile extends StatelessWidget {
  final String bundesland;
  final bool isSelected;
  final bool isAvailable;
  final VoidCallback? onTap;

  const _BundeslandTile({
    required this.bundesland,
    required this.isSelected,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 2 : 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onTap,
        enabled: isAvailable,
        title: Text(
          bundesland,
          style: TextStyle(
            color: isAvailable ? null : Theme.of(context).disabledColor,
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: AppColors.primary)
            : isAvailable
                ? null
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Bald',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  final bool isEnabled;
  const _BottomBar({required this.isEnabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: FilledButton(
          onPressed: isEnabled
              ? () => context.go(Routes.onboardingGoal)
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text('Weiter'),
        ),
      ),
    );
  }
}
