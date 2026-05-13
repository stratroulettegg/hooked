import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/user_profile_providers.dart';
import '../../shared/services/firebase/user_profile_service.dart';
import '../../shared/services/pro/pro_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/moderation_actions.dart';
import 'profile_posts_grid.dart';

/// Öffentliches Profil. Funktioniert für jeden User — auch für mich
/// selbst (dann mit Edit/Settings-Actions statt Follow-Button).
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final me = ref.watch(currentUserProvider);
    final isMe = me?.uid == uid;

    final blocked =
        ref.watch(blockedUidsProvider).valueOrNull ?? const <String>{};
    final isBlocked = !isMe && blocked.contains(uid);
    final profileAsync = ref.watch(userProfileProvider(uid));
    final postsAsync = ref.watch(userFeedPostsProvider(uid));
    final followers = ref.watch(followersOfProvider(uid)).valueOrNull;
    final following = ref.watch(followingOfProvider(uid)).valueOrNull;

    return Scaffold(
      appBar: ApexAppBar(
        extraActions: isMe
            ? [
                IconButton(
                  tooltip: 'Einstellungen',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/settings'),
                ),
              ]
            : (me == null
                ? const <Widget>[]
                : [
                    _ProfileMoreButton(
                      targetUid: uid,
                      isBlocked: isBlocked,
                    ),
                  ]),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Profil konnte nicht geladen werden.\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        ),
        data: (profile) {
          // Wenn Profil noch nicht existiert (User hat noch nie Edit
          // gespeichert), zeigen wir trotzdem Posts + minimale Identität
          // aus dem Feed-Avatar — dafür brauchen wir mind. einen Post.
          final fallbackName = postsAsync.valueOrNull?.firstOrNull?.userName
              ?.trim();
          final fallbackPhoto =
              postsAsync.valueOrNull?.firstOrNull?.userPhotoUrl;
          final displayName = profile?.displayName?.trim().isNotEmpty == true
              ? profile!.displayName!
              : (fallbackName?.isNotEmpty == true
                    ? fallbackName!
                    : 'Angler:in');
          final photoUrl = profile?.photoUrl ?? fallbackPhoto;
          final steckbrief = profile?.steckbrief?.trim();
          final species = profile?.targetSpecies ?? const <FishSpecies>[];
          final posts = postsAsync.valueOrNull ?? const [];

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              if (isBlocked)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ApexColors.strike.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ApexColors.strike.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.block, color: ApexColors.strike, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Du hast diesen Nutzer blockiert.',
                          style: TextStyle(
                            color: ApexColors.strike,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: ApexColors.primary.withAlpha(40),
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                      ? NetworkImage(photoUrl)
                      : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Icon(Icons.person, size: 44, color: ApexColors.primary)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    if (isMe && ref.watch(isProProvider)) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: ApexColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (profile?.handle != null && profile!.handle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Center(
                  child: Text(
                    '@${profile.handle}',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // Drei Stats in einer sauber zentrierten Reihe:
              // Beiträge · Follower-Pill · Folgt — gleiche Höhe, gleicher Abstand.
              _StatsRow(
                postCount: posts.length,
                followers: followers?.length ?? 0,
                following: following?.length ?? 0,
              ),
              const SizedBox(height: 16),
              if (isMe)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/profile/edit'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Profil bearbeiten'),
                  ),
                )
              else if (me != null && !isBlocked)
                _FollowButton(targetUid: uid),
              if (steckbrief != null && steckbrief.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Section(
                  title: 'STECKBRIEF',
                  child: Text(
                    steckbrief,
                    style: TextStyle(color: c.textPrimary, fontSize: 14),
                  ),
                ),
              ],
              if (species.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Section(
                  title: 'ZIELFISCH',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: species
                        .map(
                          (s) => Chip(
                            label: Text('${s.emoji} ${s.displayName}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'GETEILTE BEITRÄGE',
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 12,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ProfilePostsGrid(
                posts: posts,
                emptyHint: isMe
                    ? 'Du hast noch nichts geteilt.'
                    : 'Noch keine Beiträge.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.postCount,
    required this.followers,
    required this.following,
  });

  final int postCount;
  final int followers;
  final int following;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _StatCell(label: 'Beiträge', value: postCount),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _FollowerPill(count: followers),
        ),
        Expanded(
          child: _StatCell(label: 'Folgt', value: following),
        ),
      ],
    );
  }
}

class _FollowerPill extends StatelessWidget {
  const _FollowerPill({required this.count});
  final int count;

  String _format(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) {
      final v = (n / 1000).toStringAsFixed(1);
      return '${v.replaceAll('.0', '')}K';
    }
    if (n < 1000000) return '${(n / 1000).round()}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ApexColors.primary.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ApexColors.primary.withAlpha(80)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_alt_rounded,
                size: 14,
                color: ApexColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                _format(count),
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ApexColors.primary,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Follower',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ApexColors.primary,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.targetUid});
  final String targetUid;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isFollowingAsync = ref.watch(isFollowingProvider(widget.targetUid));
    final isFollowing = isFollowingAsync.valueOrNull ?? false;

    final child = _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(isFollowing ? Icons.check : Icons.person_add_alt_1, size: 18);
    final label = Text(isFollowing ? 'Folge ich' : 'Folgen');

    return SizedBox(
      width: double.infinity,
      child: isFollowing
          ? OutlinedButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: child,
              label: label,
            )
          : FilledButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: child,
              label: label,
            ),
    );
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final blocked =
        ref.read(blockedUidsProvider).valueOrNull ?? const <String>{};
    try {
      await UserProfileService.instance.toggleFollow(
        widget.targetUid,
        blockedUids: blocked,
      );
    } on StateError catch (e) {
      if (!mounted) return;
      if (e.message == 'blocked') {
        AppToast.error(
          context,
          'Du kannst diesem Nutzer nicht folgen, weil du ihn blockiert hast.',
        );
      } else {
        AppToast.error(context, 'Aktion nicht möglich.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Konnte Status nicht ändern.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 12,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w700,
            color: c.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _ProfileMoreButton extends ConsumerWidget {
  const _ProfileMoreButton({required this.targetUid, required this.isBlocked});

  final String targetUid;
  final bool isBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        switch (value) {
          case 'report':
            await showReportSheet(
              context,
              ref,
              kind: ModerationTargetKind.user,
              targetUid: targetUid,
            );
            break;
          case 'block':
            await confirmBlockUser(
              context,
              ref,
              targetUid: targetUid,
            );
            break;
          case 'unblock':
            try {
              await ref
                  .read(moderationServiceProvider)
                  .unblockUser(targetUid);
              if (context.mounted) {
                AppToast.success(context, 'Block aufgehoben.');
              }
            } catch (e) {
              if (context.mounted) {
                AppToast.error(context, 'Aufheben fehlgeschlagen: $e');
              }
            }
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          value: 'report',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.flag_outlined, size: 20),
            title: Text('Profil melden'),
          ),
        ),
        if (isBlocked)
          const PopupMenuItem<String>(
            value: 'unblock',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_open_outlined, size: 20),
              title: Text('Block aufheben'),
            ),
          )
        else
          const PopupMenuItem<String>(
            value: 'block',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.block, size: 20),
              title: Text('Nutzer blockieren'),
            ),
          ),
      ],
    );
  }
}
