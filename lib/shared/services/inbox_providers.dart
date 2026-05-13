import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/inbox_item.dart';
import 'firebase/auth_providers.dart';
import 'firebase/feed_service.dart';
import 'firebase/user_profile_providers.dart';
import 'app_providers.dart';

/// Projekt nutzt eine named Firestore-Datenbank `default` (nicht `(default)`).
FirebaseFirestore get _firestore => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'default',
    );

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
  final m = ref.watch(socialInboxItemsProvider).valueOrNull
          ?.where((i) => i.isUnread)
          .length ??
      0;
  final total = n + m;
  return total > 99 ? 99 : total;
});

/// Stream der Social-Notifications (Likes, Kommentare, Follows) aus
/// `userProfiles/{uid}/inbox/`. Wird vom Server gepflegt.
final socialInboxItemsProvider = StreamProvider<List<InboxItem>>((ref) {
  final me = ref.watch(currentUserProvider);
  if (me == null) return Stream.value(const <InboxItem>[]);
  return _firestore
      .collection('userProfiles')
      .doc(me.uid)
      .collection('inbox')
      .orderBy('updatedAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(InboxItem.fromDoc).toList());
});

/// Markiert ein einzelnes Inbox-Item als gelesen.
Future<void> markInboxItemRead(String uid, String itemId) async {
  await _firestore
      .collection('userProfiles')
      .doc(uid)
      .collection('inbox')
      .doc(itemId)
      .update({'readAt': FieldValue.serverTimestamp()})
      .catchError((_) {});
}

/// Markiert alle ungelesenen Items als gelesen — pro Aufruf max. 100.
Future<void> markAllSocialInboxRead(String uid) async {
  final coll = _firestore
      .collection('userProfiles')
      .doc(uid)
      .collection('inbox');
  final snap = await coll.where('readAt', isNull: true).limit(100).get();
  if (snap.docs.isEmpty) return;
  final batch = _firestore.batch();
  for (final d in snap.docs) {
    batch.update(d.reference, {'readAt': FieldValue.serverTimestamp()});
  }
  await batch.commit().catchError((_) {});
}
