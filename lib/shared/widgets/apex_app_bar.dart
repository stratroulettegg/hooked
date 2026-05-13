import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../services/app_providers.dart';
import '../services/firebase/auth_providers.dart';
import '../services/firebase/auth_service.dart';
import '../services/inbox_providers.dart';
import 'app_toast.dart';

/// Einheitlicher AppBar für die gesamte App: HOOKED Branding + Menü-Button.
/// Unterstützt zusätzliche Actions links vom Menü und den standardmäßigen
/// Zurück-Pfeil (automatisch, wenn canPop).
class ApexAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ApexAppBar({super.key, this.extraActions = const [], this.leading});

  final List<Widget> extraActions;

  /// Optionales Leading-Widget (z. B. ein Zurück-Pfeil, der nicht via
  /// Navigator.pop, sondern lokal einen Tab/State zurücksetzt).
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    return AppBar(
      leading: leading,
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HOOKED',
              style: TextStyle(
                color: ApexColors.primary,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                fontSize: 22,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 1.5),
              child: Text(
                'DEIN FANGTAGEBUCH',
                style: TextStyle(
                  color: c.textMuted,
                  letterSpacing: 2,
                  fontSize: 10,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ...extraActions,
        const _AvatarButton(),
        const HeaderMenuButton(),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Avatar-Button rechts in der AppBar — Tap öffnet das eigene Profil
/// (oder den Login, falls nicht angemeldet).
class _AvatarButton extends ConsumerWidget {
  const _AvatarButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isLoggedIn = user != null;
    final photo = user?.photoURL;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          // Immer auf den Profil-Screen — der zeigt entweder das eigene
          // Profil oder den Login-CTA inkl. Einstellungen-Button für
          // nicht-angemeldete User.
          context.push('/profile');
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ApexColors.primary.withAlpha(28),
              border: Border.all(color: ApexColors.primary, width: 1.5),
              image: photo != null
                  ? DecorationImage(
                      image: NetworkImage(photo),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: photo == null
                ? Icon(
                    isLoggedIn ? Icons.person : Icons.person_outline,
                    color: ApexColors.primary,
                    size: 16,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Menü-Button für den AppBar: öffnet ein animiertes Drop-Down-Panel mit
/// Profil-Header, Schnell-Navigation und Theme-Umschaltung.
class HeaderMenuButton extends ConsumerStatefulWidget {
  const HeaderMenuButton({super.key});

  @override
  ConsumerState<HeaderMenuButton> createState() => _HeaderMenuButtonState();
}

class _HeaderMenuButtonState extends ConsumerState<HeaderMenuButton>
    with SingleTickerProviderStateMixin {
  final GlobalKey _anchor = GlobalKey();
  late final AnimationController _iconCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void dispose() {
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    HapticFeedback.selectionClick();
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final screenSize = overlay.size;
    String activeRoute = '';
    try {
      activeRoute = GoRouterState.of(context).matchedLocation;
    } catch (_) {
      // GoRouterState ist beim ersten Build nicht immer da — fallback.
      try {
        activeRoute = GoRouter.of(
          context,
        ).routerDelegate.currentConfiguration.uri.path;
      } catch (e) {
        debugPrint('apex_app_bar route lookup: $e');
      }
    }

    _iconCtrl.forward();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Menü schließen',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return _MenuPanelOverlay(
          anchorOrigin: origin,
          screenSize: screenSize,
          animation: curved,
          activeRoute: activeRoute,
        );
      },
    );
    if (mounted) _iconCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final unread = user == null ? 0 : ref.watch(inboxUnreadCountProvider);
    return Stack(
      key: _anchor,
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'Menü',
          iconSize: 34,
          icon: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _iconCtrl,
            color: ApexColors.primary,
            size: 34,
          ),
          onPressed: _open,
        ),
        if (unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: ApexColors.strike,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// Positioniert das Menü unterhalb des Anchor-Buttons (oben rechts) und
/// animiert es mit Slide + Fade ein. Nimmt sich automatisch genug Platz nach
/// links, ohne über den Bildschirmrand zu laufen.
class _MenuPanelOverlay extends StatelessWidget {
  const _MenuPanelOverlay({
    required this.anchorOrigin,
    required this.screenSize,
    required this.animation,
    required this.activeRoute,
  });

  final Offset anchorOrigin;
  final Size screenSize;
  final Animation<double> animation;
  final String activeRoute;

  @override
  Widget build(BuildContext context) {
    const panelWidth = 280.0;
    const horizontalPadding = 8.0;
    final right = (screenSize.width - anchorOrigin.dx).clamp(
      horizontalPadding,
      screenSize.width - panelWidth - horizontalPadding,
    );
    final top = anchorOrigin.dy + 6;
    return Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          width: panelWidth,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.04),
                end: Offset.zero,
              ).animate(animation),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
                alignment: Alignment.topRight,
                child: _MenuPanel(activeRoute: activeRoute),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuPanel extends ConsumerWidget {
  const _MenuPanel({required this.activeRoute});

  final String activeRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final c = ApexColors.of(context);
    final route = activeRoute;
    final user = ref.watch(currentUserProvider);
    final unread = user == null ? 0 : ref.watch(inboxUnreadCountProvider);

    return Material(
      color: c.surface,
      elevation: 12,
      shadowColor: Colors.black.withAlpha(60),
      surfaceTintColor: ApexColors.primary.withAlpha(8),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Account-Header — zeigt sofort, "wer bin ich gerade".
            _AccountHeader(user: user),
            Divider(height: 1, thickness: 1, color: c.border),
            // Inbox-Block.
            const SizedBox(height: 6),
            _MenuTile(
              icon: Icons.notifications_none_rounded,
              label: 'Benachrichtigungen',
              active: route == '/notifications',
              badge: unread,
              onTap: () => _navigate(context, '/notifications'),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, thickness: 1, color: c.border),
            // Gameification-Block.
            const SizedBox(height: 6),
            _MenuTile(
              icon: Icons.flag_rounded,
              label: 'Missionen',
              active: route == '/missions',
              onTap: () => _navigate(context, '/missions'),
            ),
            _MenuTile(
              icon: Icons.emoji_events_rounded,
              label: 'Köderlevel',
              active: route == '/lure-levels',
              onTap: () => _navigate(context, '/lure-levels'),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, thickness: 1, color: c.border),
            // Stats / Tools-Block.
            const SizedBox(height: 6),
            _MenuTile(
              icon: Icons.menu_book_rounded,
              label: 'Fischlexikon',
              active: route == '/lexicon',
              onTap: () => _navigate(context, '/lexicon'),
            ),
            _MenuTile(
              icon: Icons.water_drop_rounded,
              label: 'Tage am Wasser',
              active: route == '/water-days',
              onTap: () => _navigate(context, '/water-days'),
            ),
            _MenuTile(
              icon: Icons.workspace_premium_rounded,
              label: 'Rekorde',
              active: route == '/records',
              onTap: () => _navigate(context, '/records'),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, thickness: 1, color: c.border),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'DESIGN',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _ThemeSegments(
                value: themeMode,
                onChanged: (mode) {
                  HapticFeedback.selectionClick();
                  ref.read(themeModeProvider.notifier).state = mode;
                },
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.border),
            const SizedBox(height: 4),
            _MenuTile(
              icon: Icons.settings_rounded,
              label: 'Einstellungen',
              active: route == '/settings',
              onTap: () => _navigate(context, '/settings'),
            ),
            if (user != null) ...[
              if (user.isAnonymous) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: _SignInPromo(
                    onTap: () => _navigate(context, '/auth'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                _MenuTile(
                  icon: Icons.logout_rounded,
                  label: 'Abmelden',
                  active: false,
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    HapticFeedback.selectionClick();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text(
          'Du wirst von Hooked abgemeldet. Deine F\u00e4nge bleiben gespeichert '
          'und sind nach erneuter Anmeldung wieder verf\u00fcgbar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    // Men\u00fc-Overlay schlie\u00dfen.
    Navigator.of(context).pop();
    try {
      await AuthService.instance.signOut();
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Abmelden fehlgeschlagen: $e');
      }
    }
  }

  void _navigate(BuildContext context, String path) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    context.push(path);
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: active ? ApexColors.primary.withAlpha(22) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? ApexColors.primary : c.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? ApexColors.primary : c.textPrimary,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ApexColors.strike,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
            if (active)
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: ApexColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSegments extends StatelessWidget {
  const _ThemeSegments({required this.value, required this.onChanged});
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    Widget seg(ThemeMode mode, IconData icon, String label) {
      final selected = value == mode;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? ApexColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? c.background : c.textSecondary,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: selected ? c.background : c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Row(
        children: [
          seg(ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
          seg(ThemeMode.light, Icons.wb_sunny_rounded, 'Hell'),
          seg(ThemeMode.dark, Icons.nights_stay_rounded, 'Dunkel'),
        ],
      ),
    );
  }
}

/// Account-Header oben im Burger-Menü — zeigt sofort, _wer_ gerade
/// eingeloggt ist (oder dass es sich um ein anonymes Geräte-Konto handelt).
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final isAnon = user == null || user!.isAnonymous;
    final name = isAnon
        ? 'Anonymes Konto'
        : (user!.displayName?.trim().isNotEmpty == true
              ? user!.displayName!.trim()
              : (user!.email ?? 'Angemeldet'));
    final sub = isAnon
        ? 'Geräte-Konto · keine Anmeldung'
        : (user!.email ?? 'Angemeldet');
    final photo = user?.photoURL;
    final initial = isAnon
        ? '?'
        : (name.isNotEmpty ? name.characters.first.toUpperCase() : '?');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ApexColors.primary.withAlpha(28),
              border: Border.all(color: ApexColors.primary, width: 1.5),
              image: photo != null
                  ? DecorationImage(
                      image: NetworkImage(photo),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: photo == null
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: ApexColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Conversion-Slot im Burger-Menü für anonyme User: macht aus dem
/// anonymen "Anmelden"-Tile ein klares Wertversprechen mit primärem CTA.
class _SignInPromo extends StatelessWidget {
  const _SignInPromo({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: ApexColors.primary.withAlpha(18),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ApexColors.primary.withAlpha(90),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    size: 18,
                    color: ApexColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Werde Teil der Community',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Posten, kommentieren, folgen — mit eigenem Profil. Kostenlos, EU-Server, jederzeit löschbar.',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: ApexColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Anmelden',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.black,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
