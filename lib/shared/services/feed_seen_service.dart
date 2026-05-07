import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Speichert, wie viele Likes/Kommentare der User f\u00fcr seinen eigenen Post
/// zuletzt gesehen hat. So k\u00f6nnen wir auf der "Meine F\u00e4nge"-\u00dcbersicht
/// markieren, wenn neue Reaktionen vorliegen.
class FeedSeenCounts {
  const FeedSeenCounts({this.likes = 0, this.comments = 0});
  final int likes;
  final int comments;
}

class FeedSeenNotifier extends StateNotifier<Map<String, FeedSeenCounts>> {
  FeedSeenNotifier() : super(const {}) {
    _load();
  }

  static const _kPrefix = 'feed_seen_';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_kPrefix));
    final map = <String, FeedSeenCounts>{};
    for (final k in keys) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      final parts = raw.split(':');
      if (parts.length != 2) continue;
      final id = k.substring(_kPrefix.length);
      map[id] = FeedSeenCounts(
        likes: int.tryParse(parts[0]) ?? 0,
        comments: int.tryParse(parts[1]) ?? 0,
      );
    }
    if (mounted) state = map;
  }

  /// Markiert den aktuellen Stand als gesehen.
  Future<void> markSeen(String postId, int likes, int comments) async {
    final next = Map<String, FeedSeenCounts>.from(state);
    next[postId] = FeedSeenCounts(likes: likes, comments: comments);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kPrefix$postId', '$likes:$comments');
  }

  FeedSeenCounts get(String postId) => state[postId] ?? const FeedSeenCounts();
}

final feedSeenProvider =
    StateNotifierProvider<FeedSeenNotifier, Map<String, FeedSeenCounts>>(
      (_) => FeedSeenNotifier(),
    );
