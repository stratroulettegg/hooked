import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/mission.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/rank_banner.dart';
import '../../shared/widgets/apex_app_bar.dart';

class MissionsScreen extends ConsumerWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(missionProvider);

    return Scaffold(
      appBar: const ApexAppBar(),
      body: missionsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ApexColors.primary),
        ),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (missions) {
          final completed = missions.where((m) => m.isCompleted).toList();
          final active = missions.where((m) => !m.isCompleted).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // Rang-Banner
              const RankBanner(),
              const SizedBox(height: 16),

              // Köderlevel-Einstieg
              _LureLevelsEntry(),
              const SizedBox(height: 16),

              // Aktive Missionen
              if (active.isNotEmpty) ...[
                _SectionHeader('AKTIV', active.length),
                const SizedBox(height: 12),
                ...active.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MissionCard(mission: m),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Abgeschlossene Missionen
              if (completed.isNotEmpty) ...[
                _SectionHeader('ABGESCHLOSSEN', completed.length),
                const SizedBox(height: 12),
                ...completed.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MissionCard(mission: m),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.count);
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: c.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: c.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 10, color: c.textMuted),
          ),
        ),
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final isCompleted = mission.isCompleted;

    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted ? ApexColors.primary.withAlpha(80) : c.border,
        ),
      ),
      child: Row(
        children: [
          Text(mission.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mission.title,
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isCompleted
                              ? ApexColors.primary
                              : c.textPrimary,
                        ),
                      ),
                    ),
                    _TypeBadge(type: mission.type),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  mission.description,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                const SizedBox(height: 8),
                if (!isCompleted) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: mission.progressPercent,
                      backgroundColor: c.border,
                      color: ApexColors.primary,
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${mission.progress} / ${mission.goal}',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                      Text(
                        '+${mission.pointsReward} Pkt.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: ApexColors.scoreMid,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: ApexColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Abgeschlossen',
                        style: TextStyle(
                          fontSize: 11,
                          color: ApexColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '+${mission.pointsReward} Pkt.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: ApexColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final MissionType type;

  Color get _color {
    switch (type) {
      case MissionType.daily:
        return const Color(0xFF64B5F6);
      case MissionType.weekly:
        return ApexColors.scoreMid;
      case MissionType.seasonal:
        return const Color(0xFF81C784);
      case MissionType.achievement:
        return ApexColors.strike;
    }
  }

  String get _label {
    switch (type) {
      case MissionType.daily:
        return 'TÄGLICH';
      case MissionType.weekly:
        return 'WOCHE';
      case MissionType.seasonal:
        return 'SAISON';
      case MissionType.achievement:
        return 'ERFOLG';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withAlpha(80)),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 9,
          color: _color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LureLevelsEntry extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: () => context.push('/lure-levels'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ApexColors.primary.withAlpha(60)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ApexColors.primary.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: ApexColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Köderlevel',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Level deine Köder bis Stufe 10',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}
