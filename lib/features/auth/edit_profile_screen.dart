import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/firebase/auth_providers.dart';
import '../../shared/services/firebase/auth_service.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Erlaubt dem User, Anzeigename und Profilbild zu ändern.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  File? _pickedPhoto;
  bool _removePhoto = false;
  bool _saving = false;
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
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
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
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving) return;
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
      // Provider neu lesen, damit der Avatar im Profil sofort aktualisiert.
      ref.invalidate(authStateProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil aktualisiert.')));
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
            textInputAction: TextInputAction.done,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Nickname',
              hintText: 'z. B. Pike-Hunter',
              border: OutlineInputBorder(),
            ),
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
