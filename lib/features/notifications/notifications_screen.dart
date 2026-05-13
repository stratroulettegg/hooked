import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/inbox_item.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/feed_service.dart';
import '../../shared/services/firebase/user_profile_providers.dart';
import '../../shared/services/inbox_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Bell-Inbox: zeigt Likes, Kommentare und Follows (gruppiert) sowie
/// neue Posts gefolgter Angler.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _markedRead = false;

  @override
  void deactivate() {
    // Beim Verlassen als gelesen markieren. Wichtig: nur direkt persistieren,
    // KEINEN Riverpod-State synchron ändern — sonst rebuildet das gerade
    // unmounting Widget und Flutter wirft `_ElementLifecycle.defunct`.
    if (!_markedRead) {
      _markedRead = true;
      final me = ref.read(currentUserProvider);
      // Persistente Speicher direkt setzen — Provider-State wird beim
      // nächsten App-Start neu aus den Prefs gelesen.
      InboxReadState.markAllRead(me?.uid ?? '');
      if (me != null) {
        markAllSocialInboxRead(me.uid);
      }
    }
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final socialAsync = ref.watch(socialInboxItemsProvider);
    final postsAsync = ref.watch(inboxPostsProvider);

    final social = socialAsync.valueOrNull ?? const <InboxItem>[];
    final posts = postsAsync.valueOrNull ?? const <FeedPost>[];

    final loading = socialAsync.isLoading && postsAsync.isLoading;
    final empty = social.isEmpty && posts.isEmpty;

    return Scaffold(
      appBar: const ApexAppBar(),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : empty
          ? _EmptyState(c: c)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (social.isNotEmpty) ...[
                  _SectionHeader(label: 'Aktivität', c: c),
                  const SizedBox(height: 8),
                  for (final item in social) ...[
                    _InboxItemTile(item: item),
                    const SizedBox(height: 8),
                  ],
                ],
                if (posts.isNotEmpty) ...[
                  if (social.isNotEmpty) const SizedBox(height: 8),
                  _SectionHeader(label: 'Neue Beiträge', c: c),
                  const SizedBox(height: 8),
                  for (final post in posts) ...[
                    _PostNotificationTile(post: post),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.c});
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
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
            'Sobald jemand deinen Fang liked, kommentiert oder dir folgt, '
            'siehst du es hier.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.c});
  final String label;
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: c.textMuted,
        ),
      ),
    );
  }
}

String _relative(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'gerade eben';
  if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
  if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
  if (diff.inDays < 7) return 'vor ${diff.inDays} Tg.';
  return 'vor ${(diff.inDays / 7).floor()} Wo.';
}

class _InboxItemTile extends StatelessWidget {
  const _InboxItemTile({required this.item});
  final InboxItem item;

  String _title() {
    final n = item.count;
    final primary = item.primaryActorName;
    String others() {
      if (n <= 1) return '';
      if (n == 2) return ' und 1 weiterer Person';
      return ' und ${n - 1} weiteren';
    }

    switch (item.type) {
      case InboxType.like:
        return n <= 1
            ? '$primary hat deinen Fang geliked'
            : '$primary${others()} haben deinen Fang geliked';
      case InboxType.comment:
        return n <= 1
            ? '$primary hat deinen Fang kommentiert'
            : '$primary${others()} haben deinen Fang kommentiert';
      case InboxType.reply:
        return n <= 1
            ? '$primary hat auf deinen Kommentar geantwortet'
            : '$primary${others()} haben auf deinen Kommentar geantwortet';
      case InboxType.follow:
        return '$primary folgt dir jetzt';
    }
  }

  IconData _icon() {
    switch (item.type) {
      case InboxType.like:
        return Icons.favorite;
      case InboxType.comment:
        return Icons.mode_comment_outlined;
      case InboxType.reply:
        return Icons.reply_rounded;
      case InboxType.follow:
        return Icons.person_add_alt_1;
    }
  }

  Color _iconColor(ApexColors c) {
    switch (item.type) {
      case InboxType.like:
        return Colors.redAccent;
      case InboxType.comment:
        return ApexColors.primary;
      case InboxType.reply:
        return ApexColors.primary;
      case InboxType.follow:
        return Colors.greenAccent.shade400;
    }
  }

  void _onTap(BuildContext context) {
    switch (item.type) {
      case InboxType.like:
        if (item.postId != null) {
          context.go('/feed', extra: item.postId);
        }
        break;
      case InboxType.comment:
      case InboxType.reply:
        if (item.postId != null) {
          // Beim Tap auf eine Kommentar-/Antwort-Benachrichtigung direkt
          // das Kommentar-Sheet öffnen. Eine Nonce sorgt dafür, dass
          // auch wiederholte Taps (gleicher Post) das Sheet erneut öffnen.
          context.go(
            '/feed',
            extra: {
              'postId': item.postId,
              'openComments': true,
              'requestId': DateTime.now().microsecondsSinceEpoch,
            },
          );
        }
        break;
      case InboxType.follow:
        if (item.primaryActorUid.isNotEmpty) {
          context.push('/user/${item.primaryActorUid}');
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final unread = item.isUnread;
    return Material(
      color: unread ? ApexColors.primary.withAlpha(18) : c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTap(context),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unread
                  ? ApexColors.primary.withAlpha(80)
                  : c.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AvatarStack(item: item, c: c),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_icon(), size: 16, color: _iconColor(c)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _title(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: c.textPrimary,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if ((item.type == InboxType.comment ||
                            item.type == InboxType.reply) &&
                        (item.commentText?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: Text(
                          '„${item.commentText!}"',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: c.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        _relative(item.updatedAt),
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: ApexColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.item, required this.c});
  final InboxItem item;
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    final actors = item.actors.take(3).toList();
    if (actors.isEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: ApexColors.primary.withAlpha(40),
        child: Icon(Icons.person, color: ApexColors.primary),
      );
    }
    if (actors.length == 1) {
      return _SingleAvatar(
        photo: item.actorPhotos[actors.first],
        size: 44,
      );
    }
    // Stack: 2-3 Avatare leicht versetzt.
    return SizedBox(
      width: 56,
      height: 44,
      child: Stack(
        children: [
          for (int i = actors.length - 1; i >= 0; i--)
            Positioned(
              left: i * 14.0,
              top: 0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 2),
                ),
                child: _SingleAvatar(
                  photo: item.actorPhotos[actors[i]],
                  size: 32,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SingleAvatar extends StatelessWidget {
  const _SingleAvatar({required this.photo, required this.size});
  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo != null && photo!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ApexColors.primary.withAlpha(40),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photo!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Icon(
                Icons.person,
                color: ApexColors.primary,
                size: size * 0.55,
              ),
            )
          : Icon(
              Icons.person,
              color: ApexColors.primary,
              size: size * 0.55,
            ),
    );
  }
}

class _PostNotificationTile extends ConsumerWidget {
  const _PostNotificationTile({required this.post});
  final FeedPost post;

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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/user/${post.userId}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _SingleAvatar(photo: photoUrl, size: 44),
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
