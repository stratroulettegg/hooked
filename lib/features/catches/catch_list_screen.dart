import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/h_scroll_with_hint.dart';
import '../../shared/widgets/swipe_to_delete.dart';
import '../onboarding/onboarding_checklist.dart';
import 'catch_detail_screen.dart' show CatchDetailArgs;
import 'widgets/catch_card.dart';

// Re-Export, damit bestehende Importer (`feed_screen.dart`) weiterhin
// `import '../catches/catch_list_screen.dart' show CommunityFeedView;`
// nutzen koennen.
export 'community_feed_view.dart' show CommunityFeedView, FeedPostPage;

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

  /// Persönliche Rekord-IDs (pro Art jeweils der längste, ersatzweise schwerste).
  Set<String> _personalBestIds(List<CatchEntry> all) {
    final bestPerSpecies = <FishSpecies, CatchEntry>{};
    for (final e in all) {
      final cur = bestPerSpecies[e.species];
      if (cur == null) {
        bestPerSpecies[e.species] = e;
        continue;
      }
      // PB primär nach Länge (cm), Gewicht (g) nur als Tiebreaker.
      final curScore = (cur.lengthCm ?? 0) * 10000 + (cur.weightG ?? 0);
      final newScore = (e.lengthCm ?? 0) * 10000 + (e.weightG ?? 0);
      if (newScore > curScore) bestPerSpecies[e.species] = e;
    }
    return bestPerSpecies.values.map((e) => e.id).toSet();
  }

  /// Springt in den globalen Feed-Tab und scrollt direkt zu `postId`.
  void _jumpToFeed(String postId) {
    context.push('/feed', extra: postId);
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
          const OnboardingChecklistCard(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _ForecastPill(),
          ),
          Expanded(
            child: catchesAsync.when(
              loading: () => const _CatchSkeletonLoader(),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (catches) {
                if (catches.isEmpty) {
                  return _EmptyState(onAdd: () => context.push('/catches/add'));
                }

                // Verfügbare Köder.
                final availableLures =
                    catches
                        .map((e) => e.lure)
                        .whereType<String>()
                        .where((l) => l.trim().isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      );

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
                  filtered = filtered
                      .where((e) => e.lure == _lureFilter)
                      .toList();
                }
                if (_onlyPB) {
                  filtered = filtered
                      .where((e) => pbIds.contains(e.id))
                      .toList();
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
                      loading: () =>
                          const SliverToBoxAdapter(child: SizedBox()),
                      error: (_, __) =>
                          const SliverToBoxAdapter(child: SizedBox()),
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
                      ..._buildGroupedSlivers(
                        context,
                        grouped,
                        pbIds,
                        siblingIds,
                      )
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
                                itemBuilder: (context, i) => CatchCard(
                                  entry: filtered[i],
                                  isPB: pbIds.contains(filtered[i].id),
                                  compact: true,
                                  onJumpToFeed: _jumpToFeed,
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
                                    dismissKey: ValueKey(
                                      'catch-${filtered[i].id}',
                                    ),
                                    confirmTitle: 'Fang löschen?',
                                    confirmMessage:
                                        'Dieser Fang wird unwiderruflich gelöscht.',
                                    onDelete: () => ref
                                        .read(catchProvider.notifier)
                                        .removeCatch(filtered[i].id),
                                    child: CatchCard(
                                      entry: filtered[i],
                                      isPB: pbIds.contains(filtered[i].id),
                                      onJumpToFeed: _jumpToFeed,
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: group.entries.length,
                  itemBuilder: (context, i) => CatchCard(
                    entry: group.entries[i],
                    isPB: pbIds.contains(group.entries[i].id),
                    compact: true,
                    onJumpToFeed: _jumpToFeed,
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
                      child: CatchCard(
                        entry: group.entries[i],
                        isPB: pbIds.contains(group.entries[i].id),
                        onJumpToFeed: _jumpToFeed,
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
  int get totalWeightG => entries.fold(0, (sum, e) => sum + (e.weightG ?? 0));
}

List<_MonthGroup> _groupByMonth(List<CatchEntry> sortedDesc) {
  final groups = <_MonthGroup>[];
  for (final e in sortedDesc) {
    final y = e.caughtAt.year;
    final m = e.caughtAt.month;
    if (groups.isNotEmpty && groups.last.year == y && groups.last.month == m) {
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
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
          Expanded(child: Container(height: 1, color: c.border)),
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
                          const SnackBar(
                            content: Text('Noch keine Köder erfasst'),
                          ),
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
                        ? () => onChanged(
                            species,
                            lure,
                            onlyPB,
                            _CatchSort.dateDesc,
                          )
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

//  Empty-State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.phishing_outlined,
      title: 'Noch keine Fänge',
      description:
          'Trage deinen ersten Fang ein: Art, Köder, Foto — wir bauen dir daraus deine persönliche Statistik.',
      ctaLabel: 'Fang eintragen',
      ctaIcon: Icons.add,
      onCta: onAdd,
    );
  }
}

/// Kompakte Beißzeit-Pill, die im Logbuch oben den Predator-Index anzeigt.
/// Tap öffnet den vollen Forecast-Screen.
class _ForecastPill extends ConsumerWidget {
  const _ForecastPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final scoreAsync = ref.watch(predatorScoreProvider);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/forecast'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ApexColors.primary.withAlpha(28),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.bolt,
                  color: ApexColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: scoreAsync.when(
                  loading: () => Text(
                    'Beißzeit-Index lädt …',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  error: (_, __) => Text(
                    'Beißzeit-Index nicht verfügbar',
                    style: TextStyle(color: c.textMuted, fontSize: 13),
                  ),
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Beißzeit ${s.score}/100',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${s.label}',
                            style: const TextStyle(
                              color: ApexColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.speciesProfile.name,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: c.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════════════════════
// SKELETON LOADER
// ═══════════════════════════════════════════════════════════════════════════

class _CatchSkeletonLoader extends StatelessWidget {
  const _CatchSkeletonLoader();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _SkeletonCard(delay: Duration(milliseconds: index * 80)),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.delay});
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final base = c.surface;
    final shine = context.isDark
        ? const Color(0xFF1E2A38)
        : const Color(0xFFE8EEF4);

    return _Shimmer(
      baseColor: base,
      highlightColor: shine,
      child: Container(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero-Bild-Platzhalter (16:9)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: shine,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titel-Zeile
                  Row(
                    children: [
                      _SkeletonBox(width: 120, height: 18, color: shine),
                      const Spacer(),
                      _SkeletonBox(width: 60, height: 14, color: shine),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Untertitel
                  _SkeletonBox(width: 180, height: 12, color: shine),
                  const SizedBox(height: 12),
                  // Tags-Zeile
                  Row(
                    children: [
                      _SkeletonBox(
                        width: 64,
                        height: 22,
                        color: shine,
                        radius: 8,
                      ),
                      const SizedBox(width: 8),
                      _SkeletonBox(
                        width: 64,
                        height: 22,
                        color: shine,
                        radius: 8,
                      ),
                      const SizedBox(width: 8),
                      _SkeletonBox(
                        width: 48,
                        height: 22,
                        color: shine,
                        radius: 8,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: delay).fadeIn(duration: 300.ms);
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.color,
    this.radius = 6,
  });
  final double width;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({
    required this.child,
    required this.baseColor,
    required this.highlightColor,
  });
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(
      begin: -1.5,
      end: 2.5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0.0, 0.5, 1.0],
            colors: [widget.baseColor, widget.highlightColor, widget.baseColor],
            transform: _SlidingGradientTransform(_anim.value),
          ).createShader(bounds),
          child: child!,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);
  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}

