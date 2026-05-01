import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import 'water_days_providers.dart';

/// Übersicht "Tage am Wasser" — rein lokal.
class WaterDaysScreen extends ConsumerWidget {
  const WaterDaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final summary = ref.watch(waterDaysSummaryProvider);
    final days = ref.watch(waterDaysProvider);
    final goalAsync = ref.watch(yearGoalProvider);
    final goal = goalAsync.valueOrNull ?? 50;

    final today = DateTime.now();
    final isMarkedToday = days.any(
      (d) =>
          d.date.year == today.year &&
          d.date.month == today.month &&
          d.date.day == today.day,
    );

    return Scaffold(
      appBar: const ApexAppBar(),
      bottomNavigationBar: const AppBottomNav(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context, ref),
        backgroundColor: ApexColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Tag am Wasser markieren',
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          // Hero
          _CounterCard(
            count: summary.daysThisYear,
            year: summary.year,
            goal: goal,
            isMarkedToday: isMarkedToday,
            onEditGoal: () => _editGoal(context, ref, goal),
          ),
          const SizedBox(height: 16),

          // Streaks (zwei Zeilen, jeweils gleichhöchsten Kacheln)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.local_fire_department,
                    label: 'Aktuell',
                    value: summary.currentStreakDays > 0
                        ? '${summary.currentStreakDays} Tage'
                        : '–',
                    hint: summary.currentStreakWeeks > 1
                        ? '${summary.currentStreakWeeks} Wochen in Folge'
                        : ' ',
                    color: ApexColors.strike,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.emoji_events,
                    label: 'Längster Streak',
                    value: summary.longestStreakDays > 0
                        ? '${summary.longestStreakDays} Tage'
                        : '–',
                    hint: ' ',
                    color: ApexColors.scoreMid,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatTile(
            icon: Icons.calendar_today,
            label: 'Gesamt',
            value: '${summary.totalDays}',
            hint: summary.firstDay != null
                ? 'seit ${AppDateFormats.dayMonthYear.format(summary.firstDay!)}'
                : ' ',
            color: ApexColors.primary,
          ),
          const SizedBox(height: 24),

          // Liste der Tage
          if (days.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Noch keine Tage am Wasser markiert.\n'
                  'Tippe auf das Plus oder erfasse einen Fang.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary),
                ),
              ),
            )
          else ...[
            Text(
              'TAGE AM WASSER',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            for (final d in days.take(120)) _DayTile(day: d),
            if (days.length > 120)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '+ ${days.length - 120} weitere',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final c = ApexColors.of(context);
    final today = DateTime.now();
    final isMarkedToday = ref
        .read(manualWaterDaysProvider.notifier)
        .contains(today);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isMarkedToday ? Icons.check_circle : Icons.today,
                color: ApexColors.primary,
              ),
              title: Text(
                isMarkedToday ? 'Heute (bereits markiert)' : 'Heute markieren',
              ),
              subtitle: Text(AppDateFormats.weekdayDate.format(today)),
              enabled: !isMarkedToday,
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(manualWaterDaysProvider.notifier).add(today);
              },
            ),
            ListTile(
              leading: Icon(Icons.calendar_month, color: ApexColors.primary),
              title: const Text('Anderes Datum wählen…'),
              subtitle: const Text('Für nachgetragene Tage am Wasser'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickDateAndAdd(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateAndAdd(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Tag am Wasser markieren',
    );
    if (picked == null) return;
    await ref.read(manualWaterDaysProvider.notifier).add(picked);
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final ctrl = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jahresziel'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Tage am Wasser',
            hintText: 'z.B. 50',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(yearGoalProvider.notifier).setGoal(result);
    }
  }
}

// ─── Hero Counter mit Fortschrittsring ──────────────────────────────────────

class _CounterCard extends StatelessWidget {
  const _CounterCard({
    required this.count,
    required this.year,
    required this.goal,
    required this.isMarkedToday,
    required this.onEditGoal,
  });

  final int count;
  final int year;
  final int goal;
  final bool isMarkedToday;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final progress = goal > 0 ? (count / goal).clamp(0.0, 1.0) : 0.0;
    final remaining = math.max(0, goal - count);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ApexColors.primary.withAlpha(50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ring
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 9,
                    backgroundColor: c.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation(
                      ApexColors.primary,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        height: 1,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      'von $goal',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count Tage',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  'am Wasser in $year',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
                const SizedBox(height: 8),
                if (remaining > 0)
                  Text(
                    'Noch $remaining bis zum Ziel',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    'Ziel erreicht 🎉',
                    style: TextStyle(
                      fontSize: 12,
                      color: ApexColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEditGoal,
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        label: Text('Ziel: $goal Tage'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.textPrimary,
                          side: BorderSide(color: c.border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isMarkedToday) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: ApexColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Heute markiert',
                        style: TextStyle(
                          fontSize: 11,
                          color: ApexColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Tile ──────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: c.textMuted,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          if (hint != null)
            Text(hint!, style: TextStyle(fontSize: 11, color: c.textMuted)),
        ],
      ),
    );
  }
}

// ─── Day Tile ───────────────────────────────────────────────────────────────

class _DayTile extends ConsumerWidget {
  const _DayTile({required this.day});
  final WaterDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final chips = <Widget>[];
    if (day.hasCatch) {
      chips.add(_SourceChip(label: 'Fang', color: ApexColors.primary));
    }
    if (day.hasTrip) {
      chips.add(_SourceChip(label: 'Trip', color: ApexColors.scoreMid));
    }
    if (day.isManual) {
      chips.add(_SourceChip(label: 'Manuell', color: c.textMuted));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onLongPress: day.isManual
              ? () => _confirmRemoveManual(context, ref)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.water_drop, size: 18, color: ApexColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppDateFormats.weekdayDate.format(day.date),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Wrap(spacing: 6, children: chips),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveManual(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manuelle Markierung löschen?'),
        content: Text(
          day.isManualOnly
              ? 'Dieser Tag wird vollständig aus der Liste entfernt.'
              : 'Die manuelle Markierung wird entfernt. Fang/Trip an diesem Tag bleibt erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ApexColors.strike),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(manualWaterDaysProvider.notifier).remove(day.date);
    }
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}
