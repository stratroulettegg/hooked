import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../services/app_paths.dart';

/// Quadratisches Thumbnail für ein gespeichertes Foto. Fällt auf ein
/// Platzhalter-Icon zurück, wenn das Bild nicht gefunden wird.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 12,
    this.placeholder,
  });

  final String? path;
  final double size;
  final double radius;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final file = AppPaths.photoFile(path);
    final c = ApexColors.of(context);
    if (file == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: c.border),
        ),
        child: placeholder ??
            Icon(Icons.image_outlined, color: c.textMuted, size: size * 0.5),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
      ),
    );
  }
}
