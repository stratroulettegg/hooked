import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/legal_urls.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/consent_service.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/auth_service.dart';
import '../../shared/services/notifications/notification_prefs.dart';
import '../../shared/services/pro/pro_providers.dart';
import '../../shared/services/pro/revenuecat_bootstrap.dart';
import '../../shared/services/pro/revenuecat_ui_helper.dart';
import '../../shared/services/sync/cloud_sync_service.dart';
import '../../shared/services/sync/sync_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/app_toast.dart';

/// Einstellungen — Konto, Benachrichtigungen, Blockierte, Rechtliches,
/// Logout, Account löschen. Alles, was früher im Profil-Tab unter den
/// User-Daten lag.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Anonyme Auto-Login-Sessions z\u00e4hlen hier *nicht* als „angemeldet" \u2014
    // sie haben keine E-Mail, keinen Provider, kein Pro-Abo und keinen
    // sinnvollen „Abmelden"/„Account l\u00f6schen"-Flow. Sie sehen den
    // Login-CTA und die ger\u00e4tebezogenen Sektionen (Notifications,
    // Privacy, Rechtliches).
    final user = ref.watch(signedInUserProvider);
    final c = ApexColors.of(context);

    if (user == null) {
      return Scaffold(
        appBar: const ApexAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 56, color: c.textMuted),
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/auth'),
                  icon: const Icon(Icons.login),
                  label: const Text('Anmelden'),
                ),
                const SizedBox(height: 24),
                _NotificationsTile(),
                const SizedBox(height: 24),
                const _PrivacySection(),
                const SizedBox(height: 24),
                const _LegalSection(),
              ],
            ),
          ),
        ),
      );
    }

    final email = user.email ?? '—';
    final providers = user.providerData.map((p) => p.providerId).toList();

    return Scaffold(
      appBar: const ApexAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          _Section(
            title: 'KONTO',
            children: [
              _InfoRow(
                icon: Icons.alternate_email,
                label: 'E-Mail',
                value: email,
              ),
              _InfoRow(
                icon: Icons.fingerprint,
                label: 'User-ID',
                value: user.uid,
              ),
              if (providers.isNotEmpty)
                _InfoRow(
                  icon: Icons.verified_user_outlined,
                  label: 'Anmeldung über',
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
          _Section(
            title: 'EINSTELLUNGEN',
            children: [
              _NotificationsTile(),
              const Divider(height: 1),
              const _BlockedUsersTile(),
              const Divider(height: 1),
              const _CommunityGuidelinesTile(),
            ],
          ),
          const SizedBox(height: 24),
          const _CloudSyncSection(),
          const SizedBox(height: 24),
          const _PrivacySection(),
          const SizedBox(height: 24),
          const _LegalSection(),
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
              'Account löschen',
              style: TextStyle(color: ApexColors.strike),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Löschen entfernt deinen Firebase-Account sofort. Deine '
            'lokalen Daten (Trips, Fänge, Spots) bleiben auf diesem Gerät.',
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
        title: const Text('Account löschen?'),
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
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // Blockierender Fortschritts-Dialog — die Löschung läuft via Cloud
    // Function und kann mehrere Sekunden dauern, je nach Datenmenge.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final c = ApexColors.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface,
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(ApexColors.strike),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Account wird gelöscht …',
                    style: TextStyle(color: c.textPrimary, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final res = await AuthService.instance.deleteAccount();
    if (!context.mounted) return;
    // Fortschritts-Dialog wieder zu.
    Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;
    if (res.isSuccess) {
      AppToast.success(context, 'Account gelöscht.');
      context.go('/catches');
    } else if (res.errorCode == 'requires-recent-login') {
      AppToast.error(
        context,
        'Bitte melde dich erneut an und versuche es noch einmal.',
      );
    } else {
      final msg = res.errorMessage?.trim().isNotEmpty == true
          ? res.errorMessage!
          : 'Account-Löschung fehlgeschlagen.';
      AppToast.error(context, msg, code: res.errorCode);
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

class _BlockedUsersTile extends StatelessWidget {
  const _BlockedUsersTile();

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/settings/blocked'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.block, size: 18, color: ApexColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Blockierte Nutzer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Block-Liste verwalten',
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

class _LegalSection extends StatelessWidget {
  const _LegalSection();

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      AppToast.error(context, 'Link konnte nicht geöffnet werden.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    Widget tile({
      required IconData icon,
      required String label,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                Icon(Icons.open_in_new, size: 16, color: c.textMuted),
              ],
            ),
          ),
        ),
      );
    }

    return _Section(
      title: 'RECHTLICHES',
      children: [
        tile(
          icon: Icons.privacy_tip_outlined,
          label: 'Datenschutz',
          subtitle: 'Wie wir mit deinen Daten umgehen',
          onTap: () => _open(context, LegalUrls.privacy),
        ),
        const Divider(height: 1),
        tile(
          icon: Icons.gavel_outlined,
          label: 'Impressum',
          subtitle: 'Anbieterkennzeichnung & Kontakt',
          onTap: () => _open(context, LegalUrls.imprint),
        ),
      ],
    );
  }
}

/// Privacy-Sektion: Diagnose-Opt-in (Crashlytics) plus Möglichkeit, die
/// erteilte Tech-Einwilligung zurückzunehmen. Reset triggert beim
/// nächsten App-Start erneut den Consent-Screen.
class _PrivacySection extends StatefulWidget {
  const _PrivacySection();

  @override
  State<_PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends State<_PrivacySection> {
  late bool _diag;

  @override
  void initState() {
    super.initState();
    _diag = ConsentService.diagnosticsGranted;
  }

  Future<void> _toggleDiag(bool v) async {
    setState(() => _diag = v);
    await ConsentService.setDiagnostics(v);
    // Crashlytics live umschalten — in Debug bleibt es ohnehin aus.
    try {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(v && !kDebugMode);
    } catch (_) {
      // Native Plugin nicht registriert (Tests / fehlende Pods) — egal.
    }
    // Analytics-Collection an denselben Schalter koppeln.
    await AnalyticsService.applyConsent(v);
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Technische Daten zurücksetzen?'),
        content: const Text(
          'Beim nächsten App-Start wirst du erneut nach deiner '
          'Einwilligung gefragt. Deine lokalen Fänge, Spots und Trips '
          'bleiben erhalten. Eine bestehende Cloud-Synchronisation '
          'wird pausiert, bis du erneut zustimmst.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ConsentService.reset();
    if (!mounted) return;
    AppToast.success(
      context,
      'Einwilligungen zurückgesetzt. App neu starten, um den Hinweis erneut zu sehen.',
    );
    setState(() => _diag = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return _Section(
      title: 'PRIVATSPHÄRE',
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          value: _diag,
          onChanged: _toggleDiag,
          activeThumbColor: ApexColors.primary,
          title: Text(
            'Hilf, Hooked besser zu machen',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Anonyme Absturzberichte + Nutzungs-Statistiken. Keine '
              'Fang-Daten, keine Standorte, keine Inhalte.',
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
          ),
        ),
        const Divider(height: 1),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _confirmReset,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.restart_alt_rounded,
                    size: 18,
                    color: ApexColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Technische Daten zurücksetzen',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hinweis-Dialog beim nächsten Start erneut anzeigen',
                          style: TextStyle(fontSize: 11, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: c.textMuted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommunityGuidelinesTile extends StatelessWidget {
  const _CommunityGuidelinesTile();

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/settings/community-guidelines'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: ApexColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community-Regeln',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Was bei Hooked erlaubt ist – und was nicht',
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

/// Settings-Section für Cloud-Sync (Pro-Feature).
///
/// Solange RevenueCat noch nicht angeschlossen ist, fungiert hier der
/// `isProProvider` aus `pro_providers.dart` als Mock-Switch — so können
/// Pro-Features (inkl. Cloud-Sync) lokal verifiziert werden.
class _CloudSyncSection extends ConsumerWidget {
  const _CloudSyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final user = ref.watch(currentUserProvider);
    final isPro = ref.watch(isProProvider);
    final enabled = ref.watch(cloudSyncEnabledProvider);
    final statusAsync = ref.watch(syncStatusProvider);
    final status = statusAsync.valueOrNull ?? SyncStatus.idle;

    String statusLabel;
    Color statusColor;
    switch (status.state) {
      case SyncState.syncing:
        statusLabel = 'Synchronisiere…';
        statusColor = ApexColors.primary;
        break;
      case SyncState.error:
        statusLabel = 'Fehler beim Sync';
        statusColor = Colors.orange;
        break;
      case SyncState.offline:
        statusLabel = 'Offline';
        statusColor = c.textMuted;
        break;
      case SyncState.idle:
        statusLabel = status.lastSuccessAt != null
            ? 'Zuletzt: ${_formatTime(status.lastSuccessAt!)}'
            : enabled
            ? 'Bereit'
            : 'Inaktiv';
        statusColor = c.textSecondary;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CLOUD-SYNC',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 12,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w700,
                color: c.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ApexColors.primary.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: ApexColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            children: [
              if (!isPro)
                ListTile(
                  leading: Icon(Icons.lock_outline, color: c.textMuted),
                  title: Text(
                    'Cloud-Sync freischalten',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Cloud-Backup, Trip-Sharing & mehr mit Hooked Pro.',
                    style: TextStyle(fontSize: 11, color: c.textMuted),
                  ),
                  trailing: Icon(Icons.chevron_right, color: c.textMuted),
                  onTap: () => context.push('/paywall'),
                )
              else ...[
                if (RevenueCatBootstrap.isAvailable) ...[
                  ListTile(
                    leading: Icon(
                      Icons.subscriptions_outlined,
                      color: ApexColors.primary,
                    ),
                    title: Text(
                      'Abo verwalten',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Plan, Verlängerung, Kündigung & FAQ',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                    trailing: Icon(Icons.chevron_right, color: c.textMuted),
                    onTap: () => RevenueCatUiHelper.presentCustomerCenter(),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: Icon(
                    enabled
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: enabled ? ApexColors.primary : c.textMuted,
                  ),
                  title: Text(
                    'Status',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    user == null ? 'Anmeldung erforderlich' : statusLabel,
                    style: TextStyle(fontSize: 12, color: statusColor),
                  ),
                  trailing: status.state == SyncState.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                if (status.state == SyncState.error &&
                    status.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      status.errorMessage!,
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              enabled && status.state != SyncState.syncing
                              ? () => ref
                                    .read(cloudSyncServiceProvider)
                                    .syncNow()
                              : null,
                          icon: const Icon(Icons.cloud_sync_outlined),
                          label: const Text('Jetzt synchronisieren'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ApexColors.primary,
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              enabled && status.state != SyncState.syncing
                              ? () => _confirmForceResync(context, ref)
                              : null,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Vollständig neu hochladen'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                            side: BorderSide(color: c.border),
                            foregroundColor: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              enabled && status.state != SyncState.syncing
                              ? () => _confirmForceRepull(context, ref)
                              : null,
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Vollständig neu laden'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                            side: BorderSide(color: c.border),
                            foregroundColor: c.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          enabled
              ? 'Deine Catches, Spots, Gewässer, Trips und Wassertage werden '
                    'mit deinem Konto synchronisiert.'
              : isPro
              ? 'Melde dich an, um Cloud-Sync zu aktivieren.'
              : 'Aktiviere Pro, um deine Daten geräteübergreifend zu nutzen.',
          style: TextStyle(fontSize: 11, color: c.textMuted),
        ),
      ],
    );
  }

  Future<void> _confirmForceResync(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vollständig neu hochladen?'),
        content: const Text(
          'Alle lokalen Catches, Spots, Gewässer, Trips und Wassertage '
          'werden in die Cloud hochgeladen, auch wenn sie dort bereits '
          'existieren. Sinnvoll, wenn der Cloud-Stand unvollständig ist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hochladen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(cloudSyncServiceProvider).forceFullResync();
  }

  Future<void> _confirmForceRepull(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud-Daten neu laden?'),
        content: const Text(
          'Alle Daten werden erneut aus der Cloud heruntergeladen. '
          'Sinnvoll auf einem zweiten Gerät, das die Daten noch nicht '
          'sieht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Herunterladen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(cloudSyncServiceProvider).forceFullRepull();
  }

  static String _formatTime(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inSeconds < 60) return 'gerade eben';
    if (d.inMinutes < 60) return 'vor ${d.inMinutes} min';
    if (d.inHours < 24) return 'vor ${d.inHours} h';
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}. '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
