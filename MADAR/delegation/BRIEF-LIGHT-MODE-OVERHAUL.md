# MADAR ERP — Light Mode & UI Modernization Brief
> نظام التفويض متعدد الوكلاء (OpenCode Delegation Brief)

```xml
<task>
Implement the official Light Mode theme and UI modernization across the MADAR POS/ERP Flutter application, adhering strictly to the Luminai Cobalt/Baby Blue palette, SAP Fiori Morning Horizon ergonomics, and Material Design 3 guidelines.

### 1. Architectural Core & Theme Persistence:
- In `lib/core/services/settings_service.dart`:
  - Add `static Future<ThemeMode> getAppThemeMode()` (default to `ThemeMode.dark`).
  - Add `static Future<void> setAppThemeMode(ThemeMode mode)`.
  - Persist setting in `SharedPreferences` under key `app_theme_mode`.
- Create `lib/core/provider/theme_provider.dart`:
  - Implement `themeModeProvider` using `StateNotifierProvider<ThemeModeNotifier, ThemeMode>` connected to `SettingsService`.
  - Expose `toggleTheme(bool isDark)` and `setTheme(ThemeMode mode)`.
- In `lib/app_bootstrap.dart`:
  - Replace hardcoded `themeMode: ThemeMode.dark` with `themeMode: ref.watch(themeModeProvider)`.
  - In `getLightTheme()`, ensure `textTheme.apply(...)` uses `bodyColor: const Color(0xFF0B192C)` and `displayColor: const Color(0xFF0B192C)` (fix the bug where bodyColor was white).

### 2. Design Tokens & Theme Configuration:
- In `lib/core/theme/madar_colors.dart`:
  - Retain all existing dark mode constants without deletion or alteration.
  - Add Light Mode tokens:
    * `lightBgApp = Color(0xFFF2F7FC)` (Ice Canvas)
    * `lightBgCard = Color(0xFFFFFFFF)` (Pure White Card)
    * `lightBgSurface = Color(0xFFEBF4FC)` (Tinted Container)
    * `lightPrimary = Color(0xFF0066FF)` (Electric Cobalt)
    * `lightPrimaryHover = Color(0xFF0052CC)`
    * `lightDeepCobalt = Color(0xFF0A2540)`
    * `lightBabyBlue = Color(0xFFBAE6FD)`
    * `lightBabyBlueContainer = Color(0xFFE0F2FE)`
    * `lightBorder = Color(0xFFCDE2F5)` (Structural Whisper Border)
    * `lightBorderSubtle = Color(0xFFE2EFF9)`
    * `lightTextPrimary = Color(0xFF0B192C)` (Deep Navy Charcoal)
    * `lightTextSecondary = Color(0xFF526E8C)` (Slate)
    * `lightTextMuted = Color(0xFF8BA2BC)`
- In `lib/core/config/theme.dart`:
  - Update `AppTheme.getLightTheme()`:
    * ColorScheme: primary `#0066FF`, onPrimary `#FFFFFF`, primaryContainer `#E0F2FE`, onPrimaryContainer `#0066FF`, secondary `#0A2540`, surface `#FFFFFF`, onSurface `#0B192C`, outline `#CDE2F5`, error `#EF4444`.
    * Scaffold background: `#F2F7FC`.
    * CardTheme: color `#FFFFFF`, elevation 0, shape `RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Color(0xFFCDE2F5), width: 1.2))`.
    * OutlinedButtonTheme: foregroundColor `#0066FF`, backgroundColor `Color(0x0F0066FF)` (6% translucent blue), border `BorderSide(color: Color(0xFF0066FF), width: 1.5)`, borderRadius 10px.
    * FilledButtonTheme: backgroundColor `#E0F2FE`, foregroundColor `#0066FF`, borderRadius 10px.
    * ElevatedButtonTheme: backgroundColor `#0066FF`, foregroundColor `#FFFFFF`, elevation 0, borderRadius 10px.
    * InputDecorationTheme: filled true, fillColor `#FFFFFF`, borders using `#CDE2F5` and focused border `#0066FF` (width 2).
    * DataTableTheme: headingRowColor `#EBF4FC`, dataRowColor `#FFFFFF`, header text bold in `#0B192C`.
    * Strictly keep `fontFamily: arabicFontFamily` (`NotoSansArabic`).
  - Keep `AppTheme.getDarkTheme()` 100% UNCHANGED.

### 3. Settings Screen Wiring:
- In `lib/ui/setting/settings.dart`:
  - Load initial theme state in `initState` via `SettingsService.getAppThemeMode()`.
  - Connect the dark mode `Switch`:
    * `value: _darkModeEnabled`
    * `onChanged: (val) { setState(() => _darkModeEnabled = val); ref.read(themeModeProvider.notifier).toggleTheme(val); }`
  - Update screen background, card surfaces, and text colors to dynamically react to `isDark ? ... : MadarColors.light...`.

### 4. In-App Header Logo Badge:
- In `lib/ui/home/modern_home.dart`:
  - Check `final isLight = Theme.of(context).brightness == Brightness.light;`
  - If `isLight`:
    * Logo container background: `#FFFFFF` (or `#F8FAFC`), border: `MadarColors.lightBorder`.
    * Logo image: Apply `ShaderMask` with `BlendMode.srcIn` using `LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF0A2540), Color(0xFF0066FF), Color(0xFF38BDF8)])`.
  - If dark mode: preserve current dark styling and gold fallback.
  - DO NOT modify external launcher icons or file assets.

### 5. Staff Pages Modernization:
- In `lib/ui/staff/attendance_settings_page.dart`:
  - Refactor chips, inputs, and section cards to respect theme colors (`Theme.of(context).cardTheme.color`, `Theme.of(context).colorScheme.outline`, etc.) instead of hardcoded `MadarColors.bgDark`.
- In `lib/ui/staff/staff_overview_page.dart`:
  - Remove duplicate redundant button "لوحة الموظفين" in header/actions.
  - Modernize stats cards with frosted borders and dual-tone icon badges.
</task>

<action_safety>
- Zero regressions on Dark Mode: It must look and behave exactly as before when Dark Mode is selected.
- Append-only DB rule: NO Drift migrations or schema files may be edited.
- Atomic operations: Financial and stock transactions remain fully atomic.
- Typography: Keep `NotoSansArabic` as the sole font family across the entire app.
- Outside assets: Do NOT touch `assets/logo/app_logo.ico` or external platform build files.
- Commits: Do NOT run `git commit` or `git add` — leave changes in the working tree for orchestrator review.
</action_safety>

<verification_loop>
Run these commands and fix any surfaced errors before concluding:
1. `dart analyze` (must have 0 errors)
2. `flutter test test/unit/` (all unit tests must pass)
Confirm `git status` shows only scoped modifications.
</verification_loop>

<structured_output_contract>
End with a clear, concise report containing:
1. Exact changes made and architectural rationale.
2. List of touched files.
3. Gate outcomes: `dart analyze` error count, `flutter test` results.
4. Any design nuances or decisions left open for review.
</structured_output_contract>
```
