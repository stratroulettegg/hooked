import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/services/firebase/feed_service.dart';
import '../catches/feed_post_detail_screen.dart';

/// Quadratisches Foto-Grid für Profil-Screens. Zeigt die letzten Feed-Posts
/// eines Users. Tap öffnet ein Vollbild-Foto mit Mini-Infos (Art, Datum,
/// Gewässer). Komplettes Detail-Design lebt im Catch-Feed.
class ProfilePostsGrid extends StatelessWidget {
  const ProfilePostsGrid({
    super.key,
    required this.posts,
    this.emptyHint = 'Noch keine Beiträge im Feed.',
  });

  final List<FeedPost> posts;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);

    if (posts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(Icons.photo_library_outlined, color: c.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                emptyHint,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, i) {
        return _PostThumb(posts: posts, index: i);
      },
    );
  }
}

class _PostThumb extends StatelessWidget {
  const _PostThumb({required this.posts, required this.index});

  final List<FeedPost> posts;
  final int index;
  FeedPost get post => posts[index];

  FishSpecies? _species() {
    for (final s in FishSpecies.values) {
      if (s.name == post.species) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final hasPhoto = post.photoUrl != null && post.photoUrl!.isNotEmpty;
    final species = _species();

    return Material(
      color: c.surfaceVariant,
      child: InkWell(
        onTap: () => _open(context),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                CachedNetworkImage(
                  imageUrl: post.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.surfaceVariant),
                  errorWidget: (_, __, ___) => _Fallback(species: species),
                )
              else
                _Fallback(species: species),
              // Kleiner Like-Counter unten links, wenn > 0.
              if (post.likeCount > 0)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite,
                          size: 11,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${post.likeCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => FeedPostDetailScreen(posts: posts, initialIndex: index),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.species});
  final FishSpecies? species;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final asset = species?.imageAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return Container(
      color: c.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(Icons.water, color: c.textMuted, size: 28),
    );
  }
}
