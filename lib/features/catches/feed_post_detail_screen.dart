import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/firebase/feed_service.dart';
import 'catch_list_screen.dart' show FeedPostPage;

/// Vollbild-Ansicht eines Feed-Beitrags mit vertikalem Swipe zwischen
/// Posts derselben Liste — gleiche Mechanik wie der Community-Feed.
/// Wird vom Profil-Grid gepusht.
class FeedPostDetailScreen extends ConsumerStatefulWidget {
  const FeedPostDetailScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
  });

  final List<FeedPost> posts;
  final int initialIndex;

  @override
  ConsumerState<FeedPostDetailScreen> createState() =>
      _FeedPostDetailScreenState();
}

class _FeedPostDetailScreenState extends ConsumerState<FeedPostDetailScreen> {
  late final PageController _controller;
  late int _currentIndex;
  // IDs lokal entfernter Posts — werden im PageView ausgeblendet.
  final Set<String> _deleted = <String>{};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<FeedPost> get _visiblePosts => widget.posts
      .where((p) => !_deleted.contains(p.id))
      .toList(growable: false);

  void _handleDeleted(String postId) {
    if (!mounted) return;
    setState(() => _deleted.add(postId));
    final visible = _visiblePosts;
    if (visible.isEmpty) {
      // Letztes Bild war's — Detail schließen.
      Navigator.of(context).maybePop();
      return;
    }
    // Cursor neu positionieren: gleicher Index, aber innerhalb der
    // jetzt kürzeren Liste. Wenn wir am Ende standen, eins zurück.
    final next = _currentIndex.clamp(0, visible.length - 1);
    setState(() => _currentIndex = next);
    // PageController auf den neuen Index ziehen, falls er außerhalb liegt.
    if (_controller.hasClients) {
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePosts;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: 'Zurück',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: visible.isEmpty
          ? const SizedBox.shrink()
          : PageView.builder(
              controller: _controller,
              scrollDirection: Axis.vertical,
              itemCount: visible.length,
              onPageChanged: (i) => _currentIndex = i,
              itemBuilder: (_, i) => FeedPostPage(
                post: visible[i],
                onDeleted: _handleDeleted,
              ),
            ),
    );
  }
}
