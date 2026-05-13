import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../services/sync/cloud_sync_service.dart';
import '../services/sync/sync_providers.dart';

/// Kompakter Indikator für den Cloud-Sync-Status (Wolken-Icon).
///
/// Zeigt sich nur, wenn Cloud-Sync aktiv ist (Pro + eingeloggt). Während
/// eines Syncs läuft ein kleines Spinner-Overlay; im Fehlerfall wird das
/// Icon orange und ein Tap startet einen erneuten Sync.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(cloudSyncEnabledProvider);
    if (!enabled) return const SizedBox.shrink();
    final statusAsync = ref.watch(syncStatusProvider);
    final status = statusAsync.valueOrNull ?? SyncStatus.idle;
    final c = ApexColors.of(context);

    final IconData icon;
    final Color color;
    switch (status.state) {
      case SyncState.syncing:
        icon = Icons.cloud_sync_outlined;
        color = ApexColors.primary;
        break;
      case SyncState.error:
        icon = Icons.cloud_off_outlined;
        color = Colors.orange;
        break;
      case SyncState.offline:
        icon = Icons.cloud_off_outlined;
        color = c.textMuted;
        break;
      case SyncState.idle:
        icon = Icons.cloud_done_outlined;
        color = c.textSecondary;
        break;
    }

    final tooltip = switch (status.state) {
      SyncState.syncing => 'Synchronisiere…',
      SyncState.error =>
        'Sync-Fehler – tippen für erneuten Versuch'
            '${status.errorMessage != null ? '\n${status.errorMessage}' : ''}',
      SyncState.offline => 'Offline',
      SyncState.idle => status.lastSuccessAt == null
          ? 'Cloud-Sync bereit'
          : 'Zuletzt synchronisiert: ${_formatTime(status.lastSuccessAt!)}',
    };

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 20,
        onTap: () => ref.read(cloudSyncServiceProvider).syncNow(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: compact ? 20 : 24,
            height: compact ? 20 : 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: compact ? 18 : 22, color: color),
                if (status.state == SyncState.syncing)
                  SizedBox(
                    width: compact ? 20 : 24,
                    height: compact ? 20 : 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inSeconds < 60) return 'gerade eben';
    if (d.inMinutes < 60) return 'vor ${d.inMinutes} min';
    if (d.inHours < 24) return 'vor ${d.inHours} h';
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}. ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
