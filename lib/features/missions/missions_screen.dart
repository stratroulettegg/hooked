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
          // Gruppieren nach Typ — Reihenfolge ist die UI-Reihenfolge.
          final daily = missions
              .where((m) => m.type == MissionType.daily)
              .toList();
          final weekly = missions
              .where((m) => m.type == MissionType.weekly)
              .toList();
          final seasonal = missions
              .where((m) => m.type == MissionType.seasonal)
              .toList();
          final achievements = missions
              .where((m) => m.type == MissionType.achievement)
              .toList();

          // Achievements: aktiv (mit Fortschritt > 0 zuerst) vor abgeschlossen.
          int achRank(Mission m) {
            if (m.isCompleted) return 2;
            if (m.progress > 0) return 0;
            return 1;
          }

          achievements.sort((a, b) {
            final r = achRank(a).compareTo(achRank(b));
            if (r != 0) return r;
            return b.progressPercent.compareTo(a.progressPercent);
          });

          final now = DateTime.now();
          final dailyEnd = MissionSeed.currentDayEnd(now);
          final weeklyEnd = MissionSeed.currentWeekEnd(now);
          final seasonEnd = MissionSeed.currentSeasonEnd(now);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const RankBanner(),
              const SizedBox(height: 16),
              _LureLevelsEntry(),
              const SizedBox(height: 20),

              // Heute
              if (daily.isNotEmpty) ...[
                _MissionGroupHeader(
                  title: 'HEUTE',
                  subtitle: _formatRemaining(now, dailyEnd, granularity: 'h'),
                  color: const Color(0xFF64B5F6),
                  icon: Icons.wb_sunny_rounded,
                  doneCount: daily.where((m) => m.isCompleted).length,
                  totalCount: daily.length,
                ),
                const SizedBox(height: 10),
                ...daily.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MissionCard(mission: m),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Diese Woche
              if (weekly.isNotEmpty) ...[
                _MissionGroupHeader(
                  title: 'DIESE WOCHE',
                  subtitle: _formatRemaining(now, weeklyEnd, granularity: 'd'),
                  color: ApexColors.scoreMid,
                  icon: Icons.calendar_view_week_rounded,
                  doneCount: weekly.where((m) => m.isCompleted).length,
                  totalCount: weekly.length,
                ),
                const SizedBox(height: 10),
                ...weekly.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MissionCard(mission: m),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Quartal
              if (seasonal.isNotEmpty) ...[
                _MissionGroupHeader(
                  title: 'QUARTAL',
                  subtitle: _formatRemaining(now, seasonEnd, granularity: 'd'),
                  color: const Color(0xFF81C784),
                  icon: Icons.eco_rounded,
                  doneCount: seasonal.where((m) => m.isCompleted).length,
                  totalCount: seasonal.length,
                ),
                const SizedBox(height: 10),
                ...seasonal.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MissionCard(mission: m),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Erfolge
              if (achievements.isNotEmpty) ...[
                _MissionGroupHeader(
                  title: 'ERFOLGE',
                  subtitle: 'Sammelbar — laufen nicht ab',
                  color: ApexColors.strike,
                  icon: Icons.emoji_events_rounded,
                  doneCount: achievements.where((m) => m.isCompleted).length,
                  totalCount: achievements.length,
                ),
                const SizedBox(height: 10),
                ...achievements.map(
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

  static String _formatRemaining(
    DateTime now,
    DateTime end, {
    required String granularity,
  }) {
    final diff = end.difference(now);
    if (diff.isNegative) return 'läuft gleich aus';
    if (granularity == 'h') {
      final h = diff.inHours;
      if (h >= 1) return 'noch $h h';
      final m = diff.inMinutes;
      return 'noch $m min';
    }
    final d = diff.inDays;
    if (d >= 1) return 'noch $d Tag${d == 1 ? '' : 'e'}';
    final h = diff.inHours;
    return 'noch $h h';
  }
}

class _MissionGroupHeader extends StatelessWidget {
  const _MissionGroupHeader({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.doneCount,
    required this.totalCount,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final int doneCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final pct = totalCount == 0 ? 0.0 : doneCount / totalCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withAlpha(38),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$doneCount / $totalCount',
                      style: TextStyle(fontSize: 10, color: c.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 3,
                        backgroundColor: c.border,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ],
              ),
            ],
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
                    Text(
                      '+${mission.pointsReward}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isCompleted
                            ? ApexColors.primary
                            : ApexColors.scoreMid,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                  Text(
                    '${mission.progress} / ${mission.goal}',
                    style: TextStyle(fontSize: 11, color: c.textMuted),
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
