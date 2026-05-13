import 'dart:io';

import 'package:flutter/material.dart';
import '../../shared/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/auth_service.dart';
import '../../shared/services/firebase/user_profile_providers.dart';
import '../../shared/services/firebase/user_profile_service.dart';
import '../../shared/utils/permission_dialogs.dart';
import '../../shared/widgets/permission_pre_prompt.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Erlaubt dem User, Anzeigename und Profilbild zu ändern.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _steckbriefCtrl = TextEditingController();
  final Set<FishSpecies> _targetSpecies = <FishSpecies>{};
  File? _pickedPhoto;
  bool _removePhoto = false;
  bool _saving = false;
  bool _profileLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    _nameCtrl.text = user?.displayName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _steckbriefCtrl.dispose();
    super.dispose();
  }

  /// Initialwerte (Steckbrief + Zielfisch) aus Firestore beim ersten Build
  /// einlesen — danach lokal halten, damit der User beim Tippen nicht
  /// überschrieben wird.
  void _hydrateFromProfile(UserProfile profile) {
    if (_profileLoaded) return;
    _profileLoaded = true;
    _steckbriefCtrl.text = profile.steckbrief ?? '';
    _targetSpecies
      ..clear()
      ..addAll(profile.targetSpecies);
  }

  Future<void> _pickPhoto() async {
    final ok = await PermissionPrePrompt.ensure(context, PermissionKind.photos);
    if (!ok || !mounted) return;
    final picker = ImagePicker();
    try {
      // Profilbilder werden klein angezeigt (Avatar) – stark komprimieren
      // spart Upload-Bandbreite und Storage-Quota.
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (picked == null) return;
      setState(() {
        _pickedPhoto = File(picked.path);
        _removePhoto = false;
      });
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
    final nameErr = validateDisplayName(_nameCtrl.text);
    if (nameErr != null) {
      setState(() => _error = nameErr);
      return;
    }
    final steckbriefErr = validateSteckbrief(_steckbriefCtrl.text);
    if (steckbriefErr != null) {
      setState(() => _error = steckbriefErr);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await AuthService.instance.updateProfile(
      displayName: _nameCtrl.text,
      photoFile: _pickedPhoto,
      removePhoto: _removePhoto,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      // Steckbrief + Zielfisch separat in userProfiles/{uid} speichern.
      try {
        final user = AuthService.instance.currentUser;
        await UserProfileService.instance.upsertOwnProfile(
          displayName: user?.displayName,
          photoUrl: user?.photoURL,
          steckbrief: _steckbriefCtrl.text,
          targetSpecies: _targetSpecies.toList(),
        );
      } catch (_) {
        // Best-effort — wenn Cloud-Write scheitert, bleibt lokal alles gut.
      }
      // Provider neu lesen, damit der Avatar im Profil sofort aktualisiert.
      ref.invalidate(authStateProvider);
      if (!mounted) return;
      AppToast.success(context, 'Profil aktualisiert.');
      context.pop();
    } else {
      setState(() {
        _saving = false;
        _error = res.errorMessage ?? res.errorCode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final c = ApexColors.of(context);

    if (user == null) {
      return Scaffold(
        appBar: const ApexAppBar(),
        body: const Center(child: Text('Nicht angemeldet')),
      );
    }

    // Profil-Daten einmal aus Firestore hydratisieren.
    final profileAsync = ref.watch(myProfileProvider);
    profileAsync.whenData((profile) {
      if (profile != null) _hydrateFromProfile(profile);
    });

    ImageProvider? avatar;
    if (_pickedPhoto != null) {
      avatar = FileImage(_pickedPhoto!);
    } else if (!_removePhoto && user.photoURL != null) {
      avatar = NetworkImage(user.photoURL!);
    }

    return Scaffold(
      appBar: const ApexAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
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
          if (avatar != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _pickedPhoto = null;
                        _removePhoto = true;
                      }),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Bild entfernen'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Nickname',
              hintText: 'z. B. Pike-Hunter',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _steckbriefCtrl,
            enabled: !_saving,
            maxLength: 280,
            maxLines: 4,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'Steckbrief',
              hintText: 'Erzähl was über dich — Lieblingsgewässer, Stil, Vibe…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ZIELFISCH',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 12,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w700,
                color: c.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FishSpecies.values.map((s) {
              final selected = _targetSpecies.contains(s);
              return FilterChip(
                label: Text('${s.emoji} ${s.displayName}'),
                selected: selected,
                onSelected: _saving
                    ? null
                    : (v) => setState(() {
                        if (v) {
                          _targetSpecies.add(s);
                        } else {
                          _targetSpecies.remove(s);
                        }
                      }),
              );
            }).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
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
            label: const Text('Speichern'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Dein Nickname und Bild werden in deinem Firebase-Profil '
            'gespeichert. Andere User können sie sehen, wenn du Trips teilst.',
            style: TextStyle(fontSize: 11, color: c.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
