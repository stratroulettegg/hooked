import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/services/app_paths.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/firebase/feed_service.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/h_scroll_with_hint.dart';
import '../../shared/widgets/swipe_to_delete.dart';
import 'catch_detail_screen.dart' show CatchDetailArgs;

class CatchListScreen extends ConsumerStatefulWidget {
  const CatchListScreen({super.key});

  @override
  ConsumerState<CatchListScreen> createState() => _CatchListScreenState();
}

class _CatchListScreenState extends ConsumerState<CatchListScreen> {
  FishSpecies? _speciesFilter;
  String? _lureFilter;
  bool _onlyPB = false;
  _CatchSort _sort = _CatchSort.dateDesc;
  bool _twoColumns = false;
  int _tab = 0; // 0 = Meine, 1 = Community

  /// Persönliche Rekord-IDs (pro Art jeweils der schwerste, ersatzweise längste).
  Set<String> _personalBestIds(List<CatchEntry> all) {
    final bestPerSpecies = <FishSpecies, CatchEntry>{};
    for (final e in all) {
      final cur = bestPerSpecies[e.species];
      if (cur == null) {
        bestPerSpecies[e.species] = e;
        continue;
      }
      final curScore = (cur.weightG ?? 0) * 1000 + (cur.lengthCm ?? 0);
      final newScore = (e.weightG ?? 0) * 1000 + (e.lengthCm ?? 0);
      if (newScore > curScore) bestPerSpecies[e.species] = e;
    }
    return bestPerSpecies.values.map((e) => e.id).toSet();
  }

  /// Trend-Berechnung: Anzahl Fänge im aktuellen Monat vs. Vormonat.
  ({int thisMonth, int delta}) _monthTrend(List<CatchEntry> all) {
    final now = DateTime.now();
    final thisStart = DateTime(now.year, now.month);
    final lastStart = DateTime(now.year, now.month - 1);
    var thisCount = 0;
    var lastCount = 0;
    for (final c in all) {
      if (!c.caughtAt.isBefore(thisStart)) {
        thisCount++;
      } else if (!c.caughtAt.isBefore(lastStart)) {
        lastCount++;
      }
    }
    return (thisMonth: thisCount, delta: thisCount - lastCount);
  }

  @override
  Widget build(BuildContext context) {
    final catchesAsync = ref.watch(catchProvider);
    final statsAsync = ref.watch(catchStatsProvider);

    return Scaffold(
      appBar: const ApexAppBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _FeedTabSwitch(
              value: _tab,
              onChanged: (i) {
                setState(() => _tab = i);
                // Beim Wechsel auf Community immer neu laden,
                // damit der Stream sicher neu auf die Auth-Lage greift.
                if (i == 1) {
                  ref.invalidate(feedPostsProvider);
                }
              },
            ),
          ),
          Expanded(
            child: _tab == 1
                ? const _CommunityFeedView()
                : catchesAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: ApexColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                    error: (e, _) => Center(child: Text('Fehler: $e')),
                    data: (catches) {
                      if (catches.isEmpty) {
                        return _EmptyState(
                          onAdd: () => context.push('/catches/add'),
                        );
                      }

          // Verfügbare Köder.
          final availableLures =
              catches
                  .map((e) => e.lure)
                  .whereType<String>()
                  .where((l) => l.trim().isNotEmpty)
                  .toSet()
                  .toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          // Verfügbare Arten.
          final availableSpecies =
              catches.map((e) => e.species).toSet().toList()
                ..sort((a, b) => a.displayName.compareTo(b.displayName));

          final pbIds = _personalBestIds(catches);
          final trend = _monthTrend(catches);

          var filtered = catches;
          if (_speciesFilter != null) {
            filtered = filtered
                .where((e) => e.species == _speciesFilter)
                .toList();
          }
          if (_lureFilter != null) {
            filtered = filtered.where((e) => e.lure == _lureFilter).toList();
          }
          if (_onlyPB) {
            filtered = filtered.where((e) => pbIds.contains(e.id)).toList();
          }

          // Sortierung.
          switch (_sort) {
            case _CatchSort.dateDesc:
              filtered.sort((a, b) => b.caughtAt.compareTo(a.caughtAt));
              break;
            case _CatchSort.lengthDesc:
              filtered.sort(
                (a, b) => (b.lengthCm ?? -1).compareTo(a.lengthCm ?? -1),
              );
              break;
            case _CatchSort.weightDesc:
              filtered.sort(
                (a, b) => (b.weightG ?? -1).compareTo(a.weightG ?? -1),
              );
              break;
          }

          final hasFilter =
              _speciesFilter != null || _lureFilter != null || _onlyPB;

          // ID-Liste in aktueller Filter-/Sort-Reihenfolge — wird an die
          // Detail-Ansicht durchgereicht, damit die vertikale Swipe-Navigation
          // die gleiche Reihenfolge nutzt.
          final siblingIds = [for (final e in filtered) e.id];

          // Gruppierung (nur bei Datums-Sort sinnvoll).
          final grouped = _sort == _CatchSort.dateDesc
              ? _groupByMonth(filtered)
              : null;

          return CustomScrollView(
            slivers: [
              statsAsync.when(
                data: (stats) => SliverToBoxAdapter(
                  child: _StatsHero(stats: stats, trend: trend),
                ),
                loading: () => const SliverToBoxAdapter(child: SizedBox()),
                error: (_, __) => const SliverToBoxAdapter(child: SizedBox()),
              ),
              SliverToBoxAdapter(
                child: _FilterBar(
                  species: _speciesFilter,
                  lure: _lureFilter,
                  onlyPB: _onlyPB,
                  sort: _sort,
                  twoColumns: _twoColumns,
                  availableSpecies: availableSpecies,
                  availableLures: availableLures,
                  onChanged: (s, l, pb, sort) => setState(() {
                    _speciesFilter = s;
                    _lureFilter = l;
                    _onlyPB = pb;
                    _sort = sort;
                  }),
                  onToggleColumns: () =>
                      setState(() => _twoColumns = !_twoColumns),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoFilterResults(
                    onReset: () => setState(() {
                      _speciesFilter = null;
                      _lureFilter = null;
                      _onlyPB = false;
                      _sort = _CatchSort.dateDesc;
                    }),
                  ),
                )
              else if (grouped != null)
                ..._buildGroupedSlivers(context, grouped, pbIds, siblingIds)
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: _twoColumns
                      ? SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) => _CatchCard(
                            entry: filtered[i],
                            isPB: pbIds.contains(filtered[i].id),
                            compact: true,
                            onTap: () => context.push(
                              '/catches/detail',
                              extra: CatchDetailArgs(
                                entry: filtered[i],
                                siblingIds: siblingIds,
                              ),
                            ),
                          ),
                        )
                      : SliverList.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SwipeToDelete(
                              dismissKey:
                                  ValueKey('catch-${filtered[i].id}'),
                              confirmTitle: 'Fang löschen?',
                              confirmMessage:
                                  'Dieser Fang wird unwiderruflich gelöscht.',
                              onDelete: () => ref
                                  .read(catchProvider.notifier)
                                  .removeCatch(filtered[i].id),
                              child: _CatchCard(
                                entry: filtered[i],
                                isPB: pbIds.contains(filtered[i].id),
                                onTap: () => context.push(
                                  '/catches/detail',
                                  extra: CatchDetailArgs(
                                    entry: filtered[i],
                                    siblingIds: siblingIds,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              if (hasFilter && filtered.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Center(
                      child: Text(
                        '${filtered.length} von ${catches.length} Fängen',
                        style: TextStyle(
                          fontSize: 11,
                          color: ApexColors.of(context).textMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedSlivers(
    BuildContext context,
    List<_MonthGroup> groups,
    Set<String> pbIds,
    List<String> siblingIds,
  ) {
    final slivers = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _MonthHeaderDelegate(group: group),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            g == groups.length - 1 ? 32 : 8,
          ),
          sliver: _twoColumns
              ? SliverGrid.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: group.entries.length,
                  itemBuilder: (context, i) => _CatchCard(
                    entry: group.entries[i],
                    isPB: pbIds.contains(group.entries[i].id),
                    compact: true,
                    onTap: () => context.push(
                      '/catches/detail',
                      extra: CatchDetailArgs(
                        entry: group.entries[i],
                        siblingIds: siblingIds,
                      ),
                    ),
                  ),
                )
              : SliverList.builder(
                  itemCount: group.entries.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SwipeToDelete(
                      dismissKey: ValueKey('catch-${group.entries[i].id}'),
                      confirmTitle: 'Fang löschen?',
                      confirmMessage:
                          'Dieser Fang wird unwiderruflich gelöscht.',
                      onDelete: () => ref
                          .read(catchProvider.notifier)
                          .removeCatch(group.entries[i].id),
                      child: _CatchCard(
                        entry: group.entries[i],
                        isPB: pbIds.contains(group.entries[i].id),
                        onTap: () => context.push(
                          '/catches/detail',
                          extra: CatchDetailArgs(
                            entry: group.entries[i],
                            siblingIds: siblingIds,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
    }
    return slivers;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Monatsgruppierung
// ─────────────────────────────────────────────────────────────────────────────

class _MonthGroup {
  _MonthGroup({required this.year, required this.month, required this.entries});
  final int year;
  final int month;
  final List<CatchEntry> entries;

  int get count => entries.length;
  int get totalWeightG =>
      entries.fold(0, (sum, e) => sum + (e.weightG ?? 0));
}

List<_MonthGroup> _groupByMonth(List<CatchEntry> sortedDesc) {
  final groups = <_MonthGroup>[];
  for (final e in sortedDesc) {
    final y = e.caughtAt.year;
    final m = e.caughtAt.month;
    if (groups.isNotEmpty &&
        groups.last.year == y &&
        groups.last.month == m) {
      groups.last.entries.add(e);
    } else {
      groups.add(_MonthGroup(year: y, month: m, entries: [e]));
    }
  }
  return groups;
}

const _monthNamesDe = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MonthHeaderDelegate({required this.group});
  final _MonthGroup group;

  static const double _height = 36;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = ApexColors.of(context);
    final monthLabel = _monthNamesDe[group.month - 1];
    final weight = group.totalWeightG;
    final weightLabel = weight >= 1000
        ? '${AppNum.fixed(weight / 1000, 1)} kg'
        : weight > 0
            ? '$weight g'
            : null;
    return Container(
      height: _height,
      color: c.background,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            '$monthLabel ${group.year}',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: c.border),
          ),
          const SizedBox(width: 10),
          Text(
            weightLabel != null
                ? '${group.count} · $weightLabel'
                : '${group.count}',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MonthHeaderDelegate oldDelegate) =>
      oldDelegate.group != group;
}

// ─────────────────────────────────────────────────────────────────────────────
//  StatsHero – emotionale Top-Card
// ─────────────────────────────────────────────────────────────────────────────

class _StatsHero extends StatelessWidget {
  const _StatsHero({required this.stats, required this.trend});
  final CatchStats stats;
  final ({int thisMonth, int delta}) trend;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    final pb = stats.personalBest;
    final pbValue = pb == null
        ? null
        : pb.weightG != null
            ? (pb.weightG! >= 1000
                ? '${AppNum.fixed(pb.weightG! / 1000, 1)} kg'
                : '${pb.weightG} g')
            : pb.lengthCm != null
                ? AppNum.cm(pb.lengthCm!)
                : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: c.cardShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero-Zeile: große Zahl + Trend-Pill ─────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.total}',
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 44,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: ApexColors.primary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  stats.total == 1 ? 'Fang' : 'Fänge',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              _TrendPill(trend: trend),
            ],
          ),
          const SizedBox(height: 14),
          // ── Sekundär-KPIs: PB & Top-Köder ───────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _MiniKpi(
                  icon: Icons.emoji_events,
                  iconColor: ApexColors.scoreMid,
                  label: 'PERSÖNLICHER REKORD',
                  value: pbValue ?? '–',
                  hint: pb?.species.displayName,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: c.border,
              ),
              Expanded(
                child: _MiniKpi(
                  icon: Icons.phishing,
                  iconColor: ApexColors.primary,
                  label: 'TOP KÖDER',
                  value: stats.topLure ?? '–',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendPill extends StatelessWidget {
  const _TrendPill({required this.trend});
  final ({int thisMonth, int delta}) trend;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    if (trend.thisMonth == 0 && trend.delta == 0) {
      return const SizedBox.shrink();
    }
    final isUp = trend.delta >= 0;
    final color = isUp ? ApexColors.primary : c.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up : Icons.trending_flat,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            trend.delta == 0
                ? '${trend.thisMonth} diesen Monat'
                : '${trend.delta > 0 ? '+' : ''}${trend.delta} vs. Vormonat',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.hint,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: c.textMuted,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: c.textMuted),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Filterleiste & Picker
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.species,
    required this.lure,
    required this.onlyPB,
    required this.sort,
    required this.twoColumns,
    required this.availableSpecies,
    required this.availableLures,
    required this.onChanged,
    required this.onToggleColumns,
  });

  final FishSpecies? species;
  final String? lure;
  final bool onlyPB;
  final _CatchSort sort;
  final bool twoColumns;
  final List<FishSpecies> availableSpecies;
  final List<String> availableLures;
  final void Function(
    FishSpecies? species,
    String? lure,
    bool onlyPB,
    _CatchSort sort,
  )
  onChanged;
  final VoidCallback onToggleColumns;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final hasAny =
        species != null ||
        lure != null ||
        onlyPB ||
        sort != _CatchSort.dateDesc;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: HScrollWithHint(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
          _FilterChipDropdown<FishSpecies?>(
            icon: Icons.set_meal,
            label: species?.displayName ?? 'Fischart',
            active: species != null,
            onTap: () async {
              final picked = await showModalBottomSheet<FishSpecies?>(
                context: context,
                showDragHandle: true,
                backgroundColor: c.surface,
                builder: (ctx) => _PickerSheet<FishSpecies>(
                  title: 'Fischart',
                  items: availableSpecies,
                  selected: species,
                  labelOf: (s) => '${s.emoji}  ${s.displayName}',
                ),
              );
              if (picked == null && species != null) return;
              onChanged(picked, lure, onlyPB, sort);
            },
            onClear: species != null
                ? () => onChanged(null, lure, onlyPB, sort)
                : null,
          ),
          const SizedBox(width: 8),
          _FilterChipDropdown(
            icon: Icons.phishing,
            label: lure ?? 'Köder',
            active: lure != null,
            onTap: () async {
              if (availableLures.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Noch keine Köder erfasst')),
                );
                return;
              }
              final picked = await showModalBottomSheet<String?>(
                context: context,
                showDragHandle: true,
                backgroundColor: c.surface,
                builder: (ctx) => _PickerSheet<String>(
                  title: 'Köder',
                  items: availableLures,
                  selected: lure,
                  labelOf: (s) => s,
                ),
              );
              if (picked == null && lure != null) return;
              onChanged(species, picked, onlyPB, sort);
            },
            onClear: lure != null
                ? () => onChanged(species, null, onlyPB, sort)
                : null,
          ),
          const SizedBox(width: 8),
          _FilterChipDropdown(
            icon: Icons.emoji_events,
            label: 'PB',
            active: onlyPB,
            isToggle: true,
            onTap: () => onChanged(species, lure, !onlyPB, sort),
          ),
          const SizedBox(width: 8),
          _FilterChipDropdown(
            icon: Icons.sort,
            label: sort.shortLabel,
            active: sort != _CatchSort.dateDesc,
            onTap: () async {
              final picked = await showModalBottomSheet<_CatchSort>(
                context: context,
                showDragHandle: true,
                backgroundColor: c.surface,
                builder: (ctx) => _PickerSheet<_CatchSort>(
                  title: 'Sortieren nach',
                  items: _CatchSort.values,
                  selected: sort,
                  labelOf: (s) => s.label,
                ),
              );
              if (picked == null) return;
              onChanged(species, lure, onlyPB, picked);
            },
            onClear: sort != _CatchSort.dateDesc
                ? () => onChanged(species, lure, onlyPB, _CatchSort.dateDesc)
                : null,
          ),
          if (hasAny) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () =>
                  onChanged(null, null, false, _CatchSort.dateDesc),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Zurücksetzen'),
              style: TextButton.styleFrom(
                foregroundColor: c.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _FilterChipDropdown(
            icon: Icons.grid_view,
            label: '2 Spalten',
            active: twoColumns,
            isToggle: true,
            onTap: onToggleColumns,
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

enum _CatchSort {
  dateDesc('Neueste zuerst', 'Neueste'),
  lengthDesc('Größe', 'Größe'),
  weightDesc('Gewicht', 'Gewicht');

  const _CatchSort(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}

class _FilterChipDropdown<T> extends StatelessWidget {
  const _FilterChipDropdown({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
    this.isToggle = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool isToggle;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? ApexColors.primary.withAlpha(28) : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? ApexColors.primary : c.border,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? ApexColors.primary : c.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? ApexColors.primary : c.textPrimary,
              ),
            ),
            if (isToggle) ...[
              const SizedBox(width: 4),
              Icon(
                active ? Icons.check : Icons.circle_outlined,
                size: 14,
                color: active ? ApexColors.primary : c.textMuted,
              ),
            ] else if (active && onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: ApexColors.primary),
              ),
            ] else if (!active) ...[
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 16, color: c.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.labelOf,
  });

  final String title;
  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final isSel = item == selected;
                  return ListTile(
                    title: Text(labelOf(item)),
                    trailing: isSel
                        ? const Icon(Icons.check, color: ApexColors.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, item),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NoFilterResults extends StatelessWidget {
  const _NoFilterResults({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.filter_alt_off, size: 48, color: c.textMuted),
          const SizedBox(height: 12),
          Text(
            'Keine Fänge passen zum Filter',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Filter zurücksetzen'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Catch-Card – einheitliche Hero-Card: 16:9 Foto oben, Daten darunter
// ─────────────────────────────────────────────────────────────────────────────

IconData _timeOfDayIcon(DateTime dt) {
  final h = dt.hour;
  if (h >= 5 && h < 9) return Icons.wb_twilight;
  if (h >= 9 && h < 18) return Icons.wb_sunny_outlined;
  if (h >= 18 && h < 21) return Icons.nights_stay_outlined;
  return Icons.dark_mode_outlined;
}

class _CatchCard extends ConsumerWidget {
  const _CatchCard({
    required this.entry,
    required this.onTap,
    this.isPB = false,
    this.compact = false,
  });
  final CatchEntry entry;
  final VoidCallback onTap;
  final bool isPB;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final spots = ref.watch(spotProvider).valueOrNull ?? const [];
    final spot = entry.spotId != null
        ? spots.where((s) => s.id == entry.spotId).firstOrNull
        : null;
    final hasPhoto = AppPaths.photoFile(entry.photoPath) != null;

    // Rechte Card-Ecken werden während des Swipes eckig — sonst stehen
    // sie vor dem roten Lösch-Feld und erzeugen Eck-Lücken.
    final swiping = SwipeAffordance.of(context);
    final cardRadius = swiping
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            bottomLeft: Radius.circular(18),
          )
        : BorderRadius.circular(18);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: cardRadius,
          border: Border.all(
            color: isPB ? ApexColors.scoreMid.withAlpha(160) : c.border,
            width: isPB ? 1.6 : 1,
          ),
          boxShadow: context.isDark
              ? []
              : [
                  BoxShadow(
                    color: isPB
                        ? ApexColors.scoreMid.withAlpha(40)
                        : c.cardShadow,
                    blurRadius: isPB ? 14 : 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: cardRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero-Bild (16:9), reines Foto ohne Text-Overlays ─────────
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LayoutBuilder(
                      builder: (ctx, constraints) {
                        final file = AppPaths.photoFile(entry.photoPath);
                        if (file != null) {
                          final cacheW = (constraints.maxWidth *
                                  MediaQuery.devicePixelRatioOf(ctx))
                              .round();
                          return Image.file(
                            file,
                            fit: BoxFit.cover,
                            cacheWidth: cacheW,
                          );
                        }
                        final asset = entry.species.imageAsset;
                        if (asset != null) {
                          return Image.asset(
                            asset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _emojiBackground(entry.species.emoji),
                          );
                        }
                        return _emojiBackground(entry.species.emoji);
                      },
                    ),
                    // Top-Right: PB-Badge (Gold)
                    if (isPB)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: ApexColors.scoreMid,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(70),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events,
                                  size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'PB',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Top-Left: Hinweis bei fehlendem Foto
                    if (!hasPhoto)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(70),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_not_supported_outlined,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Kein Foto',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Header-Zeile: Art + Datum/Uhrzeit ────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 14, compact ? 9 : 12, compact ? 10 : 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.species.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: compact ? 16 : 19,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppDateFormats.dayMonthYearShort
                                .format(entry.caughtAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textMuted,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _timeOfDayIcon(entry.caughtAt),
                                size: 12,
                                color: c.textSecondary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                AppDateFormats.hourMinute
                                    .format(entry.caughtAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // ── Metriken-Badges ────────────────────────────────────────
              if (entry.weightG != null || entry.lengthCm != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 14, 8, compact ? 10 : 14, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (entry.weightG != null)
                        _MetricBadge(
                          text: entry.weightG! >= 1000
                              ? AppNum.kg(entry.weightG!)
                              : '${entry.weightG} g',
                          color: ApexColors.primary,
                          filled: true,
                        ),
                      if (entry.lengthCm != null)
                        _MetricBadge(
                          text: entry.lengthCm! % 1 == 0
                              ? '${entry.lengthCm!.toInt()} cm'
                              : AppNum.cm(entry.lengthCm!),
                          color: c.textSecondary,
                          filled: false,
                        ),
                    ],
                  ),
                ),
              // ── Footer: Köder + Spot (immer da, sonst Mini-Hint) ────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 14, 8, compact ? 10 : 14, compact ? 10 : 12),
                child: Wrap(
                  spacing: compact ? 8 : 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (entry.lure != null)
                      _FooterChip(
                        icon: Icons.phishing,
                        text: compact
                            ? entry.lure!
                            : entry.retrieveStyles.isNotEmpty
                                ? '${entry.lure!} · ${entry.retrieveStyles.first.displayName}'
                                : entry.lure!,
                        iconColor: c.textMuted,
                      ),
                    if (spot != null && !compact)
                      _FooterChip(
                        icon: Icons.place,
                        text: spot.name,
                        iconColor: ApexColors.primary,
                      ),
                    if (compact)
                      _FooterChip(
                        icon: _timeOfDayIcon(entry.caughtAt),
                        text: AppDateFormats.dayMonthYearShort
                            .format(entry.caughtAt),
                        iconColor: c.textSecondary,
                      ),
                    if (entry.lure == null && spot == null && !compact)
                      Text(
                        'Keine weiteren Angaben',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: c.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _emojiBackground(String emoji) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          ApexColors.primary.withAlpha(40),
          ApexColors.primary.withAlpha(12),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Text(emoji, style: const TextStyle(fontSize: 64)),
    ),
  );
}

class _FooterChip extends StatelessWidget {
  const _FooterChip({
    required this.icon,
    required this.text,
    required this.iconColor,
  });
  final IconData icon;
  final String text;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.text,
    required this.color,
    required this.filled,
  });
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withAlpha(22) : c.surfaceVariant,
        borderRadius: BorderRadius.circular(7),
        border: filled ? null : Border.all(color: c.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: filled ? color : color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty-State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.phishing,
            size: 64,
            color: ApexColors.of(context).textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'Noch keine Fänge',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: ApexColors.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tippe auf + um deinen ersten Fang einzutragen',
            style: TextStyle(color: ApexColors.of(context).textMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Fang eintragen'),
          ),
        ],
      ),
    );
  }
}

/// Segmented-Switch zwischen "Meine Fänge" und "Community-Feed".
class _FeedTabSwitch extends StatelessWidget {
  const _FeedTabSwitch({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    Widget tab(int i, String label, IconData icon) {
      final active = i == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: active ? ApexColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active ? Colors.white : c.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : c.textPrimary,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          tab(0, 'Meine', Icons.person_outline),
          tab(1, 'Community', Icons.public),
        ],
      ),
    );
  }
}

/// Zeigt den globalen Community-Feed.
class _CommunityFeedView extends ConsumerWidget {
  const _CommunityFeedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: c.textMuted),
              const SizedBox(height: 12),
              Text(
                'Nur für eingeloggte Angler:innen',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Melde dich an, um den Community-Feed zu sehen und eigene Fänge zu teilen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.push('/auth'),
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Anmelden'),
              ),
            ],
          ),
        ),
      );
    }
    final feedAsync = ref.watch(feedPostsProvider);
    return feedAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: ApexColors.primary,
          strokeWidth: 2,
        ),
      ),
      error: (e, _) {
        // Permission-Denied tritt typisch beim Logout/Login-Wechsel auf,
        // bevor der Stream auf den neuen Auth-State umgeschwenkt ist.
        // Statt einer rohen Exception zeigen wir einen freundlichen Hinweis.
        final msg = e.toString().toLowerCase();
        final isPermission = msg.contains('permission-denied') ||
            msg.contains('permission_denied');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPermission ? Icons.lock_outline : Icons.cloud_off,
                  size: 56,
                  color: c.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  isPermission
                      ? 'Feed gerade nicht verfügbar'
                      : 'Verbindungsproblem',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isPermission
                      ? 'Bitte einen Moment warten oder die App neu starten.'
                      : 'Prüfe deine Internetverbindung und versuche es erneut.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(feedPostsProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        );
      },
      data: (posts) {
        if (posts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public, size: 56, color: c.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Noch keine Community-Fänge',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Teile deinen ersten Fang im Feed:\nbeim Eintragen den Schalter "In Community-Feed teilen" aktivieren.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        // Vertikaler Vollbild-Pager – analog zur Catch-Detail-Ansicht.
        return PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: posts.length,
          itemBuilder: (_, i) => _FeedPostPage(post: posts[i]),
        );
      },
    );
  }
}

/// Eine Feed-Seite im Stil der eigenen Detailansicht: Foto als Hero,
/// halbtransparentes Blur-Sheet mit den Details darüber.
class _FeedPostPage extends StatefulWidget {
  const _FeedPostPage({required this.post});

  final FeedPost post;

  @override
  State<_FeedPostPage> createState() => _FeedPostPageState();
}

class _FeedPostPageState extends State<_FeedPostPage> {
  bool _expanded = false;

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tg.';
    return AppDateFormats.dayMonthYearShort.format(when);
  }

  FishSpecies? _species() {
    for (final s in FishSpecies.values) {
      if (s.name == widget.post.species) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final post = widget.post;
    final species = _species();
    final speciesLabel = species?.displayName ?? post.species;
    final hasPhoto = post.photoUrl != null && post.photoUrl!.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final collapsedH = maxH * 0.32;
        final expandedH = maxH * 0.95;
        final sheetH = _expanded ? expandedH : collapsedH;

        return Stack(
          children: [
            // Hero: Netz-Foto oder Fallback-Gradient mit Lexikon-Asset.
            Positioned.fill(
              child: _FeedHeroBackdrop(
                photoUrl: hasPhoto ? post.photoUrl : null,
                speciesAsset: species?.imageAsset,
                speciesLabel: speciesLabel,
              ),
            ),

            // Blur-Sheet mit Details.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: sheetH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: ColoredBox(
                      color: c.background.withAlpha(60),
                      child: Column(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Center(
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      width: _expanded ? 56 : 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: _expanded
                                            ? ApexColors.primary.withAlpha(180)
                                            : c.border,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline:
                                              TextBaseline.alphabetic,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                speciesLabel,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontFamily: 'Rajdhani',
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.05,
                                                  letterSpacing: 0.3,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                            ),
                                            if (post.weightG != null) ...[
                                              const SizedBox(width: 10),
                                              Text(
                                                AppNum.kg(post.weightG!),
                                                style: const TextStyle(
                                                  fontFamily: 'Rajdhani',
                                                  fontSize: 22,
                                                  color: ApexColors.primary,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (post.lengthCm != null) ...[
                                        Text(
                                          '${post.lengthCm!.toStringAsFixed(0)} cm',
                                          style: TextStyle(
                                            fontFamily: 'Rajdhani',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: c.textSecondary,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        _MetaDotMini(color: c.textMuted),
                                      ],
                                      Icon(
                                        Icons.access_time,
                                        size: 13,
                                        color: c.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          _relativeTime(post.createdAt),
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'Rajdhani',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (post.waterBodyName != null &&
                                      post.waterBodyName!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.water,
                                          size: 13,
                                          color: c.textMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            post.waterBodyName!,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Rajdhani',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              physics: _expanded
                                  ? const ClampingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _FeedAuthorRow(post: post),
                                      const SizedBox(height: 12),
                                      _FeedDetailsCard(post: post),
                                      const SizedBox(height: 24),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetaDotMini extends StatelessWidget {
  const _MetaDotMini({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _FeedHeroBackdrop extends StatelessWidget {
  const _FeedHeroBackdrop({
    required this.photoUrl,
    required this.speciesAsset,
    required this.speciesLabel,
  });

  final String? photoUrl;
  final String? speciesAsset;
  final String speciesLabel;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    if (photoUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            photoUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return ColoredBox(
                color: c.background,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: ApexColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) =>
                _FallbackHero(asset: speciesAsset, label: speciesLabel),
          ),
          // Sanftes Vignetten-Gradient für Lesbarkeit.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
        ],
      );
    }
    return _FallbackHero(asset: speciesAsset, label: speciesLabel);
  }
}

class _FallbackHero extends StatelessWidget {
  const _FallbackHero({required this.asset, required this.label});
  final String? asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.surface, c.background],
        ),
      ),
      alignment: Alignment.center,
      child: asset != null
          ? Opacity(
              opacity: 0.6,
              child: Image.asset(asset!, height: 220, fit: BoxFit.contain),
            )
          : Icon(Icons.image_not_supported, size: 64, color: c.textMuted),
    );
  }
}

class _FeedAuthorRow extends StatelessWidget {
  const _FeedAuthorRow({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: c.border,
          backgroundImage:
              (post.userPhotoUrl != null && post.userPhotoUrl!.isNotEmpty)
                  ? NetworkImage(post.userPhotoUrl!)
                  : null,
          child: (post.userPhotoUrl == null || post.userPhotoUrl!.isEmpty)
              ? Icon(Icons.person, size: 20, color: c.textMuted)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.userName?.isNotEmpty == true
                    ? post.userName!
                    : 'Angler:in',
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                AppDateFormats.dayMonthYearHourMinute.format(post.caughtAt),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedDetailsCard extends StatelessWidget {
  const _FeedDetailsCard({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final items = <(IconData, String, String)>[];
    if (post.weightG != null) {
      items.add((Icons.monitor_weight_outlined, 'Gewicht', AppNum.kg(post.weightG!)));
    }
    if (post.lengthCm != null) {
      items.add((Icons.straighten, 'Länge', '${post.lengthCm!.toStringAsFixed(0)} cm'));
    }
    if (post.lure != null && post.lure!.isNotEmpty) {
      final lureText = post.lureColor?.isNotEmpty == true
          ? '${post.lure} · ${post.lureColor}'
          : post.lure!;
      items.add((Icons.set_meal_outlined, 'Köder', lureText));
    }
    if (post.waterBodyName != null && post.waterBodyName!.isNotEmpty) {
      items.add((Icons.water, 'Gewässer', post.waterBodyName!));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface.withAlpha(180),
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(height: 1, color: c.border),
              ),
            Row(
              children: [
                Icon(items[i].$1, size: 16, color: c.textMuted),
                const SizedBox(width: 10),
                SizedBox(
                  width: 80,
                  child: Text(
                    items[i].$2,
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i].$3,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
