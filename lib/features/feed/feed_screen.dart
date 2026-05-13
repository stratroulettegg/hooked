import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/apex_app_bar.dart';
import '../catches/catch_list_screen.dart' show CommunityFeedView;

/// Globaler Community-Feed als eigenständiger Tab-Screen.
/// Nimmt optional einen `initialPostId` entgegen (z. B. aus einer Push-
/// Notification oder einem Deep-Link), zu dem der Pager beim Öffnen springt.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({
    super.key,
    this.initialPostId,
    this.openComments = false,
    this.commentsRequestId = 0,
  });

  final String? initialPostId;
  final bool openComments;

  /// Eindeutige Nonce: ändert sich bei jedem Tap auf eine Kommentar-
  /// Benachrichtigung, damit das Sheet auch dann erneut aufgeht, wenn
  /// der Feed-Branch der Shell schon im selben State steht.
  final int commentsRequestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const ApexAppBar(),
      body: CommunityFeedView(
        initialPostId: initialPostId,
        openComments: openComments,
        commentsRequestId: commentsRequestId,
      ),
    );
  }
}
