import 'package:flutter/material.dart';

/// Haken Dran – Farbpalette
/// Naturnahe Töne: Waldgrün, Wasserblau, Sand, Braun
abstract class AppColors {
  // Primärfarbe – Waldgrün
  static const Color primary = Color(0xFF2D6A4F);
  static const Color primaryLight = Color(0xFF52B788);
  static const Color primaryDark = Color(0xFF1B4332);

  // Sekundärfarbe – Wasserblau
  static const Color secondary = Color(0xFF1A759F);
  static const Color secondaryLight = Color(0xFF48CAE4);
  static const Color secondaryDark = Color(0xFF0A4F6B);

  // Akzent – Sandbeige / Goldgelb (XP, Level)
  static const Color accent = Color(0xFFD4A017);
  static const Color accentLight = Color(0xFFFFD166);

  // Neutrale Töne
  static const Color surface = Color(0xFFF8F4EF);
  static const Color surfaceDark = Color(0xFF1C2526);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF263033);

  // Feedback
  static const Color success = Color(0xFF52B788);
  static const Color error = Color(0xFFE63946);
  static const Color warning = Color(0xFFFFB703);

  // Text
  static const Color textPrimary = Color(0xFF1B2B1C);
  static const Color textSecondary = Color(0xFF5A6B5C);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textPrimaryDark = Color(0xFFE8F0E9);
  static const Color textSecondaryDark = Color(0xFF9EB09F);
}
