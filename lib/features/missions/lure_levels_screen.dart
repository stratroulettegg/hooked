import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/data/lure_catalog.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';

class LureLevelsScreen extends ConsumerWidget {
  const LureLevelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final catchesAsync = ref.watch(catchProvider);

    return Scaffold(
      appBar: const ApexAppBar(),
      body: catchesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ApexColors.primary),
        ),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (catches) {
          // Zählen pro Köder-Name.
          final counts = <String, int>{};
          for (final ce in catches) {
            final l = ce.lure?.trim();
            if (l == null || l.isEmpty) continue;
            counts[l] = (counts[l] ?? 0) + 1;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                'KÖDERLEVEL',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: c.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Jeder Köder levelt mit deinen Fängen. '
                'Alle $kLureCatchesPerLevel Fänge gibt es ein Level – bis Level $kLureMaxLevel.',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 20),
              for (final cat in kLureCatalog.entries) ...[
                Text(
                  cat.key.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: c.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...cat.value.map((name) {
                  final n = counts[name] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LureLevelCard(name: name, catches: n),
                  );
                }),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LureLevelCard extends StatelessWidget {
  const _LureLevelCard({required this.name, required this.catches});
  final String name;
  final int catches;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final level = lureLevelFor(catches);
    final toNext = lureToNextLevel(catches);
    final isMax = level >= kLureMaxLevel;

    // Fortschritt innerhalb des aktuellen Levels.
    final intoLevel =
        catches - (level == 0 ? 0 : (level - 1) * kLureCatchesPerLevel);
    final progress = isMax
        ? 1.0
        : (intoLevel / kLureCatchesPerLevel).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: level > 0 ? ApexColors.primary.withAlpha(60) : c.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _LevelBadge(level: level),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: c.surfaceVariant,
              valueColor: const AlwaysStoppedAnimation(ApexColors.primary),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$catches Fang${catches == 1 ? '' : 'e'}',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
              const Spacer(),
              Text(
                isMax
                    ? 'Maximum erreicht'
                    : 'Noch $toNext bis Level ${level + 1}',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final active = level > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? ApexColors.primary : c.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? ApexColors.primary : c.border),
      ),
      child: Text(
        'LVL $level',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: active ? Colors.white : c.textMuted,
        ),
      ),
    );
  }
}
