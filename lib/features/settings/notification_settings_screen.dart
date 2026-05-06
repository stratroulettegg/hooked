import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/notifications/notification_categories.dart';
import '../../shared/services/notifications/notification_prefs.dart';
import '../../shared/services/notifications/notification_service.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Einstellungen für lokale Push-Benachrichtigungen.
///
/// Bewusst minimal: ein Master-Toggle + drei Charakter-Presets +
/// Ruhezeiten. Keine Einzel-Switches.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _permissionGranted = false;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await NotificationService.instance.refreshPermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = NotificationService.instance.isReady;
      _checkingPermission = false;
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _checkingPermission = true);
    final ok = await NotificationService.instance.requestPermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = ok;
      _checkingPermission = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final master = NotificationPrefs.masterEnabled;
    final activeProfile = NotificationPrefs.profile;
    final enabled = master && _permissionGranted;

    return Scaffold(
      appBar: const ApexAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _PermissionCard(
            granted: _permissionGranted,
            checking: _checkingPermission,
            onRequest: _requestPermission,
          ),
          const SizedBox(height: 20),
          _MasterCard(
            enabled: master,
            disabled: !_permissionGranted,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              await NotificationPrefs.setMasterEnabled(v);
              if (!mounted) return;
              setState(() {});
            },
          ),
          const SizedBox(height: 20),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled ? 1.0 : 0.45,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CHARAKTER',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 12,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700,
                      color: c.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final p in NotificationProfile.values) ...[
                    _ProfileTile(
                      profile: p,
                      selected: activeProfile == p,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await NotificationPrefs.setProfile(p);
                        await NotificationPrefs.clearCategoryOverrides();
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  _ProfilePreview(profile: activeProfile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'RUHEZEITEN',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 12,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _QuietHoursCard(onChanged: () => setState(() {})),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.granted,
    required this.checking,
    required this.onRequest,
  });

  final bool granted;
  final bool checking;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final color = granted ? ApexColors.primary : ApexColors.scoreMid;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withAlpha(40), color.withAlpha(8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(
            granted
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  granted ? 'Benachrichtigungen erlaubt' : 'Nicht erlaubt',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  granted
                      ? 'Hooked respektiert deine Einstellungen unten.'
                      : 'Ohne Erlaubnis kann Hooked dir nichts schicken.',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
          ),
          if (!granted)
            FilledButton(
              onPressed: checking ? null : onRequest,
              child: checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aktivieren'),
            ),
        ],
      ),
    );
  }
}

class _MasterCard extends StatelessWidget {
  const _MasterCard({
    required this.enabled,
    required this.disabled,
    required this.onChanged,
  });

  final bool enabled;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? ApexColors.primary.withAlpha(140) : c.border,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Erinnerungen',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Aktiv — du bekommst nur, was zum Profil passt.'
                        : 'Stumm — Hooked schickt dir nichts.',
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: disabled ? null : onChanged,
              activeThumbColor: ApexColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final NotificationProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? ApexColors.primary.withAlpha(20) : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? ApexColors.primary.withAlpha(180) : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Text(profile.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.label,
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.description,
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(selected),
                  color: selected ? ApexColors.primary : c.textMuted,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({required this.profile});
  final NotificationProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final included = profile.categories;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Du bekommst:',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          for (final cat in NotificationCategory.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    included.contains(cat)
                        ? Icons.check_circle_rounded
                        : Icons.remove_circle_outline_rounded,
                    size: 16,
                    color: included.contains(cat)
                        ? ApexColors.primary
                        : c.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cat.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: included.contains(cat)
                            ? c.textPrimary
                            : c.textMuted,
                        fontWeight: included.contains(cat)
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
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

class _QuietHoursCard extends StatefulWidget {
  const _QuietHoursCard({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_QuietHoursCard> createState() => _QuietHoursCardState();
}

class _QuietHoursCardState extends State<_QuietHoursCard> {
  Future<void> _pick({required bool isStart}) async {
    final mins = isStart
        ? NotificationPrefs.quietStartMinutes
        : NotificationPrefs.quietEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: mins ~/ 60, minute: mins % 60),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final newMins = picked.hour * 60 + picked.minute;
    final start = isStart ? newMins : NotificationPrefs.quietStartMinutes;
    final end = isStart ? NotificationPrefs.quietEndMinutes : newMins;
    await NotificationPrefs.setQuietHours(start, end);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  String _fmt(int mins) {
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In dieser Zeit werden keine Erinnerungen geschickt.',
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: 'AB',
                  value: _fmt(NotificationPrefs.quietStartMinutes),
                  onTap: () => _pick(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeButton(
                  label: 'BIS',
                  value: _fmt(NotificationPrefs.quietEndMinutes),
                  onTap: () => _pick(isStart: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: c.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
