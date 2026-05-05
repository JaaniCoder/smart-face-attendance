import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Corporate Light Palette ─────────────────────────────────────────────
  static const Color primaryBlue   = Color(0xFF2563EB); // Royal Blue
  static const Color secondaryBlue = Color(0xFF3B82F6); // Lighter Blue
  static const Color successGreen  = Color(0xFF10B981); // Emerald
  static const Color dangerRed     = Color(0xFFEF4444); // Rose
  static const Color warningAmber  = Color(0xFFF59E0B); // Amber

  // Backgrounds
  static const Color bgLight       = Color(0xFFF8FAFC); // Slate 50 (App Background)
  static const Color surfaceLight  = Colors.white;      // Cards / Sheets
  static const Color borderSubtle  = Color(0xFFE2E8F0); // Slate 200

  // Text
  static const Color textDark      = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF64748B); // Slate 500
  static const Color textMuted     = Color(0xFF94A3B8); // Slate 400

  // ─── Shadows ─────────────────────────────────────────────────────────────
  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static BoxDecoration subtleCard({double radius = 12}) => BoxDecoration(
    color: surfaceLight,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderSubtle, width: 1),
    boxShadow: softShadow,
  );

  // ─── Theme Data ──────────────────────────────────────────────────────────
  static ThemeData lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: bgLight,
    primaryColor: primaryBlue,
    appBarTheme: AppBarTheme(
      backgroundColor: surfaceLight,
      elevation: 1,
      centerTitle: true,
      iconTheme: const IconThemeData(color: textDark),
      titleTextStyle: GoogleFonts.rajdhani(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textDark,
        letterSpacing: 0.5,
      ),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: surfaceLight,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: GoogleFonts.rajdhani(color: textMuted, fontSize: 14),
      labelStyle: GoogleFonts.rajdhani(color: textSecondary, fontSize: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: borderSubtle, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: dangerRed, width: 1),
      ),
      prefixIconColor: textSecondary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.rajdhani(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          letterSpacing: 1,
        ),
      ),
    ),
    textTheme: GoogleFonts.rajdhaniTextTheme(
      ThemeData.light().textTheme,
    ).copyWith(
      bodyLarge: GoogleFonts.rajdhani(fontSize: 16, fontWeight: FontWeight.w600, color: textDark),
      bodyMedium: GoogleFonts.rajdhani(fontSize: 14, color: textDark),
      bodySmall: GoogleFonts.rajdhani(fontSize: 12, color: textSecondary),
    ).apply(
      bodyColor: textDark,
      displayColor: primaryBlue,
    ),
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      secondary: secondaryBlue,
      error: dangerRed,
      surface: surfaceLight,
      onSurface: textDark,
    ),
  );
}