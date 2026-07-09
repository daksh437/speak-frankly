import 'package:flutter/material.dart';

/// Central design system for a premium, cohesive look (light + dark).
/// Brand: violet primary, teal + coral accents. Rounded, soft-shadowed cards.
class AppTheme {
  static const seed = Color(0xFF6C5CE7); // violet

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final isLight = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight ? const Color(0xFFF7F6FC) : const Color(0xFF121016),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : const Color(0xFF1E1B26),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Per-scenario accent colors (by theme) + reusable gradients.
class AppColors {
  static const _byTheme = <String, Color>{
    'daily': Color(0xFF4C9AFF), // blue
    'work': Color(0xFF6C5CE7), // violet
    'travel': Color(0xFF00C2A8), // teal
    'social': Color(0xFFFF7A5A), // coral
  };

  static Color forScenario(String theme) => _byTheme[theme] ?? AppTheme.seed;

  /// A soft two-stop gradient from a base color (for accents / hero badges).
  static LinearGradient gradient(Color base) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [base, Color.lerp(base, Colors.white, 0.25)!.withValues(alpha: 0.95)],
      );

  static const correction = Color(0xFFF59E0B); // amber
  static const success = Color(0xFF10B981); // green
}
