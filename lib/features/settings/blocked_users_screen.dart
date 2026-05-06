import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/firebase/firebase_bootstrap.dart';

/// Zeigt die Liste blockierter Nutzer:innen mit Möglichkeit zum Aufheben.
/// Namen/Avatare werden best-effort aus dem Feed abgeleitet (letzter
/// bekannter Eintrag dieses Users). Wenn kein Eintrag mehr existiert,
/// wird die UID angezeigt.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final blocked = ref.watch(blockedUidsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blockiert')),
      body: blocked.when(
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
              'Konnte Block-Liste nicht laden.',
              style: TextStyle(color: c.textMuted),
            ),
          ),
        ),
        data: (uids) {
          if (uids.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 56, color: c.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'Keine blockierten Nutzer',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Wenn du jemanden blockierst, erscheint er hier und du kannst den Block jederzeit wieder aufheben.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }
          // Best-effort: Namen aus dem Feed-Stream nachschlagen.
          return _BlockedList(uids: uids.toList());
        },
      ),
    );
  }
}

class _BlockedList extends ConsumerStatefulWidget {
  const _BlockedList({required this.uids});
  final List<String> uids;

  @override
  ConsumerState<_BlockedList> createState() => _BlockedListState();
}

class _BlockedListState extends ConsumerState<_BlockedList> {
  /// Cache: uid -> (name, photoUrl). Wird einmalig pro UID aus dem Feed
  /// gelesen. Wenn nichts gefunden wird, bleibt der Eintrag null.
  final Map<String, _UserInfo?> _cache = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadInfos();
  }

  @override
  void didUpdateWidget(covariant _BlockedList old) {
    super.didUpdateWidget(old);
    final missing = widget.uids.where((u) => !_cache.containsKey(u));
    if (missing.isNotEmpty) _loadInfos();
  }

  Future<void> _loadInfos() async {
    if (_loading || !FirebaseBootstrap.isAvailable) return;
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );
      // Firestore unterstützt whereIn mit max 10 Elementen.
      final pending = widget.uids
          .where((u) => !_cache.containsKey(u))
          .toList();
      for (var i = 0; i < pending.length; i += 10) {
        final chunk = pending.sublist(
          i,
          i + 10 > pending.length ? pending.length : i + 10,
        );
        final snap = await db
            .collection('feed')
            .where('userId', whereIn: chunk)
            .limit(20)
            .get();
        final found = <String, _UserInfo>{};
        for (final d in snap.docs) {
          final m = d.data();
          final uid = m['userId'] as String?;
          if (uid == null) continue;
          if (found.containsKey(uid)) continue;
          found[uid] = _UserInfo(
            name: m['userName'] as String?,
            photoUrl: m['userPhotoUrl'] as String?,
          );
        }
        for (final u in chunk) {
          _cache[u] = found[u];
        }
      }
    } catch (_) {
      // best-effort
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: widget.uids.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final uid = widget.uids[i];
        final info = _cache[uid];
        final name = info?.name?.isNotEmpty == true
            ? info!.name!
            : 'Unbekannt';
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: c.border,
              backgroundImage: (info?.photoUrl?.isNotEmpty ?? false)
                  ? NetworkImage(info!.photoUrl!)
                  : null,
              child: (info?.photoUrl?.isEmpty ?? true)
                  ? Icon(Icons.person, color: c.textMuted)
                  : null,
            ),
            title: Text(
              name,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'UID: ${uid.substring(0, uid.length > 8 ? 8 : uid.length)}…',
              style: TextStyle(color: c.textMuted, fontSize: 11),
            ),
            trailing: TextButton(
              onPressed: () async {
                await ref
                    .read(moderationServiceProvider)
                    .unblockUser(uid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$name entsperrt.')),
                  );
                }
              },
              child: const Text('Entsperren'),
            ),
          ),
        );
      },
    );
  }
}

class _UserInfo {
  const _UserInfo({this.name, this.photoUrl});
  final String? name;
  final String? photoUrl;
}
