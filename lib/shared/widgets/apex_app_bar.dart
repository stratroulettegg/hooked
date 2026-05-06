import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../services/app_providers.dart';
import '../services/firebase/auth_providers.dart';

/// Einheitlicher AppBar für die gesamte App: HOOKED Branding + Menü-Button.
/// Unterstützt zusätzliche Actions links vom Menü und den standardmäßigen
/// Zurück-Pfeil (automatisch, wenn canPop).
class ApexAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ApexAppBar({
    super.key,
    this.extraActions = const [],
    this.leading,
  });

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
        const HeaderMenuButton(),
        const SizedBox(width: 4),
      ],
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

class _HeaderMenuButtonState extends ConsumerState<HeaderMenuButton> {
  final GlobalKey _anchor = GlobalKey();

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
      try {
        activeRoute = GoRouter.of(
          context,
        ).routerDelegate.currentConfiguration.uri.path;
      } catch (_) {}
    }

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
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _anchor,
      tooltip: 'Menü',
      icon: const Icon(Icons.menu_rounded, color: ApexColors.primary),
      onPressed: _open,
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
    final user = ref.watch(currentUserProvider);
    final isLoggedIn = user != null;
    final route = activeRoute;

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
            _ProfileHeader(
              user: user,
              isLoggedIn: isLoggedIn,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop();
                context.push(isLoggedIn ? '/profile' : '/auth');
              },
            ),
            Divider(height: 1, thickness: 1, color: c.border),
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
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String path) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    context.push(path);
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.isLoggedIn,
    required this.onTap,
  });

  final User? user;
  final bool isLoggedIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final name = isLoggedIn
        ? (user?.displayName?.trim().isNotEmpty == true
              ? user!.displayName!
              : 'Profil')
        : 'Nicht angemeldet';
    final subtitle = isLoggedIn
        ? (user?.email ?? 'Tippe für dein Profil')
        : 'Tippen, um dich anzumelden';
    final photo = isLoggedIn ? user?.photoURL : null;
    final initials = _initials(name, fallback: isLoggedIn ? '?' : '+');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ApexColors.primary.withAlpha(28),
                border: Border.all(color: ApexColors.primary, width: 2),
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
                      initials,
                      style: const TextStyle(
                        fontFamily: 'Rajdhani',
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: ApexColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  static String _initials(String name, {required String fallback}) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return fallback;
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

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
