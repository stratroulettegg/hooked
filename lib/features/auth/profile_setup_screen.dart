import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/auth_service.dart';
import '../../shared/services/firebase/user_profile_providers.dart';
import '../../shared/services/firebase/user_profile_service.dart';
import '../../shared/utils/permission_dialogs.dart';
import '../../shared/widgets/permission_pre_prompt.dart';
import '../../shared/widgets/app_toast.dart';

/// Pflicht-Onboarding nach Erst-Login.
///
/// - Username (`@handle`): pflicht, unique, 3–24 Zeichen
/// - Display-Name: pflicht, 2–40 Zeichen, frei wählbar
/// - Profilbild: optional
/// - Bio (`steckbrief`): optional, 0–280 Zeichen
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _handleCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _steckbriefCtrl = TextEditingController();

  File? _pickedPhoto;
  bool _saving = false;
  bool _hydrated = false;
  String? _formError;

  // Live-Verfügbarkeitsprüfung (debounced).
  Timer? _availabilityDebounce;
  String? _availabilityCheckedFor;
  bool? _availabilityFree; // null = nicht geprüft, true = frei, false = belegt
  bool _availabilityLoading = false;

  @override
  void dispose() {
    _availabilityDebounce?.cancel();
    _handleCtrl.dispose();
    _nameCtrl.dispose();
    _steckbriefCtrl.dispose();
    super.dispose();
  }

  /// Schlägt einen Default-Handle aus dem Auth-Display-Name vor.
  String _suggestHandle(String? source) {
    final base = (source ?? '').toLowerCase();
    final cleaned = base
        .replaceAll(RegExp(r'[äÄ]'), 'ae')
        .replaceAll(RegExp(r'[öÖ]'), 'oe')
        .replaceAll(RegExp(r'[üÜ]'), 'ue')
        .replaceAll(RegExp(r'[ß]'), 'ss')
        .replaceAll(RegExp(r'[^a-z0-9._]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'\.+'), '.');
    final trimmed = cleaned.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    if (trimmed.length < 3) return '';
    return trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
  }

  void _hydrateOnce() {
    if (_hydrated) return;
    _hydrated = true;
    final user = AuthService.instance.currentUser;
    final dn = user?.displayName ?? '';
    _nameCtrl.text = dn;
    final suggested = _suggestHandle(dn);
    if (suggested.isNotEmpty) {
      _handleCtrl.text = suggested;
      _scheduleAvailabilityCheck();
    }
  }

  void _onHandleChanged(String _) {
    setState(() {
      _availabilityFree = null;
      _availabilityCheckedFor = null;
    });
    _scheduleAvailabilityCheck();
  }

  void _scheduleAvailabilityCheck() {
    _availabilityDebounce?.cancel();
    _availabilityDebounce = Timer(const Duration(milliseconds: 400), () {
      _runAvailabilityCheck();
    });
  }

  Future<void> _runAvailabilityCheck() async {
    final raw = _handleCtrl.text.trim().toLowerCase();
    final formatErr = validateHandleFormat(raw);
    if (formatErr != null) return;
    if (_availabilityCheckedFor == raw) return;
    setState(() => _availabilityLoading = true);
    final owner = await UserProfileService.instance.getHandleOwner(raw);
    if (!mounted) return;
    final me = AuthService.instance.currentUser?.uid;
    setState(() {
      _availabilityCheckedFor = raw;
      _availabilityLoading = false;
      _availabilityFree = owner == null || owner == me;
    });
  }

  Future<void> _pickPhoto() async {
    final ok = await PermissionPrePrompt.ensure(context, PermissionKind.photos);
    if (!ok || !mounted) return;
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (picked == null) return;
      setState(() => _pickedPhoto = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      if (PermissionDialogs.isPermissionDenied(e)) {
        await PermissionDialogs.showPermissionDeniedDialog(context, e);
      } else if (mounted) {
        AppToast.error(context, 'Foto konnte nicht geladen werden: $e');
      }
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving) return;

    final handle = _handleCtrl.text.trim().toLowerCase();
    final displayName = _nameCtrl.text.trim();
    final steckbrief = _steckbriefCtrl.text.trim();

    final handleErr = validateHandleFormat(handle);
    if (handleErr != null) {
      setState(() => _formError = handleErr.message);
      return;
    }
    final nameErr = validateDisplayName(displayName);
    if (nameErr != null) {
      setState(() => _formError = nameErr);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      // 1) Auth-DisplayName + ggf. Foto setzen.
      final res = await AuthService.instance.updateProfile(
        displayName: displayName,
        photoFile: _pickedPhoto,
      );
      if (!res.isSuccess) {
        throw Exception(res.errorMessage ?? 'Profil konnte nicht gespeichert werden.');
      }

      // 2) Handle atomar reservieren (Cloud Function).
      await UserProfileService.instance.claimHandle(handle);

      // 3) Steckbrief + DisplayName-Spiegel ins Profil-Doc.
      final user = AuthService.instance.currentUser;
      await UserProfileService.instance.updateProfileBasics(
        displayName: user?.displayName,
        photoUrl: user?.photoURL,
        steckbrief: steckbrief.isEmpty ? null : steckbrief,
      );

      // Provider invalidieren, damit Router weiterleitet und das eigene
      // Profil sofort neu gelesen wird.
      ref.invalidate(authStateProvider);
      ref.invalidate(myProfileProvider);
      ref.invalidate(userProfileProvider(AuthService.instance.currentUser!.uid));

      if (!mounted) return;
      AppToast.success(context, 'Willkommen an Bord!');
      // Router-Redirect übernimmt das Weiterleiten zu /catches.
      context.go('/catches');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _hydrateOnce();
    final c = ApexColors.of(context);

    ImageProvider? avatar;
    if (_pickedPhoto != null) {
      avatar = FileImage(_pickedPhoto!);
    } else {
      final url = AuthService.instance.currentUser?.photoURL;
      if (url != null) avatar = NetworkImage(url);
    }

    return Scaffold(
      // Kein AppBar mit Back-Button — Setup ist nicht überspringbar.
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Text(
              'WILLKOMMEN BEI HOOKED',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 12,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w700,
                color: ApexColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Lass uns dein Profil einrichten',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: ApexColors.primary.withAlpha(40),
                    backgroundImage: avatar,
                    child: avatar == null
                        ? Icon(Icons.person, size: 56, color: ApexColors.primary)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Material(
                      color: ApexColors.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _saving ? null : _pickPhoto,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Profilbild (optional)',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ),
            const SizedBox(height: 28),
            // Username (Handle)
            TextField(
              controller: _handleCtrl,
              enabled: !_saving,
              maxLength: 24,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                _LowercaseFormatter(),
              ],
              onChanged: _onHandleChanged,
              decoration: InputDecoration(
                labelText: 'Benutzername *',
                hintText: 'z. B. max_angler',
                prefixText: '@',
                helperText:
                    'So wirst du gefunden. 3–24 Zeichen · a–z, 0–9, . und _.',
                helperMaxLines: 2,
                suffixIcon: _buildAvailabilitySuffix(c),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Display-Name
            TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              maxLength: 40,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Anzeigename *',
                hintText: 'z. B. Max M.',
                helperText: 'So wirst du angezeigt — im Feed und in Kommentaren.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Live-Preview
            _PreviewCard(
              displayName: _nameCtrl.text.trim(),
              handle: _handleCtrl.text.trim().toLowerCase(),
              photo: _pickedPhoto,
              fallbackPhotoUrl:
                  AuthService.instance.currentUser?.photoURL,
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 4),
            // Steckbrief
            TextField(
              controller: _steckbriefCtrl,
              enabled: !_saving,
              maxLength: 280,
              maxLines: 4,
              minLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'Steckbrief (optional)',
                hintText: 'Erzähl was über dich — Lieblingsgewässer, Stil, Vibe…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 8),
              Text(
                _formError!,
                style: TextStyle(color: ApexColors.strike, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: const Text('Profil speichern'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Dein Benutzername ist eindeutig und kann nur alle 30 Tage '
              'geändert werden. Anzeigename und Steckbrief kannst du jederzeit '
              'in den Einstellungen anpassen.',
              style: TextStyle(fontSize: 11, color: c.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.push('/settings/community-guidelines'),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontSize: 11, color: c.textMuted, height: 1.4),
                  children: [
                    const TextSpan(
                      text: 'Mit der Erstellung deines Profils akzeptierst du unsere ',
                    ),
                    TextSpan(
                      text: 'Community-Regeln',
                      style: TextStyle(
                        color: ApexColors.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const TextSpan(
                      text:
                          '. Hass, Hetze und anstößige Inhalte führen zur sofortigen '
                          'Sperrung des Kontos.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildAvailabilitySuffix(ApexColors c) {
    if (_availabilityLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final raw = _handleCtrl.text.trim().toLowerCase();
    if (raw.isEmpty) return null;
    if (validateHandleFormat(raw) != null) {
      return Icon(Icons.error_outline, color: ApexColors.strike);
    }
    if (_availabilityCheckedFor != raw) return null;
    if (_availabilityFree == true) {
      return Icon(Icons.check_circle, color: ApexColors.primary);
    }
    if (_availabilityFree == false) {
      return Icon(Icons.cancel, color: ApexColors.strike);
    }
    return null;
  }
}

/// Erzwingt Kleinschreibung im Handle-Feld, ohne den Cursor zu verlieren.
class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}

/// Live-Preview im Setup-Screen — zeigt User wie sein Profil im Feed
/// erscheinen wird (Anzeigename groß, @handle klein darunter).
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.displayName,
    required this.handle,
    required this.photo,
    required this.fallbackPhotoUrl,
  });

  final String displayName;
  final String handle;
  final File? photo;
  final String? fallbackPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final shownName = displayName.isEmpty ? 'Anzeigename' : displayName;
    final shownHandle = handle.isEmpty ? 'benutzername' : handle;

    ImageProvider? avatar;
    if (photo != null) {
      avatar = FileImage(photo!);
    } else if (fallbackPhotoUrl != null && fallbackPhotoUrl!.isNotEmpty) {
      avatar = NetworkImage(fallbackPhotoUrl!);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: ApexColors.primary.withAlpha(40),
            backgroundImage: avatar,
            child: avatar == null
                ? Icon(Icons.person, size: 22, color: ApexColors.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shownName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: displayName.isEmpty ? c.textMuted : c.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '@$shownHandle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Vorschau',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
