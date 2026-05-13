import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/waterbody.dart';
import '../../shared/services/app_providers.dart';
import 'add_edit_waterbody_screen.dart';

/// Bottom-Sheet zum Auswählen eines Gewässers für Spot/Catch/Trip.
/// Liefert die gewählte Waterbody zurück oder null („Kein Gewässer").
class WaterbodyPickerSheet extends ConsumerStatefulWidget {
  const WaterbodyPickerSheet({super.key, this.initialId});
  final String? initialId;

  static Future<Waterbody?> show(
    BuildContext context, {
    String? initialId,
  }) async {
    return showModalBottomSheet<Waterbody?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WaterbodyPickerSheet(initialId: initialId),
    );
  }

  @override
  ConsumerState<WaterbodyPickerSheet> createState() =>
      _WaterbodyPickerSheetState();
}

class _WaterbodyPickerSheetState extends ConsumerState<WaterbodyPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final waterbodies = ref.watch(waterbodyProvider).valueOrNull ?? const [];
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? waterbodies
        : waterbodies
              .where(
                (w) =>
                    w.name.toLowerCase().contains(q) ||
                    (w.region?.toLowerCase().contains(q) ?? false),
              )
              .toList();

    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Gewässer wählen',
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Neu'),
                        style: TextButton.styleFrom(
                          foregroundColor: ApexColors.primary,
                        ),
                        onPressed: () async {
                          final created = await Navigator.of(context).push(
                            MaterialPageRoute<Waterbody?>(
                              builder: (_) => const AddEditWaterbodyScreen(),
                            ),
                          );
                          if (created != null && context.mounted) {
                            Navigator.of(context).pop(created);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search, color: c.textMuted),
                      hintText: 'Suchen…',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    children: [
                      _NoneTile(
                        selected: widget.initialId == null,
                        onTap: () => Navigator.of(context).pop(null),
                      ),
                      if (filtered.isEmpty && q.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Keine Treffer für „$_query".',
                            style: TextStyle(color: c.textMuted, fontSize: 13),
                          ),
                        ),
                      ...filtered.map(
                        (w) => _WbTile(
                          waterbody: w,
                          selected: widget.initialId == w.id,
                          onTap: () => Navigator.of(context).pop(w),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NoneTile extends StatelessWidget {
  const _NoneTile({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return ListTile(
      leading: Icon(Icons.do_not_disturb_alt, color: c.textMuted),
      title: Text(
        'Kein Gewässer',
        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Spot bleibt ohne Gewässer-Verknüpfung',
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: ApexColors.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _WbTile extends StatelessWidget {
  const _WbTile({
    required this.waterbody,
    required this.selected,
    required this.onTap,
  });
  final Waterbody waterbody;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (waterbody.type) {
      case WaterbodyType.see:
      case WaterbodyType.teich:
        return Icons.water_rounded;
      case WaterbodyType.fluss:
      case WaterbodyType.kanal:
        return Icons.waves_rounded;
      case WaterbodyType.hafen:
        return Icons.directions_boat_rounded;
      case WaterbodyType.meer:
        return Icons.sailing_rounded;
      case WaterbodyType.sonstiges:
        return Icons.water_drop_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: ApexColors.primary.withAlpha(40),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_icon, color: ApexColors.primary, size: 20),
      ),
      title: Text(
        waterbody.name,
        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        waterbody.subtitle,
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: ApexColors.primary)
          : null,
      onTap: onTap,
    );
  }
}
