import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ── Brand Colors ──────────────────────────────────────────────────────────
  static const primary = Color(0xFF6C63FF);
  static const primaryDark = Color(0xFF4F46E5);
  static const primaryLight = Color(0xFFEEF2FF);
  static const accent = Color(0xFF06B6D4);
  static const orange = Color(0xFFF97316);
  static const purple = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const emerald = Color(0xFF10B981);

  // ── Light Mode ────────────────────────────────────────────────────────────
  static const bg = Color(0xFFF8FAFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVar = Color(0xFFF1F5FF);
  static const border = Color(0xFFE8EDFB);
  static const divider = Color(0xFFF0F4FF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF94A3B8);

  // ── Dark Mode ─────────────────────────────────────────────────────────────
  static const bgDark = Color(0xFF0A0B14);
  static const surfaceDark = Color(0xFF111827);
  static const surfaceVarDark = Color(0xFF1E293B);
  static const borderDark = Color(0xFF1E293B);
  static const textPrimaryDark = Color(0xFFF1F5F9);
  static const textSecondaryDark = Color(0xFF94A3B8);

  // ── Status ────────────────────────────────────────────────────────────────
  static const online = Color(0xFF22C55E);
  static const away = Color(0xFFF59E0B);
  static const busy = Color(0xFFEF4444);
  static const offline = Color(0xFF94A3B8);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient primaryGrad = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient accentGrad = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF0284C7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient purpleGrad = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFF6C63FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient orangeGrad = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFEF4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient emeraldGrad = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient darkGrad = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient meshGrad = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get light => themeWithColor(AppColors.primary, false);
  static ThemeData get dark => themeWithColor(AppColors.primary, true);

  static ThemeData themeWithColor(Color primaryColor, [bool isDark = false]) {
    final bg = isDark ? AppColors.bgDark : AppColors.bg;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final surfaceVar = isDark ? AppColors.surfaceVarDark : AppColors.surfaceVar;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textMuted =
        isDark ? AppColors.textSecondaryDark : AppColors.textMuted;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
            fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
        headlineLarge: GoogleFonts.inter(
            fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary),
        headlineMedium: GoogleFonts.inter(
            fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: GoogleFonts.inter(
            fontSize: 15, fontWeight: FontWeight.w400, color: textPrimary),
        bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
        bodySmall: GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w400, color: textMuted),
        labelLarge: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
            fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVar,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      bottomNavigationBarTheme:
          BottomNavigationBarThemeData(backgroundColor: surface),
    );
  }
}
