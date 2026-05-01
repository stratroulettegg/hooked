import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../models/mission.dart';
import '../models/player_rank.dart';
import '../services/app_providers.dart';
import 'rank_celebration.dart';

/// Banner mit aktuellem Spielerrang, Gesamtpunkten und Progress zum nächsten Rang.
/// Punkte = Fänge × 50 + Summe der abgeschlossenen Missions-Rewards.
class RankBanner extends ConsumerWidget {
  const RankBanner({super.key, this.compact = false});

  /// Kompakte Variante (weniger Padding, kleinere Schrift) für die Startseite.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(catchStatsProvider);
    final missionsAsync = ref.watch(missionProvider);

    final totalCatches = statsAsync.valueOrNull?.total ?? 0;
    final missions = missionsAsync.valueOrNull ?? const <Mission>[];
    final missionPoints = missions
        .where((m) => m.isCompleted)
        .fold<int>(0, (s, m) => s + m.pointsReward);
    final points = totalCatches * 50 + missionPoints;

    final view = _RankBannerView(
      points: points,
      totalCatches: totalCatches,
      compact: compact,
    );

    if (!kDebugMode) return view;

    // Debug-Only: Long-Press auf den Banner triggert die Party mit dem nächsten
    // Rang (oder aktuellem, falls Max erreicht) zum Testen der Animation.
    return GestureDetector(
      onLongPress: () {
        final current = PlayerRank.forPoints(points);
        final target = PlayerRank.nextAfter(current) ?? current;
        ref.read(rankCelebrationControllerProvider).trigger(target);
      },
      child: view,
    );
  }
}

class _RankBannerView extends StatelessWidget {
  const _RankBannerView({
    required this.points,
    required this.totalCatches,
    required this.compact,
  });

  final int points;
  final int totalCatches;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final rank = PlayerRank.forPoints(points);
    final next = PlayerRank.nextAfter(rank);
    final span = next != null ? (next.minPoints - rank.minPoints) : 1;
    final progressed = (points - rank.minPoints).clamp(0, span);
    final progress = next != null ? progressed / span : 1.0;

    final pad = compact ? 16.0 : 20.0;
    final avatarSize = compact ? 48.0 : 56.0;
    final emojiSize = compact ? 24.0 : 28.0;
    final titleSize = compact ? 17.0 : 20.0;
    final subSize = compact ? 12.0 : 13.0;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ApexColors.primaryDark.withAlpha(80), c.surfaceVariant],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ApexColors.primary.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: const BoxDecoration(
                  color: ApexColors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(rank.emoji, style: TextStyle(fontSize: emojiSize)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rank.title,
                        style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            color: ApexColors.primary,
                            letterSpacing: 1.5)),
                    Text('$points Punkte · $totalCatches Fänge',
                        style: TextStyle(fontSize: subSize, color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: c.surface,
                valueColor: const AlwaysStoppedAnimation(ApexColors.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Noch ${next.minPoints - points} Punkte bis ${next.title}',
              style: TextStyle(fontSize: 11, color: c.textMuted, letterSpacing: 0.5),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text('Maximaler Rang erreicht',
                style: TextStyle(fontSize: 11, color: c.textMuted, letterSpacing: 0.5)),
          ],
        ],
      ),
    );
  }
}
