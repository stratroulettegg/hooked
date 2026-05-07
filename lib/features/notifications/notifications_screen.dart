import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/services/firebase/feed_service.dart';
import '../../shared/services/firebase/user_profile_providers.dart';
import '../../shared/services/inbox_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Bell-Inbox: zeigt neue Posts gefolgter User seit dem letzten Öffnen.
/// Beim Verlassen wird `lastReadAt` auf jetzt gesetzt → Badge wird grau.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Beim Öffnen alle als gelesen markieren — der Stream auf dieser Seite
    // bleibt trotzdem mit den Items befüllt (Snapshot vor mark-read).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inboxLastReadProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final postsAsync = ref.watch(inboxPostsProvider);

    return Scaffold(
      appBar: const ApexAppBar(),
      body: postsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Konnte Benachrichtigungen nicht laden.\n$e',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary),
          ),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: c.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Alles ruhig hier.',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Folge anderen Anglern, um neue Beiträge hier zu sehen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _PostNotificationTile(post: posts[i]),
          );
        },
      ),
    );
  }
}

class _PostNotificationTile extends ConsumerWidget {
  const _PostNotificationTile({required this.post});
  final FeedPost post;

  String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    return 'vor ${diff.inDays} Tg.';
  }

  FishSpecies? _species() {
    for (final s in FishSpecies.values) {
      if (s.name == post.species) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final profile = ref.watch(userProfileProvider(post.userId)).valueOrNull;
    final liveName = profile?.displayName?.trim();
    final livePhoto = profile?.photoUrl;
    final author = (liveName != null && liveName.isNotEmpty)
        ? liveName
        : (post.userName?.isNotEmpty == true ? post.userName! : 'Angler:in');
    final photoUrl = (livePhoto != null && livePhoto.isNotEmpty)
        ? livePhoto
        : post.userPhotoUrl;
    final species = _species();
    final speciesLabel = species?.displayName ?? post.species;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/user/${post.userId}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: ApexColors.primary.withAlpha(40),
                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                    ? NetworkImage(photoUrl)
                    : null,
                child: (photoUrl == null || photoUrl.isEmpty)
                    ? Icon(Icons.person, color: ApexColors.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$author hat einen Fang geteilt',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${species?.emoji ?? ''} $speciesLabel · ${_relative(post.createdAt)}',
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              if (post.photoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    post.photoUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
