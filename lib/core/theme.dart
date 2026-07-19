import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color Palette from Design System
  static const Color primary = Color(0xFFD97D55); // Terracotta
  static const Color primaryDark = Color(0xFFC06B45);
  static const Color secondary = Color(0xFF6FA4AF); // Teal highlight
  static const Color darkGreen = Color(0xFF1E1E1E); // Surface dark
  
  static const Color backgroundLight = Color(0xFFF8F9FA); // Off-white modern
  static const Color backgroundDark = Color(0xFF141414); // True dark
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color textLight = Color(0xFF141414);
  static const Color textDark = Color(0xFFF4E9D7);

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surfaceLight,
        background: backgroundLight,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textLight,
        onBackground: textLight,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold, color: textLight),
        displayMedium: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.bold, color: textLight),
        displaySmall: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: textLight),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: textLight),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: textLight),
        titleLarge: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w600, color: textLight),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceLight,
        elevation: 0,
        iconTheme: IconThemeData(color: primary),
        titleTextStyle: TextStyle(color: primary, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), 
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceLight,
        selectedItemColor: primary,
        unselectedItemColor: Colors.grey,
        elevation: 8,
      ),
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surfaceDark,
        background: backgroundDark,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDark,
        onBackground: textDark,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold, color: textDark),
        displayMedium: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.bold, color: textDark),
        displaySmall: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: textDark),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: textDark),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: textDark),
        titleLarge: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w600, color: textDark),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundDark,
        elevation: 0,
        iconTheme: IconThemeData(color: textDark),
        titleTextStyle: TextStyle(color: textDark, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), 
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: secondary,
        unselectedItemColor: Colors.grey,
        elevation: 8,
      ),
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class AppColors {
  static const Color primary = AppTheme.primary;
  static const Color secondary = AppTheme.secondary;
  static const Color darkGreen = AppTheme.darkGreen;
  static const Color backgroundLight = AppTheme.backgroundLight;
  static const Color backgroundDark = AppTheme.backgroundDark;
  static const Color textLight = AppTheme.textLight;
  static const Color textDark = AppTheme.textDark;
  
  // WhatsApp Style Colors
  static const Color waTeal = Color(0xFF075E54);
  static const Color waTealLight = Color(0xFF128C7E);
  static const Color waGreen = Color(0xFF25D366);
  static const Color waBlueCheck = Color(0xFF34B7F1);
  static const Color waBg = Color(0xFFE5DDD5);
  static const Color waBubbleMine = Color(0xFFE7FFDB);
  static const Color waBubbleOther = Color(0xFFFFFFFF);
}
