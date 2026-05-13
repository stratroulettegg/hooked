import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/feed_service.dart';
import '../../shared/services/firebase/user_profile_providers.dart';
import '../../shared/services/firebase/user_profile_service.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/moderation_actions.dart';
import 'widgets/like_burst.dart';

class CommunityFeedView extends ConsumerStatefulWidget {
  const CommunityFeedView({
    super.key,
    this.initialPostId,
    this.openComments = false,
    this.commentsRequestId = 0,
  });

  /// Wenn gesetzt, springt der Pager beim ersten Render zu diesem Post.
  final String? initialPostId;

  /// Wenn `true` (zusammen mit `initialPostId`), wird automatisch das
  /// Kommentar-Sheet geöffnet — z. B. wenn der User von einer
  /// Kommentar-Benachrichtigung kommt.
  final bool openComments;

  /// Nonce, die sich bei jedem Tap erhöht (siehe `FeedScreen`).
  final int commentsRequestId;

  @override
  ConsumerState<CommunityFeedView> createState() => CommunityFeedViewState();
}

class CommunityFeedViewState extends ConsumerState<CommunityFeedView> {
  PageController? _pager;
  bool _didJump = false;
  int? _handledCommentsRequestId;

  @override
  void didUpdateWidget(covariant CommunityFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Wenn der Pager-Sprung-Wunsch sich ändert (anderer Post), sollen
    // wir erneut hinscrollen.
    if (oldWidget.initialPostId != widget.initialPostId) {
      _didJump = false;
    }
  }

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    // Bewusst `signedInUserProvider`: anonyme Auto-Login-Sessions sehen
    // den Feed nicht, da sie sich nicht moderieren lassen (Block/Report
    // greift nur gegen echte Identitäten).
    final user = ref.watch(signedInUserProvider);
    if (user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: c.textMuted),
              const SizedBox(height: 12),
              Text(
                'Nur für eingeloggte Angler:innen',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Melde dich an, um den Community-Feed zu sehen und eigene Fänge zu teilen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.push('/auth'),
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Anmelden'),
              ),
            ],
          ),
        ),
      );
    }
    final feedAsync = ref.watch(feedPostsProvider);
    return feedAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: ApexColors.primary,
          strokeWidth: 2,
        ),
      ),
      error: (e, _) {
        // Permission-Denied tritt typisch beim Logout/Login-Wechsel auf,
        // bevor der Stream auf den neuen Auth-State umgeschwenkt ist.
        // Statt einer rohen Exception zeigen wir einen freundlichen Hinweis.
        final msg = e.toString().toLowerCase();
        final isPermission =
            msg.contains('permission-denied') ||
            msg.contains('permission_denied');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPermission ? Icons.lock_outline : Icons.cloud_off,
                  size: 56,
                  color: c.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  isPermission
                      ? 'Feed gerade nicht verfügbar'
                      : 'Verbindungsproblem',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isPermission
                      ? 'Bitte einen Moment warten oder die App neu starten.'
                      : 'Prüfe deine Internetverbindung und versuche es erneut.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(feedPostsProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        );
      },
      data: (posts) {
        if (posts.isEmpty) {
          return EmptyStateView(
            icon: Icons.public_outlined,
            title: 'Noch keine Community-Fänge',
            description:
                'Sei der erste hier! Trage einen Fang ein und aktiviere den Schalter "In Community-Feed teilen".',
            ctaLabel: 'Fang teilen',
            ctaIcon: Icons.add,
            onCta: () => context.push('/catches/add'),
          );
        }
        // Vertikaler Vollbild-Pager – analog zur Catch-Detail-Ansicht.
        // Wenn ein initialPostId übergeben wurde, springt der Pager dorthin
        // (entweder direkt beim ersten Build oder per animateTo, sobald die
        // Posts eingetroffen sind).
        final initialIdx = widget.initialPostId == null
            ? 0
            : posts.indexWhere((p) => p.id == widget.initialPostId);
        final startIdx = initialIdx < 0 ? 0 : initialIdx;
        _pager ??= PageController(initialPage: startIdx);
        if (!_didJump && widget.initialPostId != null && initialIdx >= 0) {
          _didJump = true;
          // Falls Posts erst später eintreffen (Stream): nach dem Build
          // noch sanft hinscrollen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final p = _pager;
            if (p != null && p.hasClients) {
              p.animateToPage(
                startIdx,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
              );
            }
          });
        }
        // Auto-Open Comments-Sheet (z. B. aus Kommentar-Benachrichtigung).
        // Nonce-basiert: Nur öffnen, wenn die requestId noch nicht
        // bearbeitet wurde — damit wiederholte Taps wieder triggern.
        if (widget.openComments &&
            widget.initialPostId != null &&
            initialIdx >= 0 &&
            _handledCommentsRequestId != widget.commentsRequestId) {
          _handledCommentsRequestId = widget.commentsRequestId;
          final pid = posts[startIdx].id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            FeedPostPage.openCommentsFor(context, pid);
          });
        }
        return PageView.builder(
          controller: _pager,
          scrollDirection: Axis.vertical,
          itemCount: posts.length,
          itemBuilder: (_, i) => FeedPostPage(post: posts[i]),
        );
      },
    );
  }
}

/// Eine Feed-Seite im Stil der eigenen Detailansicht: Foto als Hero,
/// halbtransparentes Blur-Sheet mit den Details darüber.
/// Vollbild-Ansicht eines Community-Feed-Beitrags. Wird sowohl im
/// Community-Tab (PageView) als auch vom Profil-Grid (Push-Route) genutzt,
/// damit Tap auf einen Post-Thumbnail die identische Darstellung liefert.
class FeedPostPage extends ConsumerStatefulWidget {
  const FeedPostPage({super.key, required this.post, this.onDeleted});

  final FeedPost post;

  /// Wird aufgerufen, nachdem der Owner seinen eigenen Post erfolgreich
  /// gelöscht hat. Erlaubt dem Container (z.\u202fB. dem Detail-Screen),
  /// auf den nächsten Post zu wechseln oder den Screen zu schließen.
  final void Function(String postId)? onDeleted;

  /// Öffnet das Kommentar-Sheet für einen Post von außen (z. B. wenn der
  /// User von einer Kommentar-Benachrichtigung kommt). Identische Optik
  /// wie der interne `_openComments`-Aufruf.
  static void openCommentsFor(BuildContext context, String postId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeedCommentsSheet(postId: postId),
    );
  }

  @override
  ConsumerState<FeedPostPage> createState() => _FeedPostPageState();
}

class _FeedPostPageState extends ConsumerState<FeedPostPage>
    with TickerProviderStateMixin {
  // „Desired state“-Modell: was der User WILL — unabhängig vom Server.
  // null = User-Wunsch deckt sich mit Server (kein Override).
  bool? _desiredLiked;

  // Wir lassen immer nur EINEN toggleLike-Call gleichzeitig laufen.
  // Nach Abschluss vergleichen wir _desiredLiked mit dem (dann
  // hoffentlich aktualisierten) Server-Zustand und feuern bei Bedarf
  // den nächsten Toggle. So flackert die Zahl nie.
  bool _inFlight = false;

  // Heart-Burst-Animation für Double-Tap. _burstLike merkt sich, ob das
  // Burst ein Like (rotes Herz, fliegt nach oben) oder Unlike (gebrochenes
  // Herz, sinkt nach unten) darstellt.
  late final AnimationController _burstCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _burstLike = true;

  @override
  void dispose() {
    _burstCtrl.dispose();
    super.dispose();
  }

  FeedPost get post => widget.post;

  @override
  void didUpdateWidget(covariant FeedPostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stream hat einen neuen Snapshot geliefert. Falls der User
    // weiteren Klick(s) gemacht hat, während der Toggle lief, jetzt
    // nachziehen.
    _syncIfNeeded();
  }

  /// Was der User aktuell sieht (Override vor Server).
  bool _displayLiked(bool serverLiked) => _desiredLiked ?? serverLiked;

  /// Konsistenter Zähler: Server-Wert + 1/-1, falls Override abweicht.
  int _displayCount(int serverCount, bool serverLiked) {
    final desired = _desiredLiked;
    if (desired == null || desired == serverLiked) return serverCount;
    final adjusted = desired ? serverCount + 1 : serverCount - 1;
    return adjusted < 0 ? 0 : adjusted;
  }

  /// User drückt Like/Unlike-Button (Toggle).
  void _onLikeTap() {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final serverLiked = post.likedBy.contains(me.uid);
    final current = _desiredLiked ?? serverLiked;
    HapticFeedback.lightImpact();
    setState(() => _desiredLiked = !current);
    _syncIfNeeded();
  }

  /// Doppel-Tap auf das Foto: Burst-Animation + Like toggeln.
  /// Like → fliegendes rotes Herz mit Funken; Unlike → gebrochenes Herz fällt.
  void _onDoubleTapLike() {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final serverLiked = post.likedBy.contains(me.uid);
    final current = _desiredLiked ?? serverLiked;
    final next = !current;
    HapticFeedback.mediumImpact();
    setState(() {
      _burstLike = next;
      _desiredLiked = next;
    });
    _burstCtrl.forward(from: 0);
    _syncIfNeeded();
  }

  /// Schiebt den Server-Zustand auf _desiredLiked. Nur ein Call gleichzeitig.
  Future<void> _syncIfNeeded() async {
    if (_inFlight) return;
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final desired = _desiredLiked;
    if (desired == null) return;
    final serverLiked = widget.post.likedBy.contains(me.uid);
    if (desired == serverLiked) {
      // Server hat aufgeholt — Override auflösen.
      if (mounted) setState(() => _desiredLiked = null);
      return;
    }
    _inFlight = true;
    try {
      await ref.read(feedServiceProvider).toggleLike(widget.post.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _desiredLiked = null);
      AppToast.error(context, 'Like fehlgeschlagen: $e');
      return;
    } finally {
      _inFlight = false;
    }
    // Der Snapshot kommt asynchron via didUpdateWidget → dort triggern wir
    // _syncIfNeeded() erneut, falls der User zwischenzeitlich weiter
    // geklickt hat.
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tg.';
    return AppDateFormats.dayMonthYearShort.format(when);
  }

  FishSpecies? _species() {
    for (final s in FishSpecies.values) {
      if (s.name == post.species) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final species = _species();
    final speciesLabel = species?.displayName ?? post.species;
    final hasPhoto = post.photoUrl != null && post.photoUrl!.isNotEmpty;
    final hasWater =
        post.waterBodyName != null && post.waterBodyName!.isNotEmpty;
    final hasLure = post.lure != null && post.lure!.isNotEmpty;
    final lureText = hasLure
        ? (post.lureColor?.isNotEmpty == true
              ? '${post.lure} · ${post.lureColor}'
              : post.lure!)
        : null;
    final authorProfile = ref
        .watch(userProfileProvider(post.userId))
        .valueOrNull;
    final liveName = authorProfile?.displayName?.trim();
    final livePhoto = authorProfile?.photoUrl;
    final authorName = (liveName != null && liveName.isNotEmpty)
        ? liveName
        : (post.userName?.isNotEmpty == true ? post.userName! : 'Angler:in');
    final authorPhotoUrl = (livePhoto != null && livePhoto.isNotEmpty)
        ? livePhoto
        : post.userPhotoUrl;
    final me = ref.watch(currentUserProvider);
    final serverLiked = me != null && post.likedBy.contains(me.uid);
    final liked = _displayLiked(serverLiked);
    final likeCount = _displayCount(post.likeCount, serverLiked);

    return Stack(
      children: [
        // Hero: Netz-Foto oder Fallback-Gradient mit Lexikon-Asset.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: me == null ? null : _onDoubleTapLike,
            child: _FeedHeroBackdrop(
              photoUrl: hasPhoto ? post.photoUrl : null,
              speciesAsset: species?.imageAsset,
              speciesLabel: speciesLabel,
            ),
          ),
        ),

        // Heart-Burst-Overlay (Double-Tap). Like → rotes Herz fliegt
        // mit 6 Funken-Herzen nach oben. Unlike → gebrochenes Herz fällt
        // und fadet aus.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _burstCtrl,
              builder: (_, __) {
                final v = _burstCtrl.value;
                if (v == 0) return const SizedBox.shrink();
                return LikeBurst(progress: v, isLike: _burstLike);
              },
            ),
          ),
        ),

        // Sanfter Dunkel-Gradient am Bildunterrand fuer garantierten
        // Kontrast — egal wie hell das Foto ist.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 360,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(40),
                    Colors.black.withAlpha(140),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Unten: Action-Spalte rechts, darunter Meta-Pills, darunter Sheet.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action-Spalte rechts.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _FeedActionButton(
                          icon: liked ? Icons.favorite : Icons.favorite_border,
                          iconColor: liked ? ApexColors.scoreLow : Colors.white,
                          count: likeCount,
                          highlighted: liked,
                          onTap: me == null ? null : _onLikeTap,
                        ),
                        const SizedBox(height: 14),
                        _FeedActionButton(
                          icon: Icons.mode_comment_outlined,
                          iconColor: Colors.white,
                          count: post.commentCount,
                          highlighted: false,
                          onTap: me == null
                              ? null
                              : () => _openComments(context, post.id),
                        ),
                        if (me != null) ...[
                          const SizedBox(height: 14),
                          _FeedMoreButton(
                            onTap: () => _showPostMenu(context, ref),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Floating Glas-Pills (auf dem Bild, knapp ueber dem Sheet).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (post.lengthCm != null)
                      _metaPill(
                        c,
                        Icons.straighten,
                        '${post.lengthCm!.toStringAsFixed(0)} cm',
                      ),
                    _metaPill(
                      c,
                      Icons.access_time,
                      _relativeTime(post.createdAt),
                    ),
                    if (hasWater)
                      _metaPill(
                        c,
                        Icons.water,
                        post.waterBodyName!,
                        accent: true,
                      ),
                    if (hasLure)
                      _metaPill(c, Icons.set_meal_outlined, lureText!),
                  ],
                ),
              ),

              // Floating Blur-Sheet \u2013 nur Spezies/Gewicht + Autor.
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(60),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: ColoredBox(
                      color: c.background.withAlpha(110),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        speciesLabel,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Rajdhani',
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          height: 1.05,
                                          letterSpacing: 0.3,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (post.weightG != null) ...[
                                      const SizedBox(width: 10),
                                      Text(
                                        AppNum.kg(post.weightG!),
                                        style: const TextStyle(
                                          fontFamily: 'Rajdhani',
                                          fontSize: 20,
                                          color: ApexColors.primary,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Autor: Name + Datum + Avatar (rechts).
                              // Tap → öffentliches Profil des Autors.
                              InkWell(
                                onTap: () =>
                                    context.push('/user/${post.userId}'),
                                borderRadius: BorderRadius.circular(8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 140,
                                          ),
                                          child: Text(
                                            authorName,
                                            textAlign: TextAlign.end,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          AppDateFormats.dayMonthYearShort
                                              .format(post.caughtAt),
                                          style: TextStyle(
                                            color: c.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: c.border,
                                          backgroundImage:
                                              (authorPhotoUrl != null &&
                                                  authorPhotoUrl.isNotEmpty)
                                              ? NetworkImage(authorPhotoUrl)
                                              : null,
                                          child:
                                              (authorPhotoUrl == null ||
                                                  authorPhotoUrl.isEmpty)
                                              ? Icon(
                                                  Icons.person,
                                                  size: 24,
                                                  color: c.textMuted,
                                                )
                                              : null,
                                        ),
                                        if (me != null && me.uid != post.userId)
                                          Positioned(
                                            right: -10,
                                            bottom: -10,
                                            child: _QuickFollowBadge(
                                              targetUid: post.userId,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Schwebende Glas-Pill, die direkt auf dem Bild liegt.
  /// `accent: true` markiert wichtige Infos (z. B. Gewässer) mit
  /// Primary-Tönung – sticht zwischen den anderen Pills hervor.
  Widget _metaPill(
    ApexColors c,
    IconData icon,
    String text, {
    bool accent = false,
  }) {
    final iconColor = accent ? ApexColors.primary : Colors.white.withAlpha(230);
    final bgAlpha = accent ? 90 : 70;
    final borderColor = accent
        ? ApexColors.primary.withAlpha(120)
        : Colors.white.withAlpha(45);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(bgAlpha),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 0.7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent ? Colors.white : Colors.white,
                  letterSpacing: 0.4,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openComments(BuildContext context, String postId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Über dem Root-Navigator anzeigen, damit das Sheet auch
      // den globalen FAB („+"-Quick-Add) überdeckt.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeedCommentsSheet(postId: postId),
    );
  }

  /// Bottom-Sheet mit Aktionen für einen Feed-Post.
  /// - Eigener Post: Löschen (markiert lokalen Fang als nicht-geteilt).
  /// - Fremder Post: Melden + Nutzer blockieren.
  void _showPostMenu(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final me = ref.read(currentUserProvider);
    final isMine = me != null && me.uid == post.userId;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              color: c.background.withAlpha(235),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (isMine)
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        color: ApexColors.strike,
                      ),
                      title: Text(
                        'Beitrag löschen',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Dein Fang bleibt im Tagebuch erhalten.',
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        final ok = await confirmDeleteOwnPost(
                          context,
                          ref,
                          postId: post.id,
                        );
                        if (ok) widget.onDeleted?.call(post.id);
                      },
                    )
                  else ...[
                    ListTile(
                      leading: Icon(
                        Icons.flag_outlined,
                        color: ApexColors.scoreLow,
                      ),
                      title: Text(
                        'Beitrag melden',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await showReportSheet(
                          context,
                          ref,
                          kind: ModerationTargetKind.post,
                          postId: post.id,
                          targetUid: post.userId,
                        );
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.block, color: ApexColors.scoreLow),
                      title: Text(
                        'Nutzer blockieren',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Du siehst keine Beiträge mehr von ${post.userName?.isNotEmpty == true ? post.userName! : "diesem Nutzer"}.',
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await confirmBlockUser(
                          context,
                          ref,
                          targetUid: post.userId,
                          targetName: post.userName,
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runder Glas-Button mit Icon + Counter (rechte Action-Spalte).
/// Animiert das Icon kurz beim Aktivieren (Like).
class _FeedActionButton extends StatefulWidget {
  const _FeedActionButton({
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final Color iconColor;
  final int count;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  State<_FeedActionButton> createState() => _FeedActionButtonState();
}

class _FeedActionButtonState extends State<_FeedActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(covariant _FeedActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted && !oldWidget.highlighted) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.35,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.35,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_ctrl);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.highlighted
                    ? ApexColors.scoreLow.withAlpha(120)
                    : Colors.black.withAlpha(120),
                blurRadius: widget.highlighted ? 18 : 12,
                spreadRadius: widget.highlighted ? 1 : 0,
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Material(
                color: Colors.black.withAlpha(90),
                shape: const CircleBorder(
                  side: BorderSide(color: Color(0x40FFFFFF), width: 0.7),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onTap,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Center(
                      child: ScaleTransition(
                        scale: scale,
                        child: Icon(
                          widget.icon,
                          color: widget.iconColor,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Counter immer anzeigen (auch bei 0) – verhindert Layout-Shift,
        // wenn der erste Like/Kommentar dazukommt.
        const SizedBox(height: 5),
        Text(
          _fmt(widget.count),
          style: const TextStyle(
            fontFamily: 'Rajdhani',
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Colors.white,
            letterSpacing: 0.3,
            shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
          ),
        ),
      ],
    );
  }

  /// Kurzform für Counter: 1.2k, 12k.
  static String _fmt(int n) {
    if (n < 1000) return '$n';
    final k = n / 1000;
    return k < 10 ? '${k.toStringAsFixed(1)}k' : '${k.toStringAsFixed(0)}k';
  }
}

/// BottomSheet mit Live-Kommentar-Stream und Eingabefeld.
class _FeedCommentsSheet extends ConsumerStatefulWidget {
  const _FeedCommentsSheet({required this.postId});
  final String postId;

  @override
  ConsumerState<_FeedCommentsSheet> createState() => _FeedCommentsSheetState();
}

class _FeedCommentsSheetState extends ConsumerState<_FeedCommentsSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  String? _replyToId;
  String? _replyToName;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setReply(String? id, String? name) {
    setState(() {
      _replyToId = id;
      _replyToName = name;
    });
    if (id != null) _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(feedServiceProvider)
          .addComment(widget.postId, text, parentId: _replyToId);
      _ctrl.clear();
      _setReply(null, null);
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : 'Kommentar fehlgeschlagen: $e';
      AppToast.error(context, msg);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _relTime(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'jetzt';
    if (d.inMinutes < 60) return '${d.inMinutes} Min.';
    if (d.inHours < 24) return '${d.inHours} Std.';
    if (d.inDays < 7) return '${d.inDays} Tg.';
    return AppDateFormats.dayMonthYearShort.format(when);
  }

  /// Einzelner Kommentar (Top-Level oder Reply).
  /// `indent: 1` macht den Avatar etwas kleiner für Replies.
  Widget _commentTile(
    ApexColors c,
    dynamic me,
    FeedComment cm, {
    int indent = 0,
  }) {
    final isMine = me?.uid == cm.userId;
    final avatarRadius = indent == 0 ? 16.0 : 13.0;
    final iconSize = indent == 0 ? 18.0 : 14.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: avatarRadius,
          backgroundColor: c.border,
          backgroundImage:
              (cm.userPhotoUrl != null && cm.userPhotoUrl!.isNotEmpty)
              ? NetworkImage(cm.userPhotoUrl!)
              : null,
          child: (cm.userPhotoUrl == null || cm.userPhotoUrl!.isEmpty)
              ? Icon(Icons.person, size: iconSize, color: c.textMuted)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      cm.userName?.isNotEmpty == true
                          ? cm.userName!
                          : 'Angler:in',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _relTime(cm.createdAt),
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                cm.text,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              // Antworten-Action — auch für Replies erlaubt. Damit Threads
              // flach bleiben, hängen Antworten auf eine Antwort am selben
              // Top-Level-Kommentar (parentId der aktuellen Reply, sonst
              // die eigene id). Im Compose-Hint erscheint trotzdem der
              // Name der Person, auf die geantwortet wird.
              InkWell(
                onTap: () => _setReply(
                  cm.parentId ?? cm.id,
                  cm.userName?.isNotEmpty == true
                      ? cm.userName!
                      : 'Angler:in',
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'Antworten',
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isMine)
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: c.textMuted),
            onPressed: () async {
              try {
                await ref
                    .read(feedServiceProvider)
                    .deleteComment(widget.postId, cm.id);
              } catch (e) {
                if (!context.mounted) return;
                AppToast.error(context, 'Löschen fehlgeschlagen: $e');
              }
            },
          ),
        if (!isMine && me != null)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 18, color: c.textMuted),
            color: c.surface,
            onSelected: (v) async {
              if (v == 'report') {
                await showReportSheet(
                  context,
                  ref,
                  kind: ModerationTargetKind.comment,
                  postId: widget.postId,
                  commentId: cm.id,
                  targetUid: cm.userId,
                );
              } else if (v == 'block') {
                await confirmBlockUser(
                  context,
                  ref,
                  targetUid: cm.userId,
                  targetName: cm.userName,
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: ApexColors.scoreLow,
                    ),
                    const SizedBox(width: 8),
                    Text('Melden', style: TextStyle(color: c.textPrimary)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, size: 18, color: ApexColors.scoreLow),
                    const SizedBox(width: 8),
                    Text(
                      'Nutzer blockieren',
                      style: TextStyle(color: c.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final me = ref.watch(currentUserProvider);
    final commentsAsync = ref.watch(feedCommentsProvider(widget.postId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        // WICHTIG: MediaQuery aus dem Builder-Context lesen, damit
        // Tastatur-Insets live aktualisiert werden. `viewInsets.bottom`
        // = Tastatur-Höhe, `viewPadding.bottom` = System-Gestenleiste /
        // Home-Indicator. Wenn die Tastatur offen ist, ist die Gestenleiste
        // verdeckt (viewPadding=0) — dann reicht viewInsets allein.
        final mq = MediaQuery.of(ctx);
        final keyboard = mq.viewInsets.bottom;
        final safeBottom = mq.viewPadding.bottom;
        final bottomPad = keyboard > 0 ? keyboard : safeBottom;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: c.background.withAlpha(235),
                border: Border(top: BorderSide(color: c.border.withAlpha(120))),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 18,
                          color: c.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Kommentare',
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const Spacer(),
                        commentsAsync.maybeWhen(
                          data: (l) => Text(
                            '${l.length}',
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c.textMuted,
                            ),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: c.border.withAlpha(80)),
                  Expanded(
                    child: commentsAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: ApexColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Konnte Kommentare nicht laden.',
                            style: TextStyle(color: c.textMuted),
                          ),
                        ),
                      ),
                      data: (list) {
                        if (list.isEmpty) {
                          return Center(
                            child: Text(
                              'Noch keine Kommentare. Mach den Anfang!',
                              style: TextStyle(color: c.textMuted),
                            ),
                          );
                        }
                        // Top-Level + Replies (parentId) aufteilen.
                        final tops = <FeedComment>[];
                        final replies = <String, List<FeedComment>>{};
                        for (final cm in list) {
                          if (cm.parentId == null) {
                            tops.add(cm);
                          } else {
                            replies.putIfAbsent(cm.parentId!, () => []).add(cm);
                          }
                        }
                        return ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: tops.length,
                          itemBuilder: (context, i) {
                            final top = tops[i];
                            final children =
                                replies[top.id] ?? const <FeedComment>[];
                            return Padding(
                              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _commentTile(c, me, top, indent: 0),
                                  for (final r in children)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 10,
                                        left: 36,
                                      ),
                                      child: _commentTile(c, me, r, indent: 1),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Eingabefeld unten – als rounded Glas-Pill.
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: c.border.withAlpha(120)),
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(14, 10, 10, 10 + bottomPad),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Reply-Indikator: zeigt, an wen gerade geantwortet wird.
                        if (_replyToId != null) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                            decoration: BoxDecoration(
                              color: ApexColors.primary.withAlpha(30),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: ApexColors.primary.withAlpha(80),
                                width: 0.7,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.reply,
                                  size: 14,
                                  color: ApexColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Antwort an ${_replyToName ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _setReply(null, null),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: c.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: c.border.withAlpha(160),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: TextField(
                                  controller: _ctrl,
                                  focusNode: _focus,
                                  enabled: me != null && !_sending,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 14,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: me == null
                                        ? 'Anmelden, um zu kommentieren'
                                        : _replyToId != null
                                        ? 'Antworten…'
                                        : 'Kommentar schreiben…',
                                    hintStyle: TextStyle(color: c.textMuted),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: ApexColors.primary,
                              shape: const CircleBorder(),
                              elevation: 0,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: me == null || _sending ? null : _send,
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: _sending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.send,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Kleiner runder Glas-Button für sekundäre Aktionen (3-Punkte-Menü)
/// in der rechten Action-Spalte des Feed-Posts.
class _FeedMoreButton extends StatelessWidget {
  const _FeedMoreButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withAlpha(80),
          border: Border.all(color: Colors.white.withAlpha(40), width: 0.7),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 12),
          ],
        ),
        child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
      ),
    );
  }
}

class _FeedHeroBackdrop extends StatelessWidget {
  const _FeedHeroBackdrop({
    required this.photoUrl,
    required this.speciesAsset,
    required this.speciesLabel,
  });

  final String? photoUrl;
  final String? speciesAsset;
  final String speciesLabel;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    if (photoUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Hintergrund: dasselbe Foto stark geblurrt + abgedunkelt,
          // damit das Vollbild nicht abgeschnitten werden muss.
          Image.network(
            photoUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(color: c.background),
          ),
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withAlpha(120)),
          ),
          // Vordergrund: Foto füllt komplett, Crop ist okay damit
          // keine schwarzen Ränder oben/unten entstehen.
          Image.network(
            photoUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(
                  color: ApexColors.primary,
                  strokeWidth: 2,
                ),
              );
            },
            errorBuilder: (_, __, ___) =>
                _FallbackHero(asset: speciesAsset, label: speciesLabel),
          ),
          // Sanftes Vignetten-Gradient für Lesbarkeit der unteren Pills.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
                stops: [0.6, 1.0],
              ),
            ),
          ),
        ],
      );
    }
    return _FallbackHero(asset: speciesAsset, label: speciesLabel);
  }
}

class _FallbackHero extends StatelessWidget {
  const _FallbackHero({required this.asset, required this.label});
  final String? asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    if (asset != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(asset!, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
                stops: [0.6, 1.0],
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.surface, c.background],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported, size: 64, color: c.textMuted),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// QUICK FOLLOW BADGE (Avatar-Overlay im Feed)
// ═══════════════════════════════════════════════════════════════════════════

/// Kleiner runder „+"-Badge, der unten rechts auf dem Autor-Avatar sitzt.
/// Optimistisch: Tap setzt den Folge-Status sofort, der Server-Write laeuft
/// im Hintergrund. Nach erfolgreichem Folgen verschwindet der Badge.
class _QuickFollowBadge extends ConsumerStatefulWidget {
  const _QuickFollowBadge({required this.targetUid});
  final String targetUid;

  @override
  ConsumerState<_QuickFollowBadge> createState() => _QuickFollowBadgeState();
}

class _QuickFollowBadgeState extends ConsumerState<_QuickFollowBadge> {
  bool? _override;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isFollowingAsync = ref.watch(isFollowingProvider(widget.targetUid));
    final serverFollowing = isFollowingAsync.valueOrNull ?? false;
    // Override aufloesen, sobald der Server eingefangen hat — egal ob
    // wir den Toggle hier oder anderswo (Profil-Screen) ausgeloest haben.
    if (_override != null && _override == serverFollowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _override == serverFollowing) {
          setState(() => _override = null);
        }
      });
    }
    final isFollowing = _override ?? serverFollowing;

    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Material(
          color: isFollowing ? Colors.white : ApexColors.primary,
          shape: CircleBorder(
            side: BorderSide(
              color: isFollowing ? ApexColors.primary : Colors.white,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: _busy ? null : _toggle,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Icon(
                isFollowing ? Icons.remove : Icons.add,
                size: 16,
                color: isFollowing ? ApexColors.primary : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    final isFollowingAsync = ref.read(isFollowingProvider(widget.targetUid));
    final serverFollowing = isFollowingAsync.valueOrNull ?? false;
    final currentlyFollowing = _override ?? serverFollowing;
    final next = !currentlyFollowing;
    setState(() {
      _override = next;
      _busy = true;
    });
    final blocked =
        ref.read(blockedUidsProvider).valueOrNull ?? const <String>{};
    try {
      await UserProfileService.instance.toggleFollow(
        widget.targetUid,
        blockedUids: blocked,
      );
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _override = currentlyFollowing);
      AppToast.error(
        context,
        e.message == 'blocked'
            ? 'Du kannst diesem Nutzer nicht folgen, weil du ihn blockiert hast.'
            : 'Aktion nicht möglich.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _override = currentlyFollowing);
      AppToast.error(context, 'Konnte Status nicht ändern.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
