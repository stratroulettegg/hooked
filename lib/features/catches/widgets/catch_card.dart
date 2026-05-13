import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/catch_entry.dart';
import '../../../shared/services/app_paths.dart';
import '../../../shared/services/app_providers.dart';
import '../../../shared/services/feed_seen_service.dart';
import '../../../shared/services/firebase/feed_service.dart';
import '../../../shared/widgets/swipe_to_delete.dart';

/// Karten-Darstellung eines Fangs in der "Meine Fänge"-Liste.
///
/// Liefert Hero-Foto (oder Spezies-Asset/Emoji-Fallback), PB-Badge,
/// Geteilt-Badge mit Live-Counter (über `myFeedPostsProvider`) und
/// einen Footer mit Köder/Spot. `compact: true` halbiert die Innen-
/// abstände — wird im 2-Spalten-Grid genutzt.
class CatchCard extends ConsumerWidget {
  const CatchCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.isPB = false,
    this.compact = false,
    this.onJumpToFeed,
  });
  final CatchEntry entry;
  final VoidCallback onTap;
  final bool isPB;
  final bool compact;

  /// Aufruf, wenn der User auf das Geteilt-Badge tippt → springt im
  /// Community-Feed direkt zu diesem Post.
  final ValueChanged<String>? onJumpToFeed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final spots = ref.watch(spotProvider).valueOrNull ?? const [];
    final spot = entry.spotId != null
        ? spots.where((s) => s.id == entry.spotId).firstOrNull
        : null;
    final hasPhoto = AppPaths.photoFile(entry.photoPath) != null;

    // Live-Counter aus dem eigenen Feed-Stream + Seen-State.
    final myPosts = ref.watch(myFeedPostsProvider).valueOrNull ?? const {};
    final FeedPost? post = entry.isShared ? myPosts[entry.id] : null;
    final seen =
        ref.watch(feedSeenProvider)[entry.id] ?? const FeedSeenCounts();
    final newLikes = post == null
        ? 0
        : (post.likeCount - seen.likes).clamp(0, 9999);
    final newComments = post == null
        ? 0
        : (post.commentCount - seen.comments).clamp(0, 9999);
    final hasNews = newLikes > 0 || newComments > 0;

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
      onTap: () {
        // Beim Öffnen den aktuellen Stand als gesehen markieren — danach
        // verschwindet der Neu-Indikator auf der Karte.
        if (post != null) {
          ref
              .read(feedSeenProvider.notifier)
              .markSeen(post.id, post.likeCount, post.commentCount);
        }
        onTap();
      },
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
                          final cacheW =
                              (constraints.maxWidth *
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
                              Icon(
                                Icons.emoji_events,
                                size: 13,
                                color: Colors.white,
                              ),
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
                    // Top-Left: Geteilt-Pill mit Live-Counter, sonst
                    // Hinweis bei fehlendem Foto.
                    if (entry.isShared)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: post == null || onJumpToFeed == null
                              ? null
                              : () {
                                  // Vor dem Sprung den aktuellen Stand
                                  // als gesehen markieren.
                                  ref
                                      .read(feedSeenProvider.notifier)
                                      .markSeen(
                                        post.id,
                                        post.likeCount,
                                        post.commentCount,
                                      );
                                  onJumpToFeed!(post.id);
                                },
                          child: _SharedBadge(
                            post: post,
                            newLikes: newLikes,
                            newComments: newComments,
                            hasNews: hasNews,
                          ),
                        ),
                      )
                    else if (!hasPhoto)
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
                              Icon(
                                Icons.image_not_supported_outlined,
                                size: 12,
                                color: Colors.white,
                              ),
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
                  compact ? 10 : 14,
                  compact ? 9 : 12,
                  compact ? 10 : 14,
                  0,
                ),
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
                            AppDateFormats.dayMonthYearShort.format(
                              entry.caughtAt,
                            ),
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
                                AppDateFormats.hourMinute.format(
                                  entry.caughtAt,
                                ),
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
                    compact ? 10 : 14,
                    8,
                    compact ? 10 : 14,
                    0,
                  ),
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
                  compact ? 10 : 14,
                  8,
                  compact ? 10 : 14,
                  compact ? 10 : 12,
                ),
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
                        text: AppDateFormats.dayMonthYearShort.format(
                          entry.caughtAt,
                        ),
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

IconData _timeOfDayIcon(DateTime dt) {
  final h = dt.hour;
  if (h >= 5 && h < 9) return Icons.wb_twilight;
  if (h >= 9 && h < 18) return Icons.wb_sunny_outlined;
  if (h >= 18 && h < 21) return Icons.nights_stay_outlined;
  return Icons.dark_mode_outlined;
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
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 64))),
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

/// Glas-Badge, das auf der "Meine Fänge"-Karte signalisiert, dass der Fang
/// in der Community geteilt wurde — inkl. Live-Counter für Likes/Kommentare
/// und einem roten Dot, wenn neue Reaktionen seit dem letzten Besuch da sind.
class _SharedBadge extends StatelessWidget {
  const _SharedBadge({
    required this.post,
    required this.newLikes,
    required this.newComments,
    required this.hasNews,
  });

  final FeedPost? post;
  final int newLikes;
  final int newComments;
  final bool hasNews;

  @override
  Widget build(BuildContext context) {
    final pending = post == null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(95),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: hasNews
                  ? ApexColors.scoreLow.withAlpha(180)
                  : Colors.white.withAlpha(45),
              width: 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                pending ? Icons.cloud_upload_outlined : Icons.public,
                size: 13,
                color: Colors.white.withAlpha(230),
              ),
              const SizedBox(width: 5),
              Text(
                pending ? 'Wird geteilt…' : 'Geteilt',
                style: const TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
              if (post != null) ...[
                const SizedBox(width: 8),
                _badgeStat(
                  Icons.favorite,
                  post!.likeCount,
                  highlighted: newLikes > 0,
                ),
                const SizedBox(width: 6),
                _badgeStat(
                  Icons.mode_comment,
                  post!.commentCount,
                  highlighted: newComments > 0,
                ),
                if (hasNews) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: ApexColors.scoreLow,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _badgeStat(IconData icon, int count, {bool highlighted = false}) {
    final color = highlighted
        ? ApexColors.scoreLow
        : Colors.white.withAlpha(230);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
