import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/catch_thumb.dart';
import '../catches/catch_detail_screen.dart';

/// "Persönliche Rekorde" — pro Art der schwerste & längste Fang plus
/// einige Gesamt-Highlights über alle Fänge.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final catchesAsync = ref.watch(catchProvider);
    final spots = ref.watch(spotProvider).valueOrNull ?? const <FishingSpot>[];

    return Scaffold(
      appBar: const ApexAppBar(),
      body: catchesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: ApexColors.primary,
            strokeWidth: 2,
          ),
        ),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (catches) {
          if (catches.isEmpty) {
            return _EmptyState(onAdd: () => context.go('/catches/add'));
          }

          final spotById = {for (final s in spots) s.id: s};

          // Pro Art den schwersten und längsten Fang ermitteln.
          final perSpecies = <FishSpecies, _SpeciesRecords>{};
          for (final e in catches) {
            final cur = perSpecies[e.species] ?? _SpeciesRecords.empty();
            perSpecies[e.species] = cur.consider(e);
          }
          final speciesEntries = perSpecies.entries.toList()
            ..sort((a, b) {
              // Arten mit beidem (Gewicht & Länge) zuerst, dann nach Gewicht.
              final wa = a.value.heaviest?.weightG ?? 0;
              final wb = b.value.heaviest?.weightG ?? 0;
              if (wb != wa) return wb.compareTo(wa);
              final la = a.value.longest?.lengthCm ?? 0;
              final lb = b.value.longest?.lengthCm ?? 0;
              return lb.compareTo(la);
            });

          // Globale Rekorde
          CatchEntry? heaviest;
          CatchEntry? longest;
          for (final e in catches) {
            if ((e.weightG ?? 0) > (heaviest?.weightG ?? 0)) heaviest = e;
            if ((e.lengthCm ?? 0) > (longest?.lengthCm ?? 0)) longest = e;
          }

          final speciesCount = perSpecies.length;
          final totalCatches = catches.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              // Hero-Card: Übersicht
              _OverviewCard(
                totalCatches: totalCatches,
                speciesCount: speciesCount,
                heaviest: heaviest,
                longest: longest,
              ),
              const SizedBox(height: 24),

              Text(
                'PRO ART',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 8),

              for (final entry in speciesEntries) ...[
                _SpeciesSection(
                  species: entry.key,
                  records: entry.value,
                  spotById: spotById,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SpeciesRecords {
  final CatchEntry? heaviest;
  final CatchEntry? longest;
  const _SpeciesRecords({this.heaviest, this.longest});

  factory _SpeciesRecords.empty() => const _SpeciesRecords();

  _SpeciesRecords consider(CatchEntry e) {
    CatchEntry? h = heaviest;
    CatchEntry? l = longest;
    if (e.weightG != null && (e.weightG! > (h?.weightG ?? -1))) h = e;
    if (e.lengthCm != null && (e.lengthCm! > (l?.lengthCm ?? -1))) l = e;
    // Falls nirgends gesetzt: wenigstens irgendeinen Fang als Platzhalter merken.
    if (h == null && l == null) {
      return _SpeciesRecords(heaviest: e, longest: e);
    }
    return _SpeciesRecords(heaviest: h, longest: l);
  }
}

// ─── Overview Card ───────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.totalCatches,
    required this.speciesCount,
    required this.heaviest,
    required this.longest,
  });

  final int totalCatches;
  final int speciesCount;
  final CatchEntry? heaviest;
  final CatchEntry? longest;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ApexColors.primary.withAlpha(36),
            ApexColors.primary.withAlpha(8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ApexColors.primary.withAlpha(80), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: ApexColors.scoreMid,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'PERSÖNLICHE REKORDE',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MiniStat(label: 'Fänge', value: '$totalCatches'),
                ),
                _Divider(c: c),
                Expanded(
                  child: _MiniStat(label: 'Arten', value: '$speciesCount'),
                ),
                _Divider(c: c),
                Expanded(
                  child: _MiniStat(
                    label: 'Schwerster',
                    value: heaviest?.weightG != null
                        ? _formatWeight(heaviest!.weightG!)
                        : '–',
                  ),
                ),
                _Divider(c: c),
                Expanded(
                  child: _MiniStat(
                    label: 'Längster',
                    value: longest?.lengthCm != null
                        ? '${_formatLength(longest!.lengthCm!)} cm'
                        : '–',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.c});
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: c.border,
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
            color: c.textMuted,
          ),
        ),
      ],
    );
  }
}

// ─── Species Section ─────────────────────────────────────────────────────────

class _SpeciesSection extends StatelessWidget {
  const _SpeciesSection({
    required this.species,
    required this.records,
    required this.spotById,
  });

  final FishSpecies species;
  final _SpeciesRecords records;
  final Map<String, FishingSpot> spotById;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final h = records.heaviest;
    final l = records.longest;
    // Falls schwerster == längster, nur eine Karte zeigen.
    final sameCatch = h != null && l != null && h.id == l.id;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                species.displayName.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (sameCatch)
            _RecordRow(
              entry: h,
              kind: _RecordKind.combined,
              spot: h.spotId != null ? spotById[h.spotId] : null,
            )
          else ...[
            if (h != null && (h.weightG ?? 0) > 0)
              _RecordRow(
                entry: h,
                kind: _RecordKind.heaviest,
                spot: h.spotId != null ? spotById[h.spotId] : null,
              ),
            if (h != null &&
                (h.weightG ?? 0) > 0 &&
                l != null &&
                (l.lengthCm ?? 0) > 0)
              const SizedBox(height: 8),
            if (l != null && (l.lengthCm ?? 0) > 0)
              _RecordRow(
                entry: l,
                kind: _RecordKind.longest,
                spot: l.spotId != null ? spotById[l.spotId] : null,
              ),
            // Fallback, wenn weder Gewicht noch Länge gesetzt sind.
            if ((h == null || (h.weightG ?? 0) == 0) &&
                (l == null || (l.lengthCm ?? 0) == 0) &&
                h != null)
              _RecordRow(
                entry: h,
                kind: _RecordKind.combined,
                spot: h.spotId != null ? spotById[h.spotId] : null,
              ),
          ],
        ],
      ),
    );
  }
}

enum _RecordKind { heaviest, longest, combined }

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.entry,
    required this.kind,
    required this.spot,
  });

  final CatchEntry entry;
  final _RecordKind kind;
  final FishingSpot? spot;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    final (icon, label, color) = switch (kind) {
      _RecordKind.heaviest => (
        Icons.fitness_center_rounded,
        'SCHWERSTER',
        ApexColors.strike,
      ),
      _RecordKind.longest => (
        Icons.straighten_rounded,
        'LÄNGSTER',
        ApexColors.primary,
      ),
      _RecordKind.combined => (
        Icons.emoji_events_rounded,
        'BESTER',
        ApexColors.scoreMid,
      ),
    };

    final metric = switch (kind) {
      _RecordKind.heaviest =>
        entry.weightG != null ? _formatWeight(entry.weightG!) : '–',
      _RecordKind.longest =>
        entry.lengthCm != null ? '${_formatLength(entry.lengthCm!)} cm' : '–',
      _RecordKind.combined => _bestMetric(entry),
    };

    final spotLabel =
        spot?.name ??
        spot?.waterBodyName ??
        ((entry.lat != null && entry.lng != null) ? 'Pin' : null);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CatchDetailScreen(entry: entry)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CatchThumb(
                species: entry.species,
                photoPath: entry.photoPath,
                size: 56,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 13, color: color),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metric,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(entry, spotLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty ───────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_outlined, size: 56, color: c.textMuted),
            const SizedBox(height: 16),
            Text(
              'Noch keine Rekorde',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Erfasse deinen ersten Fang — dann tauchen hier deine\n'
              'persönlichen Bestleistungen pro Art auf.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Fang erfassen'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _formatWeight(int g) => AppNum.kg(g);

String _formatLength(double cm) {
  if (cm == cm.roundToDouble()) return cm.toStringAsFixed(0);
  return AppNum.fixed(cm, 1);
}

String _bestMetric(CatchEntry e) {
  if ((e.weightG ?? 0) > 0 && (e.lengthCm ?? 0) > 0) {
    return '${_formatWeight(e.weightG!)} · ${_formatLength(e.lengthCm!)} cm';
  }
  if ((e.weightG ?? 0) > 0) return _formatWeight(e.weightG!);
  if ((e.lengthCm ?? 0) > 0) return '${_formatLength(e.lengthCm!)} cm';
  return e.species.displayName;
}

String _subtitle(CatchEntry e, String? spotLabel) {
  final parts = <String>[];
  parts.add(AppDateFormats.dayMonthYear.format(e.caughtAt));
  if (spotLabel != null && spotLabel.isNotEmpty) parts.add(spotLabel);
  if (e.lure != null && e.lure!.trim().isNotEmpty) parts.add(e.lure!);
  return parts.join(' · ');
}
