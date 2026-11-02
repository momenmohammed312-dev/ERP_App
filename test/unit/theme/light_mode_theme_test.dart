import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/theme.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/provider/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Light Mode Design Tokens & Configuration', () {
    test('AppTheme.getLightTheme has correct Luminai & SAP tokens', () {
      final theme = AppTheme.getLightTheme();

      expect(theme.brightness, equals(Brightness.light));
      expect(theme.colorScheme.primary, equals(const Color(0xFF0066FF)));
      expect(theme.colorScheme.secondary, equals(const Color(0xFF0A2540)));
      expect(theme.colorScheme.surface, equals(const Color(0xFFFFFFFF)));
      expect(theme.colorScheme.onSurface, equals(const Color(0xFF0B192C)));
      expect(theme.colorScheme.outline, equals(const Color(0xFFCDE2F5)));
      expect(theme.scaffoldBackgroundColor, equals(const Color(0xFFF2F7FC)));
      expect(theme.cardTheme.color, equals(const Color(0xFFFFFFFF)));
    });

    test('PosApp.getLightTheme applies high-contrast dark text on light surfaces', () {
      final theme = PosApp.getLightTheme();
      expect(theme.textTheme.bodyMedium?.color, equals(const Color(0xFF0B192C)));
      expect(theme.textTheme.titleMedium?.color, equals(const Color(0xFF0B192C)));
    });

    test('AppTheme.getDarkTheme remains 100% intact with GitHub Dark tokens', () {
      final theme = AppTheme.getDarkTheme();
      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(const Color(0xFF0D1117)));
      expect(theme.cardTheme.color, equals(const Color(0xFF161B22)));
    });

    test('SettingsService persists and retrieves AppThemeMode correctly', () async {
      // Default is dark
      final initial = await SettingsService.getAppThemeMode();
      expect(initial, equals(ThemeMode.dark));

      // Switch to light
      await SettingsService.setAppThemeMode(ThemeMode.light);
      final afterLight = await SettingsService.getAppThemeMode();
      expect(afterLight, equals(ThemeMode.light));

      // Switch back to dark
      await SettingsService.setAppThemeMode(ThemeMode.dark);
      final afterDark = await SettingsService.getAppThemeMode();
      expect(afterDark, equals(ThemeMode.dark));
    });

    test('themeModeProvider toggles and notifies listeners', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(themeModeProvider.notifier);
      expect(container.read(themeModeProvider), equals(ThemeMode.dark));

      await notifier.toggleTheme(false); // false = light mode
      expect(container.read(themeModeProvider), equals(ThemeMode.light));

      await notifier.toggleTheme(true); // true = dark mode
      expect(container.read(themeModeProvider), equals(ThemeMode.dark));
    });
  });
}
