import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/home/modern_home.dart';

void main() {
  setUp(() {
    PlatformUtils.debugOverrideIsMobile = null;
  });

  tearDown(() {
    PlatformUtils.debugOverrideIsMobile = null;
  });

  group('ModernHomeScreen Tab & Navigation Configuration', () {
    testWidgets(
      'Desktop mode: 8 tabs, staff tab present at index 4, custody at 5, cashier at 6',
      (WidgetTester tester) async {
        PlatformUtils.debugOverrideIsMobile = false;

        // Platform flag assertions
        expect(PlatformUtils.isMobile, isFalse);
        expect(PlatformUtils.isDesktop, isTrue);
        expect(PlatformUtils.hidesStaffFeaturesOnMobile, isFalse);

        // Tab count and index assertions
        expect(ModernHomeScreen.tabCount, equals(8));
        expect(ModernHomeScreen.productsTabIndex, equals(1));
        expect(ModernHomeScreen.customersTabIndex, equals(2));
        expect(ModernHomeScreen.suppliersTabIndex, equals(3));
        expect(ModernHomeScreen.staffTabIndex, equals(4));
        expect(ModernHomeScreen.custodyTabIndex, equals(5));
        expect(ModernHomeScreen.cashierTabIndex, equals(6));
        expect(ModernHomeScreen.reportsTabIndex, equals(7));

        late AppLocalizations l10n;

        // Render TabBar using ModernHomeScreen.buildTabs
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ar'),
            home: Builder(
              builder: (context) {
                l10n = AppLocalizations.of(context);
                final tabs = ModernHomeScreen.buildTabs(l10n);
                return DefaultTabController(
                  length: tabs.length,
                  child: Scaffold(
                    appBar: AppBar(
                      bottom: TabBar(tabs: tabs),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify total tab widgets rendered
        final tabWidgets = tester.widgetList<Tab>(find.byType(Tab)).toList();
        expect(tabWidgets.length, equals(8));

        // Verify each tab position
        expect(tabWidgets[0].text, equals(l10n.dashboard));
        expect(tabWidgets[1].text, equals(l10n.products));
        expect(tabWidgets[2].text, equals(l10n.customer_list));
        expect(tabWidgets[3].text, equals(l10n.suppliers));
        expect(tabWidgets[4].text, equals('الموظفين'));
        expect(tabWidgets[5].text, equals('العهد المالية'));
        expect(tabWidgets[6].text, equals(l10n.cash));
        expect(tabWidgets[7].text, equals(l10n.reports));

        // Staff tab specifically exists on desktop
        expect(find.text('الموظفين'), findsOneWidget);
      },
    );

    testWidgets(
      'Mobile mode: 7 tabs, staff tab absent, custody at 4, cashier at index 5, reports at index 6',
      (WidgetTester tester) async {
        PlatformUtils.debugOverrideIsMobile = true;

        // Platform flag assertions
        expect(PlatformUtils.isMobile, isTrue);
        expect(PlatformUtils.isDesktop, isFalse);
        expect(PlatformUtils.hidesStaffFeaturesOnMobile, isTrue);

        // Tab count and index assertions
        expect(ModernHomeScreen.tabCount, equals(7));
        expect(ModernHomeScreen.productsTabIndex, equals(1));
        expect(ModernHomeScreen.customersTabIndex, equals(2));
        expect(ModernHomeScreen.suppliersTabIndex, equals(3));
        expect(ModernHomeScreen.staffTabIndex, isNull);
        expect(ModernHomeScreen.custodyTabIndex, equals(4));
        expect(ModernHomeScreen.cashierTabIndex, equals(5));
        expect(ModernHomeScreen.reportsTabIndex, equals(6));

        late AppLocalizations l10n;

        // Render TabBar using ModernHomeScreen.buildTabs
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ar'),
            home: Builder(
              builder: (context) {
                l10n = AppLocalizations.of(context);
                final tabs = ModernHomeScreen.buildTabs(l10n);
                return DefaultTabController(
                  length: tabs.length,
                  child: Scaffold(
                    appBar: AppBar(
                      bottom: TabBar(tabs: tabs),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify total tab widgets rendered
        final tabWidgets = tester.widgetList<Tab>(find.byType(Tab)).toList();
        expect(tabWidgets.length, equals(7));

        // Verify each tab position
        expect(tabWidgets[0].text, equals(l10n.dashboard));
        expect(tabWidgets[1].text, equals(l10n.products));
        expect(tabWidgets[2].text, equals(l10n.customer_list));
        expect(tabWidgets[3].text, equals(l10n.suppliers));
        expect(tabWidgets[4].text, equals('العهد المالية'));
        expect(tabWidgets[5].text, equals(l10n.cash));
        expect(tabWidgets[6].text, equals(l10n.reports));

        // Staff tab strictly absent on mobile
        expect(find.text('الموظفين'), findsNothing);
      },
    );
  });
}
