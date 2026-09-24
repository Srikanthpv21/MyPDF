import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ReadingMode {
  light,
  sepia,
  night,
}

class AppTheme {
  // Brand colors - Crimson Red theme
  static const Color primary = Color(0xFFDC2626); // Crimson Red
  static const Color primaryLight = Color(0xFFEF4444);
  static const Color primaryDark = Color(0xFF991B1B);
  static const Color accent = Color(0xFFF43F5E); // Crimson Rose

  // Surface colors (Dark Theme)
  static const Color darkBg = Color(0xFF0B0F19);
  static const Color darkSurface = Color(0xFF151C2C);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);

  // Surface colors (Light Theme)
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);

  // Reading Mode Color Filters for PDF Canvas
  // 1. Inverted Night Matrix
  static const List<double> nightModeMatrix = <double>[
    -1.0, 0.0, 0.0, 0.0, 255.0,
    0.0, -1.0, 0.0, 0.0, 255.0,
    0.0, 0.0, -1.0, 0.0, 255.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ];

  // 2. Warm Sepia Filter Matrix
  static const List<double> sepiaModeMatrix = <double>[
    0.393 * 1.1, 0.769 * 0.9, 0.189 * 0.7, 0.0, 15.0,
    0.349 * 1.0, 0.686 * 1.0, 0.168 * 0.6, 0.0, 10.0,
    0.272 * 0.8, 0.534 * 0.8, 0.131 * 0.9, 0.0, 0.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: darkSurface,
        surfaceContainerHighest: darkCard,
        onSurface: Colors.white,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: lightSurface,
        surfaceContainerHighest: lightCard,
        onSurface: Color(0xFF0F172A),
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
    );
  }
}
