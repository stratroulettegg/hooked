import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../profile/user_profile_screen.dart';

/// Profil-Tab. Zeigt für eingeloggte User die identische Public-Profil-
/// Ansicht wie sie auch andere sehen (`UserProfileScreen`). Einstellungen
/// liegen unter `/settings`. Nicht angemeldet → Login-CTA.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Anonyme Auto-Login-Sessions sehen den Login-CTA, nicht das Profil.
    final user = ref.watch(signedInUserProvider);
    if (user != null) {
      return UserProfileScreen(uid: user.uid);
    }

    final c = ApexColors.of(context);
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
                'Melde dich an, um dein Profil und deine Beiträge zu sehen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.push('/auth'),
                icon: const Icon(Icons.login),
                label: const Text('Anmelden'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Einstellungen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
