import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/auth_service.dart';
import '../../shared/services/notifications/notification_prefs.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Zeigt Profil-Info und bietet Logout / Account l\u00f6schen.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final c = ApexColors.of(context);

    if (user == null) {
      // Nicht angemeldet \u2192 direkt auf Login.
      return Scaffold(
        appBar: const ApexAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, size: 64, color: c.textMuted),
                const SizedBox(height: 12),
                Text(
                  'Nicht angemeldet',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Melde dich an, um Trips mit anderen zu teilen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.push('/auth'),
                  icon: const Icon(Icons.login),
                  label: const Text('Anmelden'),
                ),
                const SizedBox(height: 24),
                _NotificationsTile(),
              ],
            ),
          ),
        ),
      );
    }

    final email = user.email ?? '\u2014';
    final name = user.displayName?.trim();
    final providers = user.providerData.map((p) => p.providerId).toList();

    return Scaffold(
      appBar: const ApexAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: ApexColors.primary.withAlpha(40),
              backgroundImage: user.photoURL != null
                  ? NetworkImage(user.photoURL!)
                  : null,
              child: user.photoURL == null
                  ? Icon(Icons.person, size: 36, color: ApexColors.primary)
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              name == null || name.isEmpty ? email : name,
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          if (name != null && name.isNotEmpty)
            Center(
              child: Text(
                email,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/profile/edit'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Profil bearbeiten'),
            ),
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'KONTO',
            children: [
              _InfoRow(
                icon: Icons.fingerprint,
                label: 'User-ID',
                value: user.uid,
              ),
              if (providers.isNotEmpty)
                _InfoRow(
                  icon: Icons.verified_user_outlined,
                  label: 'Anmeldung \u00fcber',
                  value: providers.map(_providerLabel).join(', '),
                ),
              if (user.metadata.creationTime != null)
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Registriert seit',
                  value:
                      '${user.metadata.creationTime!.day}.${user.metadata.creationTime!.month}.${user.metadata.creationTime!.year}',
                ),
            ],
          ),
          const SizedBox(height: 24),
          _Section(title: 'EINSTELLUNGEN', children: [_NotificationsTile()]),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await AuthService.instance.signOut();
              if (context.mounted) context.pop();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Abmelden'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: c.border),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _confirmDelete(context, ref),
            icon: Icon(Icons.delete_forever, color: ApexColors.strike),
            label: Text(
              'Account l\u00f6schen',
              style: TextStyle(color: ApexColors.strike),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'L\u00f6schen entfernt deinen Firebase-Account sofort. Deine '
            'lokalen Daten (Trips, F\u00e4nge, Spots) bleiben auf diesem Ger\u00e4t.',
            style: TextStyle(fontSize: 11, color: c.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static String _providerLabel(String id) {
    switch (id) {
      case 'password':
        return 'E-Mail';
      case 'google.com':
        return 'Google';
      case 'apple.com':
        return 'Apple';
      default:
        return id;
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account l\u00f6schen?'),
        content: const Text(
          'Dein Cloud-Account wird unwiderruflich entfernt. Bist du sicher?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ApexColors.strike),
            child: const Text('L\u00f6schen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final res = await AuthService.instance.deleteAccount();
    if (!context.mounted) return;
    if (res.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account gel\u00f6scht.')));
      context.pop();
    } else if (res.errorCode == 'requires-recent-login') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte melde dich erneut an und versuche es noch einmal.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.errorMessage ?? 'Fehler')));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 12,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w700,
            color: c.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ApexColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: c.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
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

class _NotificationsTile extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables
  _NotificationsTile();

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final master = NotificationPrefs.masterEnabled;
    final profile = NotificationPrefs.profile;
    final subtitle = master ? '${profile.emoji} ${profile.label}' : 'Stumm';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/settings/notifications'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                master
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                size: 18,
                color: master ? ApexColors.primary : c.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Benachrichtigungen',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
