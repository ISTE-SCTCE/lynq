import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MemberTheme {
  // ISTE Brand Palette
  static const Color terracotta = Color(0xFFD97D55);
  static const Color cream = Color(0xFFF4E9D7);
  static const Color sage = Color(0xFFB8C4A9);
  static const Color teal = Color(0xFF6FA4AF);

  // Backgrounds
  static const Color bgDark = Color(0xFF141414);     // graphite black
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surface2Dark = Color(0xFF252525);
  static const Color surface3Dark = Color(0xFF2E2E2E);

  // Text
  static const Color textPrimary = Color(0xFFF4E9D7);   // cream
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textMuted = Color(0xFF666666);

  // Accent gradients
  static const List<Color> heroGradient = [
    Color(0xFFD97D55),
    Color(0xFFB8604A),
  ];

  static const List<Color> cardGradient = [
    Color(0xFF6FA4AF),
    Color(0xFF4A7A85),
  ];

  static const List<Color> membershipGradient = [
    Color(0xFF2A2A2A),
    Color(0xFF1A1A1A),
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: terracotta,
        secondary: teal,
        surface: surfaceDark,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: cream,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(
            fontSize: 32, fontWeight: FontWeight.bold, color: cream),
        displayMedium: GoogleFonts.spaceGrotesk(
            fontSize: 28, fontWeight: FontWeight.bold, color: cream),
        displaySmall: GoogleFonts.spaceGrotesk(
            fontSize: 24, fontWeight: FontWeight.bold, color: cream),
        headlineLarge: GoogleFonts.spaceGrotesk(
            fontSize: 22, fontWeight: FontWeight.w700, color: cream),
        headlineMedium: GoogleFonts.spaceGrotesk(
            fontSize: 18, fontWeight: FontWeight.w600, color: cream),
        titleLarge: GoogleFonts.spaceGrotesk(
            fontSize: 16, fontWeight: FontWeight.w700, color: cream),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: cream),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: textSecondary),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: textMuted),
        labelLarge: GoogleFonts.spaceGrotesk(
            fontSize: 14, fontWeight: FontWeight.w700, color: cream),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        iconTheme: IconThemeData(color: cream),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: terracotta,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          elevation: 0,
          textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: teal, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      useMaterial3: true,
    );
  }
}
