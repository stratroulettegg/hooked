import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/catch_entry.dart';
import '../services/app_paths.dart';

/// Quadratisches Thumbnail für einen Fang.
///
/// Reihenfolge der Quellen:
/// 1. Eigenes Foto (`photoPath`)
/// 2. Lexikon-Bild der Art (`species.imageAsset`)
/// 3. Verlauf mit Emoji der Art
class CatchThumb extends StatelessWidget {
  const CatchThumb({
    super.key,
    required this.species,
    required this.photoPath,
    this.size = 56,
    this.radius = 12,
  });

  final FishSpecies species;
  final String? photoPath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final file = AppPaths.photoFile(photoPath);
    final br = BorderRadius.circular(radius);

    if (file != null) {
      return ClipRRect(
        borderRadius: br,
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
        ),
      );
    }

    final asset = species.imageAsset;
    if (asset != null) {
      return ClipRRect(
        borderRadius: br,
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ApexColors.primary.withAlpha(30),
                  ApexColors.primary.withAlpha(12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: br,
            ),
            child: _emojiFallback(),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ApexColors.primary.withAlpha(30),
            ApexColors.primary.withAlpha(12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: br,
      ),
      child: _emojiFallback(),
    );
  }

  Widget _emojiFallback() => Center(
    child: Text(species.emoji, style: TextStyle(fontSize: size * 0.46)),
  );
}
