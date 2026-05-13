import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/pro/pro_providers.dart';
import 'paywall_screen.dart';

/// Pro-Features, hinter denen ein Paywall steht. Enum-Werte werden im
/// Paywall-Header verwendet, um den Kontext klar zu machen ("Upgrade
/// für Cloud-Backup"), und für Analytics-Events.
enum ProFeature {
  cloudBackup(
    title: 'Foto-Cloud-Backup',
    description:
        'Sichere deine Catch-Fotos verschlüsselt auf EU-Servern. '
        'Geräte-Wechsel und Wiederherstellung mit einem Tap.',
    icon: Icons.cloud_done_rounded,
    analyticsKey: 'cloud_backup',
  ),
  unlimitedTrips(
    title: 'Unbegrenzt Trips',
    description:
        'Free erlaubt 3 aktive Trips. Mit Pro plane so viele '
        'Touren, wie du willst — parallel und ohne Limit.',
    icon: Icons.route_rounded,
    analyticsKey: 'unlimited_trips',
  ),
  tripSharing(
    title: 'Trip-Sharing',
    description:
        'Lade Buddies zu deinen Trips ein. Gemeinsam planen, '
        'gemeinsam loggen, gemeinsam Fänge feiern.',
    icon: Icons.group_add_rounded,
    analyticsKey: 'trip_sharing',
  ),
  predatorForecast(
    title: '7-Tage-Forecast',
    description:
        'Predator-Score für die nächsten 7 Tage — inklusive Mondphase, '
        'Detail-Wetter und Beißzeit-Prognose.',
    icon: Icons.calendar_view_week_rounded,
    analyticsKey: 'predator_forecast',
  ),
  adFree(
    title: 'Werbefrei',
    description:
        'Keine Anzeigen, keine Ablenkung — die App, wie du sie willst.',
    icon: Icons.block_rounded,
    analyticsKey: 'ad_free',
  );

  const ProFeature({
    required this.title,
    required this.description,
    required this.icon,
    required this.analyticsKey,
  });

  final String title;
  final String description;
  final IconData icon;
  final String analyticsKey;
}

/// Öffnet den Paywall-Screen als Modal-Sheet. Vibriert dezent als
/// haptisches Feedback. Liefert `true` zurück, wenn der User Pro
/// freigeschaltet hat (sodass Caller den Flow direkt fortsetzen kann).
Future<bool> showPaywall(BuildContext context, {required ProFeature feature}) {
  HapticFeedback.selectionClick();
  return Navigator.of(context, rootNavigator: true)
      .push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PaywallScreen(feature: feature),
        ),
      )
      .then((v) => v ?? false);
}

/// Gate-Helper: prüft `isProProvider` und ruft entweder [onAllowed] oder
/// [showPaywall] auf. Idiomatischer Aufruf an Call-Sites:
///
/// ```dart
/// onPressed: () => proGate(
///   context: context,
///   ref: ref,
///   feature: ProFeature.cloudBackup,
///   onAllowed: () => uploadPhoto(),
/// ),
/// ```
Future<void> proGate({
  required BuildContext context,
  required WidgetRef ref,
  required ProFeature feature,
  required VoidCallback onAllowed,
}) async {
  final isPro = ref.read(isProProvider);
  if (isPro) {
    onAllowed();
    return;
  }
  final unlocked = await showPaywall(context, feature: feature);
  if (unlocked && context.mounted) onAllowed();
}
