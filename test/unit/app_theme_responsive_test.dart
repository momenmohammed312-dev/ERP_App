import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/theme.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';

void main() {
  setUp(() {
    PlatformUtils.debugOverrideIsMobile = null;
  });

  tearDown(() {
    PlatformUtils.debugOverrideIsMobile = null;
  });

  group('PosApp responsive theme configuration', () {
    test('Desktop mode: standard visualDensity and unscaled textTheme (1.0)', () {
      PlatformUtils.debugOverrideIsMobile = false;

      final light = PosApp.getLightTheme();
      final dark = PosApp.getDarkTheme();

      expect(light.visualDensity, equals(VisualDensity.standard));
      expect(dark.visualDensity, equals(VisualDensity.standard));

      final baseLight = AppTheme.getLightTheme().textTheme;
      expect(
        light.textTheme.bodyMedium?.fontSize,
        equals(baseLight.bodyMedium?.fontSize),
      );
      expect(
        light.textTheme.titleLarge?.fontSize,
        equals(baseLight.titleLarge?.fontSize),
      );
    });

    test('Mobile mode: compact visualDensity and scaled textTheme (0.85)', () {
      PlatformUtils.debugOverrideIsMobile = true;

      final light = PosApp.getLightTheme();
      final dark = PosApp.getDarkTheme();

      expect(light.visualDensity, equals(VisualDensity.compact));
      expect(dark.visualDensity, equals(VisualDensity.compact));

      expect(light.textTheme.bodyMedium?.fontSize, closeTo(14.0 * 0.85, 0.001));
      expect(light.textTheme.titleLarge?.fontSize, closeTo(22.0 * 0.85, 0.001));
      expect(dark.textTheme.bodyMedium?.fontSize, closeTo(14.0 * 0.85, 0.001));
      expect(dark.textTheme.titleLarge?.fontSize, closeTo(22.0 * 0.85, 0.001));
    });
  });
}
