import 'package:flutter/material.dart';

class AppTheme {
  static const String arabicFontFamily = 'NotoSansArabic';

  static ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        secondary: Color(0xFF424242), // Dark grey
        primary: Color(0xFF212121), // Black
        surface: Color(0xFFF8F9FA),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFF1A1A1A),
        surfaceTint: Color(0xFFE0E0E0),
        surfaceContainerHighest: Color(0xFFE0E0E0),
      ),
      fontFamily: arabicFontFamily,
      appBarTheme: getAppBarTheme(isDark: false),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF212121),
        unselectedItemColor: Colors.grey,
      ),
      elevatedButtonTheme: getElevatedButtonTheme(isDark: false),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        headerBackgroundColor: Colors.black,
        headerForegroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        dayStyle: const TextStyle(color: Colors.black),
        yearStyle: const TextStyle(color: Colors.black),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey;
          }
          return Colors.black;
        }),
        todayForegroundColor: WidgetStateProperty.all(Colors.black),
        todayBorder: const BorderSide(color: Colors.black),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.black;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: isDark ? Colors.white : const Color(0xFF212121),
        foregroundColor: isDark ? Colors.black : Colors.white,
        textStyle: TextStyle(
          color: isDark ? Colors.black : Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
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
          : const Color(0xFFF8F9FA),
      foregroundColor: isDark
          ? const Color(0xFFE6EDF3)
          : const Color(0xFF1A1A1A),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 22,
        color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1A1A1A),
        fontFamily: arabicFontFamily,
      ),
    );
  }
}
