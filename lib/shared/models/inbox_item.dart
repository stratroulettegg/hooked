import 'package:cloud_firestore/cloud_firestore.dart';

/// Ein Inbox-Item, gruppiert nach `type` × Ziel.
///
/// - `type=like` / `comment`: pro Post ein Doc → `actors` enthält die
///   uids derer, die geliked/kommentiert haben (neueste zuerst).
/// - `type=follow`: pro Actor ein Doc.
class InboxItem {
  final String id;
  final InboxType type;
  final String? postId;
  final String? commentId;
  final String? parentCommentId;
  final String? commentText;
  final List<String> actors;
  final Map<String, String> actorNames;
  final Map<String, String> actorPhotos;
  final int count;
  final DateTime updatedAt;
  final DateTime? readAt;

  InboxItem({
    required this.id,
    required this.type,
    required this.actors,
    required this.actorNames,
    required this.actorPhotos,
    required this.count,
    required this.updatedAt,
    this.postId,
    this.commentId,
    this.parentCommentId,
    this.commentText,
    this.readAt,
  });

  bool get isUnread => readAt == null;

  String get primaryActorUid => actors.isNotEmpty ? actors.first : '';
  String get primaryActorName =>
      actorNames[primaryActorUid]?.trim().isNotEmpty == true
      ? actorNames[primaryActorUid]!
      : 'Angler:in';
  String? get primaryActorPhoto {
    final p = actorPhotos[primaryActorUid];
    return (p != null && p.isNotEmpty) ? p : null;
  }

  factory InboxItem.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final t = (d['type'] as String?) ?? 'like';
    return InboxItem(
      id: doc.id,
      type: InboxType.values.firstWhere(
        (e) => e.name == t,
        orElse: () => InboxType.like,
      ),
      postId: d['postId'] as String?,
      commentId: d['commentId'] as String?,
      parentCommentId: d['parentCommentId'] as String?,
      commentText: d['commentText'] as String?,
      actors: (d['actors'] as List?)?.cast<String>() ?? const [],
      actorNames: ((d['actorNames'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      ),
      actorPhotos: ((d['actorPhotos'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      ),
      count: (d['count'] as num?)?.toInt() ?? 0,
      updatedAt:
          (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (d['readAt'] as Timestamp?)?.toDate(),
    );
  }
}

enum InboxType { like, comment, follow, reply }
