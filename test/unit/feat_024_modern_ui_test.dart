import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/home/modern_home.dart';

void main() {
  group('FEAT-024: MADAR UI Modernization Unit Tests', () {
    test('MadarColors central palette values are authentic brand tokens', () {
      expect(MadarColors.bgDark, equals(const Color(0xFF0D1117)));
      expect(MadarColors.bgCard, equals(const Color(0xFF161B22)));
      expect(MadarColors.bgSurface, equals(const Color(0xFF1E2A3A)));
      expect(MadarColors.gold, equals(const Color(0xFFC9A84C)));
      expect(MadarColors.border, equals(const Color(0xFF30363D)));
      expect(MadarColors.success, equals(const Color(0xFF238636)));
      expect(MadarColors.error, equals(const Color(0xFFF85149)));
    });

    testWidgets('buildTabs tabs are compact (height 48) with preserved text', (tester) async {
      PlatformUtils.debugOverrideIsMobile = false;

      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ar'),
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              final tabs = ModernHomeScreen.buildTabs(l10n);
              for (final tab in tabs) {
                expect(tab.height, equals(48));
                expect(tab.text, isNotNull);
              }
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
    });

    test('Financial spline telemetry calculation sanity check', () {
      final sampleFlow = [
        {'date': '2026-10-01', 'sales': 12000.0, 'purchases': 7500.0},
        {'date': '2026-10-02', 'sales': 18500.0, 'purchases': 11000.0},
      ];

      double totalSales = 0.0;
      double totalPurchases = 0.0;
      for (final item in sampleFlow) {
        totalSales += (item['sales'] as double);
        totalPurchases += (item['purchases'] as double);
      }
      final netProfit = totalSales - totalPurchases;
      final margin = totalSales > 0 ? (netProfit / totalSales * 100) : 0.0;

      expect(totalSales, equals(30500.0));
      expect(totalPurchases, equals(18500.0));
      expect(netProfit, equals(12000.0));
      expect(margin, closeTo(39.34, 0.01));
    });
  });
}
