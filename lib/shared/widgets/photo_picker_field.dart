import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../services/app_paths.dart';

/// Wiederverwendbares Bild-Auswahlfeld für Fang & Spot.
///
/// Speichert das gewählte/aufgenommene Bild dauerhaft im App-Documents-Ordner
/// (`<docs>/photos/<uuid>.jpg`) und gibt den absoluten Pfad über [onChanged] zurück.
class PhotoPickerField extends StatefulWidget {
  const PhotoPickerField({
    super.key,
    required this.path,
    required this.onChanged,
    this.label = 'Foto',
    this.height = 180,
  });

  final String? path;
  final ValueChanged<String?> onChanged;
  final String label;
  final double height;

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final img = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 75,
      );
      if (img == null) return;
      final ext = p.extension(img.path).isNotEmpty
          ? p.extension(img.path)
          : '.jpg';
      final fileName = '${const Uuid().v4()}$ext';
      final dest = p.join(AppPaths.photos, fileName);
      await File(img.path).copy(dest);
      // Nur Dateinamen persistieren – absoluter Pfad ist auf iOS instabil
      widget.onChanged(fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Foto konnte nicht geladen werden: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: ApexColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final c = ApexColors.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_camera, color: ApexColors.primary),
                title: Text('Kamera', style: TextStyle(color: c.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: ApexColors.primary),
                title: Text(
                  'Aus Mediathek',
                  style: TextStyle(color: c.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final file = AppPaths.photoFile(widget.path);
    final hasPhoto = file != null;

    return GestureDetector(
      onTap: _busy ? null : _chooseSource,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasPhoto ? ApexColors.primary.withAlpha(80) : c.border,
            width: hasPhoto ? 1.5 : 1,
          ),
          image: hasPhoto
              ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          children: [
            if (!hasPhoto)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      color: c.textMuted,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _busy ? 'Lädt …' : '${widget.label} hinzufügen',
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            if (hasPhoto)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    _IconButton(icon: Icons.refresh, onTap: _chooseSource),
                    const SizedBox(width: 6),
                    _IconButton(
                      icon: Icons.close,
                      onTap: () => widget.onChanged(null),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(140),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
