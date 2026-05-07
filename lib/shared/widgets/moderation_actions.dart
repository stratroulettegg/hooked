import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../services/app_providers.dart';
import '../services/firebase/auth_providers.dart';

/// Vordefinierte Meldegründe – decken die häufigsten Moderationsfälle ab.
const List<String> kReportReasons = [
  'Beleidigung / Hass',
  'Spam / Werbung',
  'Anstößiger Inhalt',
  'Falsche Informationen',
  'Verstoß gegen Tier-/Naturschutz',
  'Sonstiges',
];

/// Bestimmt das Meldeziel.
enum ModerationTargetKind { post, comment }

/// Zeigt das untere Sheet zum Melden eines Posts oder Kommentars.
/// Gibt `true` zurück, wenn der Report erfolgreich abgesetzt wurde.
Future<bool> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required ModerationTargetKind kind,
  required String postId,
  String? commentId,
  required String targetUid,
}) async {
  final me = ref.read(currentUserProvider);
  if (me == null) {
    AppToast.error(context, 'Bitte zuerst anmelden, um zu melden.');
    return false;
  }
  if (me.uid == targetUid) {
    AppToast.error(context, 'Du kannst dich nicht selbst melden.');
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      kind: kind,
      postId: postId,
      commentId: commentId,
      targetUid: targetUid,
    ),
  );
  return result ?? false;
}

/// Bestätigungsdialog zum Blockieren eines Nutzers.
/// Bei Bestätigung wird der Block sofort persistiert.
Future<bool> confirmBlockUser(
  BuildContext context,
  WidgetRef ref, {
  required String targetUid,
  String? targetName,
}) async {
  final c = ApexColors.of(context);
  final me = ref.read(currentUserProvider);
  if (me == null || me.uid == targetUid) return false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text('Nutzer blockieren?', style: TextStyle(color: c.textPrimary)),
      content: Text(
        targetName != null && targetName.isNotEmpty
            ? 'Du siehst keine Beiträge oder Kommentare von $targetName mehr. '
                  'Du kannst den Block in den Einstellungen wieder aufheben.'
            : 'Du siehst keine Beiträge oder Kommentare von diesem Nutzer mehr. '
                  'Du kannst den Block in den Einstellungen wieder aufheben.',
        style: TextStyle(color: c.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ApexColors.scoreLow),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Blockieren'),
        ),
      ],
    ),
  );

  if (ok != true) return false;
  try {
    await ref.read(moderationServiceProvider).blockUser(targetUid);
    if (context.mounted) {
      AppToast.success(
        context,
        targetName?.isNotEmpty == true
            ? '$targetName blockiert.'
            : 'Nutzer blockiert.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      AppToast.error(context, 'Blockieren fehlgeschlagen: $e');
    }
    return false;
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.kind,
    required this.postId,
    required this.commentId,
    required this.targetUid,
  });

  final ModerationTargetKind kind;
  final String postId;
  final String? commentId;
  final String targetUid;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  final _detailCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null || _sending) return;
    setState(() => _sending = true);
    final detail = _detailCtrl.text.trim();
    final fullReason = detail.isEmpty ? _reason! : '${_reason!} — $detail';
    try {
      final svc = ref.read(moderationServiceProvider);
      if (widget.kind == ModerationTargetKind.post) {
        await svc.reportPost(
          postId: widget.postId,
          targetUid: widget.targetUid,
          reason: fullReason,
        );
      } else {
        await svc.reportComment(
          postId: widget.postId,
          commentId: widget.commentId!,
          targetUid: widget.targetUid,
          reason: fullReason,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        'Danke. Wir prüfen die Meldung und kümmern uns darum.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppToast.error(context, 'Melden fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final mediaInsets = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: c.background.withAlpha(235),
                border: Border(top: BorderSide(color: c.border.withAlpha(120))),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: mediaInsets),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 18,
                            color: c.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.kind == ModerationTargetKind.post
                                ? 'Beitrag melden'
                                : 'Kommentar melden',
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: c.border.withAlpha(80)),
                    Flexible(
                      child: ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        children: [
                          Text(
                            'Wähle einen Grund:',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final r in kReportReasons)
                            RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: ApexColors.primary,
                              value: r,
                              groupValue: _reason,
                              onChanged: (v) => setState(() => _reason = v),
                              title: Text(
                                r,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _detailCtrl,
                            maxLines: 3,
                            maxLength: 400,
                            style: TextStyle(color: c.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Optional: Was genau ist das Problem?',
                              hintStyle: TextStyle(color: c.textMuted),
                              filled: true,
                              fillColor: c.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: ApexColors.primary,
                                  width: 1.4,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.border),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Wir prüfen jede Meldung. Wiederholte Verstöße können zur Sperrung des Kontos führen.',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: c.border.withAlpha(120)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _sending
                                  ? null
                                  : () => Navigator.of(context).pop(false),
                              child: const Text('Abbrechen'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (_reason == null || _sending)
                                  ? null
                                  : _submit,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.flag, size: 16),
                              label: const Text('Melden'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
