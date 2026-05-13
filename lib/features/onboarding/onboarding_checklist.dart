import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/user_profile_providers.dart';
import '../../shared/widgets/app_toast.dart';

/// Schritte der Erste-Schritte-Checkliste. Reihenfolge ist die UI-Reihenfolge.
enum OnboardingStep {
  firstSpot,
  firstCatch,
  signIn,
  profilePhoto,
  steckbrief,
  firstShare,
}

/// Die für anonyme User sichtbaren Schritte: lokale Features + Login als
/// Brücke zu den Community-Features.
const List<OnboardingStep> _anonSteps = [
  OnboardingStep.firstSpot,
  OnboardingStep.firstCatch,
  OnboardingStep.signIn,
];

/// Die für eingeloggte User sichtbaren Schritte.
const List<OnboardingStep> _authSteps = [
  OnboardingStep.profilePhoto,
  OnboardingStep.steckbrief,
  OnboardingStep.firstSpot,
  OnboardingStep.firstCatch,
  OnboardingStep.firstShare,
];

extension OnboardingStepX on OnboardingStep {
  String get title {
    switch (this) {
      case OnboardingStep.profilePhoto:
        return 'Profilbild hinzufügen';
      case OnboardingStep.steckbrief:
        return 'Steckbrief schreiben';
      case OnboardingStep.firstSpot:
        return 'Ersten Spot anlegen';
      case OnboardingStep.firstCatch:
        return 'Ersten Fang dokumentieren';
      case OnboardingStep.firstShare:
        return 'Beitrag im Feed teilen';
      case OnboardingStep.signIn:
        return 'Account anlegen';
    }
  }

  String get cta {
    switch (this) {
      case OnboardingStep.profilePhoto:
      case OnboardingStep.steckbrief:
        return 'Profil bearbeiten';
      case OnboardingStep.firstSpot:
        return 'Spot anlegen';
      case OnboardingStep.firstCatch:
        return 'Fang anlegen';
      case OnboardingStep.firstShare:
        return 'Fang teilen';
      case OnboardingStep.signIn:
        return 'Anmelden';
    }
  }

  IconData get icon {
    switch (this) {
      case OnboardingStep.profilePhoto:
        return Icons.add_a_photo_outlined;
      case OnboardingStep.steckbrief:
        return Icons.edit_note_rounded;
      case OnboardingStep.firstSpot:
        return Icons.location_on_outlined;
      case OnboardingStep.firstCatch:
        return Icons.phishing_rounded;
      case OnboardingStep.firstShare:
        return Icons.public_outlined;
      case OnboardingStep.signIn:
        return Icons.login_rounded;
    }
  }

  String get route {
    switch (this) {
      case OnboardingStep.profilePhoto:
      case OnboardingStep.steckbrief:
        return '/profile/edit';
      case OnboardingStep.firstSpot:
        return '/spots/add';
      case OnboardingStep.firstCatch:
        return '/catches/add';
      case OnboardingStep.firstShare:
        return '/catches';
      case OnboardingStep.signIn:
        return '/auth';
    }
  }
}

/// Persistiert den „dismissed"- und „celebrated"-Status der Checkliste.
/// Pro UID getrennt; anonyme User nutzen den Bucket `_anon`.
class OnboardingChecklistPrefs {
  OnboardingChecklistPrefs._();

  static const _anonBucket = '_anon';
  static String _bucket(String? uid) =>
      (uid == null || uid.isEmpty) ? _anonBucket : uid;

  static String _dismissedKey(String? uid) =>
      'onboarding_checklist_dismissed_${_bucket(uid)}';
  static String _celebratedKey(String? uid) =>
      'onboarding_checklist_celebrated_${_bucket(uid)}';

  static Future<bool> isDismissed(String? uid) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_dismissedKey(uid)) ?? false;
  }

  static Future<void> dismiss(String? uid) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_dismissedKey(uid), true);
  }

  static Future<bool> isCelebrated(String? uid) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_celebratedKey(uid)) ?? false;
  }

  static Future<void> markCelebrated(String? uid) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_celebratedKey(uid), true);
  }
}

/// Reaktive Karte mit den 5 Erste-Schritte-Tasks. Holt sich Profile,
/// Catches, Spots und FeedPosts aus den globalen Providern und rendert
/// die Liste nur, wenn:
///   - User eingeloggt
///   - mindestens ein Schritt offen ist
///   - User die Karte nicht dismissed hat
///   - Profil-Setup grundsätzlich abgeschlossen ist (handle vorhanden)
class OnboardingChecklistCard extends ConsumerStatefulWidget {
  const OnboardingChecklistCard({super.key});

  @override
  ConsumerState<OnboardingChecklistCard> createState() =>
      _OnboardingChecklistCardState();
}

class _OnboardingChecklistCardState
    extends ConsumerState<OnboardingChecklistCard> {
  bool _initialized = false;
  bool _dismissedLocal = false;
  bool _expanded = true;
  String _watchedBucket = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = ref.read(currentUserProvider)?.uid;
    final bucket = (uid == null || uid.isEmpty) ? '_anon' : uid;
    if (bucket != _watchedBucket) {
      _watchedBucket = bucket;
      _initialized = false;
      _loadPrefs(uid);
    }
  }

  Future<void> _loadPrefs(String? uid) async {
    final dismissed = await OnboardingChecklistPrefs.isDismissed(uid);
    if (!mounted) return;
    setState(() {
      _dismissedLocal = dismissed;
      _initialized = true;
    });
  }

  Set<OnboardingStep> _completedSteps(bool isLoggedIn) {
    final done = <OnboardingStep>{};
    // Lokale Schritte — auch ohne Login verfügbar.
    final spots = ref.watch(spotProvider).valueOrNull ?? const [];
    if (spots.isNotEmpty) done.add(OnboardingStep.firstSpot);
    final catches = ref.watch(catchProvider).valueOrNull ?? const [];
    if (catches.isNotEmpty) done.add(OnboardingStep.firstCatch);
    if (isLoggedIn) {
      done.add(OnboardingStep.signIn);
      final profile = ref.watch(myProfileProvider).valueOrNull;
      if (profile?.photoUrl?.isNotEmpty == true) {
        done.add(OnboardingStep.profilePhoto);
      }
      if (profile?.steckbrief?.trim().isNotEmpty == true) {
        done.add(OnboardingStep.steckbrief);
      }
      final myPosts = ref.watch(myFeedPostsProvider).valueOrNull;
      if ((myPosts != null && myPosts.isNotEmpty) ||
          catches.any((c) => c.isShared)) {
        done.add(OnboardingStep.firstShare);
      }
    }
    return done;
  }

  void _maybeCelebrate(String? uid, int doneCount, int total) async {
    if (doneCount < total) return;
    final already = await OnboardingChecklistPrefs.isCelebrated(uid);
    if (already || !mounted) return;
    await OnboardingChecklistPrefs.markCelebrated(uid);
    if (!mounted) return;
    AppToast.success(
      context,
      '🏆 Hooked-Profi! Du kennst alle Grundfunktionen.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _dismissedLocal) {
      return const SizedBox.shrink();
    }
    final user = ref.watch(currentUserProvider);
    final isLoggedIn = user != null;
    // Wenn eingeloggt, aber Profil-Setup noch nicht durch (handle fehlt),
    // verstecken — der Profile-Setup-Screen kümmert sich erst.
    if (isLoggedIn) {
      final profile = ref.watch(myProfileProvider).valueOrNull;
      if (profile?.handle == null || profile!.handle!.isEmpty) {
        return const SizedBox.shrink();
      }
    }

    final steps = isLoggedIn ? _authSteps : _anonSteps;
    final done = _completedSteps(isLoggedIn);
    final total = steps.length;
    final doneCount = steps.where(done.contains).length;

    // Bei 100% feiern und Karte schließen.
    if (doneCount >= total) {
      _maybeCelebrate(user?.uid, doneCount, total);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await OnboardingChecklistPrefs.dismiss(user?.uid);
        if (mounted) setState(() => _dismissedLocal = true);
      });
      return const SizedBox.shrink();
    }

    final c = ApexColors.of(context);
    final progress = doneCount / total;
    final headline = isLoggedIn
        ? (doneCount == 0
            ? 'Lerne Hooked in $total Schritten kennen'
            : 'Noch ${total - doneCount} bis zum Hooked-Profi')
        : (doneCount == 0
            ? 'In 3 Schritten startklar'
            : 'Noch ${total - doneCount} bis zum Start');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ApexColors.primary.withAlpha(60)),
        boxShadow: [
          BoxShadow(
            color: ApexColors.primary.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: ApexColors.primary.withAlpha(30),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ApexColors.primary.withAlpha(80),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$doneCount/$total',
                      style: const TextStyle(
                        fontFamily: 'Rajdhani',
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: ApexColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ERSTE SCHRITTE',
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.6,
                            color: ApexColors.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          headline,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: ApexColors.primary.withAlpha(28),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              ApexColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _expanded ? 'Einklappen' : 'Ausklappen',
                    icon: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: c.textMuted,
                      ),
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  IconButton(
                    tooltip: 'Ausblenden',
                    icon: Icon(Icons.close, size: 18, color: c.textMuted),
                    onPressed: () async {
                      await OnboardingChecklistPrefs.dismiss(user?.uid);
                      if (mounted) setState(() => _dismissedLocal = true);
                    },
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: !_expanded
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      Divider(height: 1, color: c.border),
                      for (final step in steps)
                        _StepRow(
                          step: step,
                          done: done.contains(step),
                          onTap: () => context.push(step.route),
                        ),
                      const SizedBox(height: 4),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.done,
    required this.onTap,
  });

  final OnboardingStep step;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: done ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? ApexColors.primary
                    : ApexColors.primary.withAlpha(20),
                border: Border.all(
                  color: done
                      ? ApexColors.primary
                      : ApexColors.primary.withAlpha(80),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Icon(step.icon, size: 14, color: ApexColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                step.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: done ? c.textMuted : c.textPrimary,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: c.textMuted,
                ),
              ),
            ),
            if (!done)
              Row(
                children: [
                  Text(
                    step.cta,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ApexColors.primary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: ApexColors.primary,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
