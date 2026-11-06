import 'package:flutter/material.dart';
import '../theme/madar_colors.dart';

class AppTheme {
  static const String arabicFontFamily = 'NotoSansArabic';

  static ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: MadarColors.lightPrimary, // #0066FF
        onPrimary: Colors.white,
        primaryContainer: MadarColors.lightBabyBlueContainer, // #E0F2FE
        onPrimaryContainer: MadarColors.lightPrimary,
        secondary: MadarColors.lightDeepCobalt, // #0A2540
        onSecondary: Colors.white,
        secondaryContainer: MadarColors.lightBgSurface, // #EBF4FC
        onSecondaryContainer: MadarColors.lightDeepCobalt,
        tertiary: Color(0xFF0284C7),
        surface: MadarColors.lightBgCard, // #FFFFFF
        onSurface: MadarColors.lightTextPrimary, // #0B192C
        surfaceContainerHighest: MadarColors.lightBgSurface,
        surfaceContainerLow: Color(0xFFF8FAFD),
        outline: MadarColors.lightBorder, // #CDE2F5
        outlineVariant: MadarColors.lightBorderSubtle, // #E2EFF9
        error: Color(0xFFEF4444),
        onError: Colors.white,
      ),
      fontFamily: arabicFontFamily,
      appBarTheme: getAppBarTheme(isDark: false),
      scaffoldBackgroundColor: MadarColors.lightBgApp, // #F2F7FC
      cardTheme: const CardThemeData(
        color: MadarColors.lightBgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: MadarColors.lightBorder, width: 1.2),
        ),
      ),
      elevatedButtonTheme: getElevatedButtonTheme(isDark: false),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MadarColors.lightPrimary,
          backgroundColor: const Color(0x0F0066FF), // Translucent blue tint
          side: const BorderSide(color: MadarColors.lightPrimary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: arabicFontFamily,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MadarColors.lightBabyBlueContainer,
          foregroundColor: MadarColors.lightPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: arabicFontFamily,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MadarColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MadarColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MadarColors.lightPrimary, width: 2),
        ),
        hintStyle: const TextStyle(color: MadarColors.lightTextMuted),
        labelStyle: const TextStyle(color: MadarColors.lightTextSecondary),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(MadarColors.lightBgSurface),
        dataRowColor: WidgetStateProperty.all(Colors.white),
        headingTextStyle: const TextStyle(
          color: MadarColors.lightTextPrimary,
          fontWeight: FontWeight.bold,
          fontFamily: arabicFontFamily,
        ),
        dataTextStyle: const TextStyle(
          color: MadarColors.lightTextPrimary,
          fontFamily: arabicFontFamily,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: MadarColors.lightBorderSubtle,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: MadarColors.lightPrimary,
        unselectedItemColor: MadarColors.lightTextMuted,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        headerBackgroundColor: MadarColors.lightPrimary,
        headerForegroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        dayStyle: const TextStyle(color: MadarColors.lightTextPrimary),
        yearStyle: const TextStyle(color: MadarColors.lightTextPrimary),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          if (states.contains(WidgetState.disabled)) {
            return MadarColors.lightTextMuted;
          }
          return MadarColors.lightTextPrimary;
        }),
        todayForegroundColor: WidgetStateProperty.all(MadarColors.lightPrimary),
        todayBorder: const BorderSide(color: MadarColors.lightPrimary),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return MadarColors.lightTextPrimary;
        }),
      ),
    );
  }

  static ThemeData getDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        secondary: Color(0xFFBDBDBD), // Light grey
        primary: Colors.white, // White
        surface: Color(0xFF0D1117), // GitHub dark
        onPrimary: Color(0xFF0D1117),
        onSecondary: Color(0xFF0D1117),
        onSurface: Color(0xFFE6EDF3),
        surfaceTint: Color(0xFF30363D),
        surfaceContainerHighest: Color(0xFF161B22),
      ),
      fontFamily: arabicFontFamily,
      appBarTheme: getAppBarTheme(isDark: true),
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF161B22),
        selectedItemColor: Colors.white,
        unselectedItemColor: Color(0xFF8B949E),
      ),
      elevatedButtonTheme: getElevatedButtonTheme(isDark: true),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0x1AFFFFFF),
          side: const BorderSide(color: Color(0xFF30363D), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: arabicFontFamily,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF21262D),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: arabicFontFamily,
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF161B22),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF21262D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        selectedColor: Color(0xFFC9A84C),
        style: ListTileStyle.list,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF21262D)),
        dataRowColor: WidgetStateProperty.all(const Color(0xFF161B22)),
        headingTextStyle: const TextStyle(
          color: Color(0xFFE6EDF3),
          fontWeight: FontWeight.bold,
          fontFamily: arabicFontFamily,
        ),
        dataTextStyle: const TextStyle(
          color: Color(0xFFE6EDF3),
          fontFamily: arabicFontFamily,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFF161B22),
        headerBackgroundColor: Colors.black,
        headerForegroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        dayStyle: const TextStyle(color: Colors.white),
        yearStyle: const TextStyle(color: Colors.white),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey;
          }
          return Colors.white;
        }),
        todayForegroundColor: WidgetStateProperty.all(Colors.white),
        todayBorder: const BorderSide(color: Colors.white),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          return Colors.white;
        }),
      ),
    );
  }

  static ElevatedButtonThemeData getElevatedButtonTheme({
    required bool isDark,
  }) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: isDark ? Colors.white : MadarColors.lightPrimary,
        foregroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        textStyle: TextStyle(
          color: isDark ? Colors.black : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          fontFamily: arabicFontFamily,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }

  static AppBarTheme getAppBarTheme({required bool isDark}) {
    return AppBarTheme(
      backgroundColor: isDark
          ? const Color(0xFF161B22)
          : Colors.white,
      foregroundColor: isDark
          ? const Color(0xFFE6EDF3)
          : MadarColors.lightTextPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: isDark ? const Color(0xFFE6EDF3) : MadarColors.lightTextPrimary,
        fontFamily: arabicFontFamily,
      ),
    );
  }
}
