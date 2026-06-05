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

  // m-lynq Brand Theme Colors
  static const Color mBackground = Color(0xFFEBF3FC); // Celestial Soft Blue
  static const Color mSlate = Color(0xFF5F85A2);      // Slate Blue
  static const Color mDarkCharcoal = Color(0xFF111111); // Deep text/accent
  static const Color mWhite = Color(0xFFFFFFFF);
  static const Color mLightSlate = Color(0xFFD3E3F0);
  
  // Pastels for card backgrounds
  static const Color mPastelBlue = Color(0xFFD9E9F9);
  static const Color mPastelLavender = Color(0xFFE8E2F5);
  static const Color mPastelPeach = Color(0xFFFBE4D5);
  static const Color mPastelMint = Color(0xFFE1F3E2);

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: mBackground,
      colorScheme: const ColorScheme.light(
        primary: mSlate,
        secondary: mDarkCharcoal,
        surface: mWhite,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: mDarkCharcoal,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(
            fontSize: 32, fontWeight: FontWeight.bold, color: mDarkCharcoal),
        displayMedium: GoogleFonts.spaceGrotesk(
            fontSize: 28, fontWeight: FontWeight.bold, color: mDarkCharcoal),
        displaySmall: GoogleFonts.spaceGrotesk(
            fontSize: 24, fontWeight: FontWeight.bold, color: mDarkCharcoal),
        headlineLarge: GoogleFonts.spaceGrotesk(
            fontSize: 22, fontWeight: FontWeight.w700, color: mDarkCharcoal),
        headlineMedium: GoogleFonts.spaceGrotesk(
            fontSize: 18, fontWeight: FontWeight.w600, color: mDarkCharcoal),
        titleLarge: GoogleFonts.spaceGrotesk(
            fontSize: 16, fontWeight: FontWeight.w700, color: mDarkCharcoal),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: mDarkCharcoal),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: mDarkCharcoal.withOpacity(0.7)),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: mDarkCharcoal.withOpacity(0.5)),
        labelLarge: GoogleFonts.spaceGrotesk(
            fontSize: 14, fontWeight: FontWeight.w700, color: mDarkCharcoal),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: mDarkCharcoal),
        titleTextStyle: TextStyle(color: mDarkCharcoal, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: mDarkCharcoal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          elevation: 0,
          textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: mDarkCharcoal.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: mDarkCharcoal.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: mSlate, width: 2.0),
        ),
        hintStyle: GoogleFonts.inter(color: mDarkCharcoal.withOpacity(0.3), fontSize: 14),
        labelStyle: GoogleFonts.inter(color: mDarkCharcoal.withOpacity(0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData get darkTheme => lightTheme; // For m-lynq style consistency
}
