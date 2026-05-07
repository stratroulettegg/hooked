import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase/auth_providers.dart';
import 'firebase/feed_service.dart';
import 'firebase/user_profile_providers.dart';
import 'app_providers.dart';

/// Schlüssel für `lastReadAt` der Bell pro User.
String _lastReadKey(String uid) => 'inbox_last_read_$uid';

/// Liefert den lokalen `lastReadAt`-Timestamp für die Bell. Default ist
/// „jetzt", damit Bestandsuser beim ersten Öffnen nicht mit 7 Tagen alten
/// Beiträgen als „neu" überrollt werden.
class InboxReadState {
  static Future<DateTime> getLastRead(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastReadKey(uid));
    if (ms == null) {
      final now = DateTime.now();
      await prefs.setInt(_lastReadKey(uid), now.millisecondsSinceEpoch);
      return now;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> markAllRead(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastReadKey(uid),
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// `lastReadAt` als Riverpod-Provider — hält den Timestamp im Speicher,
/// damit der Bell-Stream live darauf reagiert.
class InboxLastReadNotifier extends AsyncNotifier<DateTime> {
  @override
  Future<DateTime> build() async {
    final me = ref.watch(currentUserProvider);
    if (me == null) return DateTime.now();
    return InboxReadState.getLastRead(me.uid);
  }

  /// Setzt den Timestamp auf jetzt (Bell wird grau).
  Future<void> markAllRead() async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    await InboxReadState.markAllRead(me.uid);
    state = AsyncData(DateTime.now());
  }
}

final inboxLastReadProvider =
    AsyncNotifierProvider<InboxLastReadNotifier, DateTime>(
      InboxLastReadNotifier.new,
    );

/// Stream der Bell-Inhalte: neue Posts gefolgter User seit lastReadAt.
final inboxPostsProvider = StreamProvider<List<FeedPost>>((ref) {
  final me = ref.watch(currentUserProvider);
  if (me == null) return Stream.value(const <FeedPost>[]);
  final following =
      ref.watch(myFollowingProvider).valueOrNull ?? const <String>{};
  final lastRead =
      ref.watch(inboxLastReadProvider).valueOrNull ?? DateTime.now();
  final blocked =
      ref.watch(blockedUidsProvider).valueOrNull ?? const <String>{};
  if (following.isEmpty) return Stream.value(const <FeedPost>[]);
  return FeedService()
      .watchFollowingFeedSince(following, lastRead)
      .map((list) => list.where((p) => !blocked.contains(p.userId)).toList());
});

/// Anzahl ungelesener Bell-Items (für Badge). Auf 99 gecappt.
final inboxUnreadCountProvider = Provider<int>((ref) {
  final n = ref.watch(inboxPostsProvider).valueOrNull?.length ?? 0;
  return n > 99 ? 99 : n;
});
