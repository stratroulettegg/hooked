import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/auth_service.dart';
import '../../shared/services/firebase/firebase_bootstrap.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Login-Screen mit Apple und Google.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _loading = false;
  String? _lastError;

  Future<void> _run(Future<AuthResult> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _lastError = null;
    });
    try {
      final res = await action();
      if (!mounted) return;
      if (res.isSuccess) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      } else if (res.errorCode != 'cancelled') {
        setState(() => _lastError = res.errorMessage ?? res.errorCode);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final firebaseReady = ref.watch(firebaseAvailableProvider);

    return Scaffold(
      appBar: const ApexAppBar(),
      body: !firebaseReady
          ? _NotConfigured(error: FirebaseBootstrap.initError)
          : AbsorbPointer(
              absorbing: _loading,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                children: [
                  Icon(Icons.cloud_queue, size: 56, color: ApexColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Cloud-Konto',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Nur noetig, wenn du Trips mit anderen teilen willst. '
                    'Alles andere funktioniert weiter offline.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  if (AuthService.instance.isAppleSupported) ...[
                    _ProviderButton(
                      icon: Icons.apple,
                      label: 'Mit Apple anmelden',
                      onPressed: () =>
                          _run(() => AuthService.instance.signInWithApple()),
                      dark: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _ProviderButton(
                    icon: Icons.g_mobiledata,
                    label: 'Mit Google anmelden',
                    onPressed: () =>
                        _run(() => AuthService.instance.signInWithGoogle()),
                  ),
                  if (_lastError != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _lastError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ApexColors.strike,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: CircularProgressIndicator(
                        color: ApexColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Wir speichern nur deinen Anbieter-Profilnamen und (optional) '
                    'dein Profilbild in einem EU-Firebase-Projekt. '
                    'Du kannst deinen Account jederzeit im Profil loeschen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: c.textMuted),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.dark = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: dark ? Colors.black : c.surface,
          foregroundColor: dark ? Colors.white : c.textPrimary,
          side: BorderSide(color: c.border),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: c.textMuted),
            const SizedBox(height: 12),
            Text(
              'Cloud nicht eingerichtet',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'F\u00fchre einmalig `flutterfire configure` im Projekt aus, '
              'um die Firebase-Konfiguration zu erzeugen. Die App l\u00e4uft '
              'ansonsten weiter offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
