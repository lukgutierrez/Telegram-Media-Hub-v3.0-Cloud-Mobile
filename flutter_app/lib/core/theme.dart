import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CyberTheme {
  static const Color bgDark = Color(0xFF050811);
  static const Color bgCard = Color(0xFF0A0F1D);
  static const Color bgCardHover = Color(0xFF0F172A);
  static const Color borderCyan = Color(0xFF00F0FF);
  static const Color neonGreen = Color(0xFF00FF41);
  static const Color neonCyan = Color(0xFF00F0FF);
  static const Color neonYellow = Color(0xFFFFE600);
  static const Color neonPurple = Color(0xFFA855F7);
  static const Color neonRed = Color(0xFFEF4444);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textLight = Color(0xFFF1F5F9);

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: neonCyan,
      canvasColor: bgDark,
      cardColor: bgCard,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        secondary: neonGreen,
        surface: bgCard,
        error: neonRed,
      ),
      textTheme: GoogleFonts.firaCodeTextTheme(
        ThemeData.dark().textTheme.apply(
          bodyColor: textLight,
          displayColor: textLight,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: neonCyan,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0B132B),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: neonCyan, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderCyan.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderCyan.withValues(alpha: 0.3)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: neonCyan, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonGreen.withValues(alpha: 0.15),
          foregroundColor: neonGreen,
          side: BorderSide(color: neonGreen.withValues(alpha: 0.6), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
        ),
      ),
    );
  }

  static BoxDecoration cyberCardBox({Color? borderColor, Color? bgColor}) {
    return BoxDecoration(
      color: bgColor ?? bgCard,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: (borderColor ?? borderCyan).withValues(alpha: 0.25),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: (borderColor ?? borderCyan).withValues(alpha: 0.05),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ],
    );
  }
}
