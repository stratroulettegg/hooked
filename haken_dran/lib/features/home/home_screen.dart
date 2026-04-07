import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/app_user.dart';
import '../../shared/services/user_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _HomeAppBar(userAsync: userAsync),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _DailyProgressCard(userAsync: userAsync),
                const SizedBox(height: 20),
                _SectionTitle('Lernmodi'),
                const SizedBox(height: 12),
                _ModusGrid(),
                const SizedBox(height: 20),
                _SectionTitle('Fortschritt'),
                const SizedBox(height: 12),
                _ProgressStatsCard(userAsync: userAsync),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── AppBar ────────────────────────────────────────────────────────────────

class _HomeAppBar extends StatelessWidget {
  final AsyncValue<AppUser?> userAsync;
  const _HomeAppBar({required this.userAsync});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: AppColors.primary,
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: userAsync.when(
              data: (user) => _AppBarContent(user: user),
              loading: () => const _AppBarContent(user: null),
              error: (_, __) => const _AppBarContent(user: null),
            ),
          ),
        ),
      ),
      title: const Text(
        'Haken Dran',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () {},
        ),
      ],
    );
  }
}

class _AppBarContent extends StatelessWidget {
  final AppUser? user;
  const _AppBarContent({this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user != null
                      ? 'Hallo, ${user!.displayName ?? 'Angler'}! 👋'
                      : 'Hallo, Angler! 👋',
                  style: AppTextStyles.headlineMedium
                      .copyWith(color: Colors.white),
                ),
                Text(
                  user != null ? user!.levelTitle : 'Wurmwerfer',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            const Spacer(),
            // XP-Badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${user?.xp ?? 0} XP',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Level-Fortschrittsbalken
        _LevelProgressBar(user: user),
      ],
    );
  }
}

class _LevelProgressBar extends StatelessWidget {
  final AppUser? user;
  const _LevelProgressBar({this.user});

  double get _progress {
    if (user == null) return 0;
    final thresholds = AppConstants.levelThresholds;
    final level = user!.level;
    if (level >= thresholds.length) return 1.0;
    final current = thresholds[level - 1];
    final next = thresholds[level];
    return (user!.xp - current) / (next - current);
  }

  @override
  Widget build(BuildContext context) {
    final level = user?.level ?? 1;
    return Row(
      children: [
        Text(
          'Lvl $level',
          style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.accent),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Lvl ${level + 1}',
          style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

// ── Daily Progress ─────────────────────────────────────────────────────────

class _DailyProgressCard extends StatelessWidget {
  final AsyncValue<AppUser?> userAsync;
  const _DailyProgressCard({required this.userAsync});

  @override
  Widget build(BuildContext context) {
    final user = userAsync.valueOrNull;
    final streak = user?.streak ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dein Streak', style: AppTextStyles.titleLarge),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department,
                          color: Colors.orange, size: 28),
                      const SizedBox(width: 6),
                      Text(
                        '$streak ${streak == 1 ? 'Tag' : 'Tage'}',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.tonal(
              onPressed: () {},
              child: const Text('Lernen'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Modi-Grid ──────────────────────────────────────────────────────────────

class _ModusGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: const [
        _ModusCard(
          icon: Icons.bolt,
          title: 'Blitzrunde',
          subtitle: '10 Fragen · 5 min',
          color: Color(0xFFF4A261),
          route: Routes.quiz,
        ),
        _ModusCard(
          icon: Icons.assignment,
          title: 'Simulation',
          subtitle: 'Echte Prüfung',
          color: AppColors.secondary,
          route: Routes.simulation,
        ),
        _ModusCard(
          icon: Icons.style,
          title: 'Karteikarten',
          subtitle: 'Leitner-System',
          color: AppColors.primary,
          route: Routes.flashcards,
        ),
        _ModusCard(
          icon: Icons.menu_book,
          title: 'Regelwerk',
          subtitle: 'Nachlesen',
          color: Color(0xFF9C89B8),
          route: Routes.regelwerk,
        ),
      ],
    );
  }
}

class _ModusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String route;

  const _ModusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(icon, size: 90,
                  color: color.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                  Text(title,
                      style: AppTextStyles.titleLarge
                          .copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stats Card ─────────────────────────────────────────────────────────────

class _ProgressStatsCard extends StatelessWidget {
  final AsyncValue<AppUser?> userAsync;
  const _ProgressStatsCard({required this.userAsync});

  @override
  Widget build(BuildContext context) {
    final user = userAsync.valueOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              label: 'Level',
              value: '${user?.level ?? 1}',
              icon: Icons.military_tech,
              color: AppColors.accent,
            ),
            _Divider(),
            _StatItem(
              label: 'XP gesamt',
              value: '${user?.xp ?? 0}',
              icon: Icons.star,
              color: AppColors.secondary,
            ),
            _Divider(),
            _StatItem(
              label: 'Streak',
              value: '${user?.streak ?? 0}',
              icon: Icons.local_fire_department,
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(value,
            style: AppTextStyles.headlineMedium
                .copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: VerticalDivider(
        color:
            Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: AppTextStyles.headlineMedium
            .copyWith(fontWeight: FontWeight.w700));
  }
}
