import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';
import 'auth_providers.dart';
import 'feed_service.dart';
import 'user_profile_service.dart';

/// Stream eines beliebigen User-Profils (UID-Family).
final userProfileProvider = StreamProvider.family<UserProfile?, String>((
  ref,
  uid,
) {
  return UserProfileService.instance.watchProfile(uid);
});

/// Eigenes Profil — bequemer Shortcut.
final myProfileProvider = StreamProvider<UserProfile?>((ref) {
  final me = ref.watch(currentUserProvider);
  if (me == null) return Stream.value(null);
  return UserProfileService.instance.watchProfile(me.uid);
});

/// True, wenn der eingeloggte User `targetUid` folgt.
final isFollowingProvider = StreamProvider.family<bool, String>((
  ref,
  targetUid,
) {
  // Auf currentUser hoeren, damit der Stream beim Login neu gebaut wird.
  ref.watch(currentUserProvider);
  return UserProfileService.instance.watchIsFollowing(targetUid);
});

/// UIDs, denen der eingeloggte User folgt.
final myFollowingProvider = StreamProvider<Set<String>>((ref) {
  final me = ref.watch(currentUserProvider);
  if (me == null) return Stream.value(const <String>{});
  return UserProfileService.instance.watchFollowing(me.uid);
});

/// Follower-UIDs eines beliebigen Users (für Stat-Counter und Listen).
final followersOfProvider = StreamProvider.family<Set<String>, String>((
  ref,
  uid,
) {
  return UserProfileService.instance.watchFollowers(uid);
});

/// Following-UIDs eines beliebigen Users.
final followingOfProvider = StreamProvider.family<Set<String>, String>((
  ref,
  uid,
) {
  return UserProfileService.instance.watchFollowing(uid);
});

/// Posts eines bestimmten Users (für Public-Profile-Grid und eigenes Profil).
/// Filtert blockierte Autoren clientseitig.
final userFeedPostsProvider = StreamProvider.family<List<FeedPost>, String>((
  ref,
  uid,
) {
  final blocked =
      ref.watch(blockedUidsProvider).valueOrNull ?? const <String>{};
  if (blocked.contains(uid)) {
    return Stream.value(const <FeedPost>[]);
  }
  return FeedService().watchUserFeed(uid);
});
