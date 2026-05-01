import 'package:flutter/material.dart';

/// Adaptive Farbpalette als ThemeExtension.
/// Markenwerte (primary, strike, score-Farben) sind statische Konstanten.
/// Adaptive Werte (Hintergründe, Rahmen, Text) sind Instanzfelder.
class ApexColors extends ThemeExtension<ApexColors> {
  const ApexColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primaryGlow,
    required this.cardShadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primaryGlow;
  final Color cardShadow;

  // ── Markenwerte (mode-unabhängig) ──────────────────────────────────────────
  static const primary = Color(0xFF00D4AA);
  static const primaryDark = Color(0xFF009E7E);
  static const strike = Color(0xFFFF6B35);
  static const scoreHigh = Color(0xFF00D4AA);
  static const scoreMid = Color(0xFFFFB800);
  static const scoreLow = Color(0xFFFF4B4B);
  // ── Temperatur-Skala (Wetter-Stat-Tiles, Forecast-Karten) ────────────────
  static const tempCold = Color(0xFF64B5F6); // < 5°C
  static const tempCool = Color(0xFF4DD0E1); // 5–15°C
  static const tempMild = Color(0xFF81C784); // 15–25°C
  static const tempWarm = Color(0xFFFF8A65); // > 25°C
  // ── System-UI ────────────────────────────────────────────────────────────
  // Spiegeln die `surface`-Werte der jeweiligen Palette wider und werden
  // für `SystemUiOverlayStyle` (System-Navigation-Bar) gebraucht, weil dort
  // `const` Farben nötig sind und damit kein Zugriff auf `ApexColors.of`.
  static const systemSurfaceDark = Color(0xFF0C1320);
  static const systemSurfaceLight = Color(0xFFFFFFFF);
  static Color get strikeGlow => strike.withAlpha(50);

  // ── Dark Palette ───────────────────────────────────────────────────────────
  static const dark = ApexColors(
    background: Color(0xFF06090F),
    surface: Color(0xFF0C1320),
    surfaceVariant: Color(0xFF111C2C),
    border: Color(0xFF1E3349),
    textPrimary: Color(0xFFDFECF8),
    textSecondary: Color(0xFF90B8D8), // war 0xFF5F80A0 (~4.3:1 → jetzt ~6.0:1)
    textMuted: Color(0xFF5280A0), // war 0xFF253D55 (~2.2:1 → jetzt ~4.1:1)
    primaryGlow: Color(0x2800D4AA),
    cardShadow: Color(0x00000000),
  );

  // ── Light Palette ──────────────────────────────────────────────────────────
  static const light = ApexColors(
    background: Color(0xFFECF2F9),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF3F7FC),
    border: Color(0xFFCDD9E6),
    textPrimary: Color(0xFF0A1822),
    textSecondary: Color(0xFF2E4F6A), // war 0xFF456070 (~2.6:1 → jetzt ~5.1:1)
    textMuted: Color(0xFF4A6880), // war 0xFF8BA4B8 (~1.6:1 → jetzt ~3.5:1)
    primaryGlow: Color(0x22009E7E),
    cardShadow: Color(0x18213450),
  );

  static ApexColors of(BuildContext context) =>
      Theme.of(context).extension<ApexColors>()!;

  @override
  ThemeExtension<ApexColors> copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? primaryGlow,
    Color? cardShadow,
  }) => ApexColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    primaryGlow: primaryGlow ?? this.primaryGlow,
    cardShadow: cardShadow ?? this.cardShadow,
  );

  @override
  ThemeExtension<ApexColors> lerp(ThemeExtension<ApexColors>? other, double t) {
    if (other is! ApexColors) return this;
    return ApexColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primaryGlow: Color.lerp(primaryGlow, other.primaryGlow, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

/// Convenience-Extension für schnellen Zugriff.
extension ApexThemeX on BuildContext {
  ApexColors get ac => ApexColors.of(this);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  static ThemeData get dark => _build(
    Brightness.dark,
    ApexColors.dark,
    ApexColors.primary,
    const Color(0xFF06090F),
  );
  static ThemeData get light => _build(
    Brightness.light,
    ApexColors.light,
    const Color(0xFF008A6C),
    Colors.white,
  );

  static ThemeData _build(
    Brightness brightness,
    ApexColors c,
    Color primaryColor,
    Color onPrimary,
  ) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryColor,
        onPrimary: onPrimary,
        primaryContainer: primaryColor.withAlpha(isDark ? 38 : 28),
        onPrimaryContainer: primaryColor,
        secondary: ApexColors.strike,
        onSecondary: Colors.white,
        secondaryContainer: ApexColors.strike.withAlpha(isDark ? 38 : 28),
        onSecondaryContainer: ApexColors.strike,
        tertiary: ApexColors.scoreMid,
        onTertiary: Colors.white,
        tertiaryContainer: ApexColors.scoreMid.withAlpha(38),
        onTertiaryContainer: ApexColors.scoreMid,
        error: ApexColors.scoreLow,
        onError: Colors.white,
        errorContainer: ApexColors.scoreLow.withAlpha(38),
        onErrorContainer: ApexColors.scoreLow,
        surface: c.surface,
        onSurface: c.textPrimary,
        surfaceContainerHighest: c.surfaceVariant,
        onSurfaceVariant: c.textSecondary,
        outline: c.border,
        outlineVariant: c.border.withAlpha(120),
        shadow: c.cardShadow,
        scrim: Colors.black,
        inverseSurface: isDark ? c.textPrimary : c.surface,
        onInverseSurface: isDark ? c.background : c.textPrimary,
        inversePrimary: primaryColor,
        surfaceDim: c.background,
        surfaceBright: c.surfaceVariant,
        surfaceContainerLowest: c.background,
        surfaceContainerLow: c.surface,
        surfaceContainer: c.surfaceVariant,
        surfaceContainerHigh: c.surfaceVariant,
      ),
      fontFamily: 'Rajdhani',

      // ── AppBar ──────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
          letterSpacing: 1.5,
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
      ),

      // ── Navigation Bar ──────────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        elevation: isDark ? 0 : 8,
        shadowColor: c.cardShadow,
        height: 70,
        indicatorColor: primaryColor.withAlpha(isDark ? 38 : 30),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primaryColor, size: 22);
          }
          return IconThemeData(color: c.textMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            );
          }
          return TextStyle(color: c.textMuted, fontSize: 11);
        }),
      ),

      // ── Cards ───────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: isDark ? 0 : 3,
        shadowColor: c.cardShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isDark ? BorderSide(color: c.border) : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),

      dividerTheme: DividerThemeData(color: c.border, thickness: 1),

      // ── Text ────────────────────────────────────────────────────────────────
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 64,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
          letterSpacing: 1,
          height: 1.0,
        ),
        headlineLarge: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
          letterSpacing: 0.3,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
          letterSpacing: 0.3,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 15, color: c.textPrimary),
        bodyMedium: TextStyle(fontSize: 13, color: c.textSecondary),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: primaryColor,
          letterSpacing: 1.5,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: c.textMuted,
          letterSpacing: 1.2,
        ),
      ),

      // ── Buttons ─────────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Rajdhani',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 1.5,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: onPrimary,
        elevation: isDark ? 0 : 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      // ── Input ───────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ApexColors.scoreLow),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ApexColors.scoreLow, width: 2),
        ),
        labelStyle: TextStyle(color: c.textSecondary, fontFamily: 'Rajdhani'),
        hintStyle: TextStyle(color: c.textMuted),
        prefixIconColor: c.textSecondary,
      ),

      // ── Chips ───────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        selectedColor: primaryColor.withAlpha(isDark ? 40 : 30),
        checkmarkColor: primaryColor,
        labelStyle: TextStyle(color: c.textPrimary, fontFamily: 'Rajdhani'),
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // ── Dialog ──────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: c.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }
}
