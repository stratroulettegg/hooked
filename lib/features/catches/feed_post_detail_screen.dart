import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/services/firebase/feed_service.dart';
import 'catch_list_screen.dart' show FeedPostPage;

/// Vollbild-Ansicht eines Feed-Beitrags mit vertikalem Swipe zwischen
/// Posts derselben Liste — gleiche Mechanik wie der Community-Feed.
/// Wird vom Profil-Grid gepusht.
class FeedPostDetailScreen extends StatefulWidget {
  const FeedPostDetailScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
  });

  final List<FeedPost> posts;
  final int initialIndex;

  @override
  State<FeedPostDetailScreen> createState() => _FeedPostDetailScreenState();
}

class _FeedPostDetailScreenState extends State<FeedPostDetailScreen> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        itemCount: widget.posts.length,
        itemBuilder: (_, i) => FeedPostPage(post: widget.posts[i]),
      ),
    );
  }
}
