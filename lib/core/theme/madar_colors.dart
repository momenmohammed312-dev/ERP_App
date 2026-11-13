import 'package:flutter/material.dart';

/// Central color tokens for MADAR brand identity across Desktop, Mobile, and Web.
class MadarColors {
  static const Color bgDark = Color(0xFF0D1117);
  static const Color bgCard = Color(0xFF161B22);
  static const Color bgSurface = Color(0xFF1E2A3A);
  static const Color gold = Color(0xFFC9A84C);
  static const Color goldLight = Color(0xFFE8C97A);
  static const Color goldDark = Color(0xFF9B7B2B);
  static const Color border = Color(0xFF30363D);
  static const Color borderSubtle = Color(0x3330363D);
  static const Color textMuted = Color(0xFF7D8590);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textLight = Color(0xFFF0F6FC);
  static const Color success = Color(0xFF238636);
  static const Color error = Color(0xFFF85149);
  static const Color warning = Color(0xFFD29922);
  static const Color info = Color(0xFF388BFD);

  // ===========================================================================
  // Light Mode Tokens (Luminai Frosted Blue & SAP Morning Horizon Ergonomics)
  // ===========================================================================
  static const Color lightBgApp = Color(0xFFF2F7FC); // Ice Canvas
  static const Color lightBgCard = Color(0xFFFFFFFF); // Pure White Card Surface
  static const Color lightBgSurface = Color(0xFFEBF4FC); // Tinted Section Container
  static const Color lightPrimary = Color(0xFF0066FF); // Electric Cobalt
  static const Color lightPrimaryHover = Color(0xFF0052CC);
  static const Color lightDeepCobalt = Color(0xFF0A2540); // Deep Brand Navy
  static const Color lightBabyBlue = Color(0xFFBAE6FD);
  static const Color lightBabyBlueContainer = Color(0xFFE0F2FE); // Soft Tonal Fill
  static const Color lightBorder = Color(0xFFCDE2F5); // Structural Whisper Border
  static const Color lightBorderSubtle = Color(0xFFE2EFF9);
  static const Color lightTextPrimary = Color(0xFF0B192C); // Deep Charcoal Navy
  static const Color lightTextSecondary = Color(0xFF526E8C); // Slate Secondary
  static const Color lightTextMuted = Color(0xFF8BA2BC); // Tertiary/Muted
}

/// Dynamic theme tokens helper extending [BuildContext].
extension MadarThemeContext on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get bgCanvas => isDarkMode ? MadarColors.bgDark : MadarColors.lightBgApp;
  Color get bgCard => isDarkMode ? MadarColors.bgCard : MadarColors.lightBgCard;
  Color get bgSurface => isDarkMode ? MadarColors.bgSurface : MadarColors.lightBgSurface;
  Color get textPrimary => isDarkMode ? MadarColors.textLight : MadarColors.lightTextPrimary;
  Color get textSecondary => isDarkMode ? MadarColors.textSecondary : MadarColors.lightTextSecondary;
  Color get textMuted => isDarkMode ? MadarColors.textMuted : MadarColors.lightTextMuted;
  Color get borderColor => isDarkMode ? MadarColors.border : MadarColors.lightBorder;
  Color get borderSubtle => isDarkMode ? MadarColors.borderSubtle : MadarColors.lightBorderSubtle;
  Color get primaryColor => isDarkMode ? MadarColors.gold : MadarColors.lightPrimary;
  Color get primaryContainer => isDarkMode ? const Color(0x26C9A84C) : MadarColors.lightBabyBlueContainer;
}
