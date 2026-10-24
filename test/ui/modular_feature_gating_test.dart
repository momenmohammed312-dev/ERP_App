import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/core/provider/license_provider.dart';
import 'package:pos_offline_desktop/services/feature_gate_service.dart' hide FeatureGuard;
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/online_license_service.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:pos_offline_desktop/widgets/license/feature_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('ui_gating_test_');
    SecureLicenseStorage.useDirectory(tmpDir);
    HardwareIdService.debugMachineGuid = 'LIVE-TEST-MACHINE-001';
    HardwareIdService.debugInstallUuid = 'LIVE-TEST-INSTALL-001';
    OnlineLicenseService.apiUrlOverride = 'http://localhost:8000/license_api';
  });

  tearDown(() async {
    HardwareIdService.resetForTesting();
    OnlineLicenseService.apiUrlOverride = null;
    SecureLicenseStorage.useDirectory(Directory.systemTemp);
    try {
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('Virtual Device UI Test: Comprehensive Modular Feature Gating for all canonical Add-ons', (WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final onlineService = OnlineLicenseService();

    // ── Phase 1: Activate MO2-TEST-BASIC (Only core modules: pos, inventory, customers, reports) ──
    final basicRes = await tester.runAsync(() => onlineService.activateLicense('MO2-TEST-BASIC'));
    expect(basicRes?.isAllowed, isTrue);

    final activatedClicks = <String, int>{};
    final lockedClicks = <String, int>{};

    void recordClick(String key) => activatedClicks[key] = (activatedClicks[key] ?? 0) + 1;
    void recordLockedClick(String key) => lockedClicks[key] = (lockedClicks[key] ?? 0) + 1;

    Widget buildButton(String name, String feature, {bool core = false}) {
      return FeatureGuard(
        featureName: feature,
        lockedWidget: ElevatedButton(
          key: ValueKey('locked_$feature'),
          onPressed: () => recordLockedClick(feature),
          child: Text('$name (مغلق)'),
        ),
        child: ElevatedButton(
          key: ValueKey('active_$feature'),
          onPressed: () => recordClick(feature),
          child: Text(name),
        ),
      );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  // 1. Core modules (Always Unlocked)
                  buildButton('نقطة البيع', 'pos', core: true),
                  buildButton('المخزن والمنتجات', 'inventory', core: true),
                  buildButton('التقارير الأساسية', 'reports', core: true),

                  // 2. Canonical Add-on Modules (Audited directly from codebase)
                  buildButton('الموظفين', 'staff_management'),
                  buildButton('العهد المالية', 'custody'),
                  buildButton('الهوالك والتوالف', 'damaged_goods'),
                  buildButton('التصنيع', 'manufacturing'),

                  // 3. Sidebar Conditional Widgets
                  ConditionalWidget(
                    feature: 'custody',
                    fallback: const Text('تبويب العهد: غير متاح'),
                    child: const Text('تبويب العهد: متاح'),
                  ),
                  ConditionalWidget(
                    feature: 'staff_management',
                    fallback: const Text('تبويب الموظفين: غير متاح'),
                    child: const Text('تبويب الموظفين: متاح'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // ── Verify Basic License State ──
    // Core features MUST be unlocked
    expect(find.text('نقطة البيع'), findsOneWidget);
    expect(find.text('المخزن والمنتجات'), findsOneWidget);
    expect(find.text('التقارير الأساسية'), findsOneWidget);

    // Add-on modules MUST be LOCKED
    expect(find.text('الموظفين (مغلق)'), findsOneWidget);
    expect(find.text('العهد المالية (مغلق)'), findsOneWidget);
    expect(find.text('الهوالك والتوالف (مغلق)'), findsOneWidget);
    expect(find.text('التصنيع (مغلق)'), findsOneWidget);

    // Sidebar items MUST be fallback
    expect(find.text('تبويب العهد: غير متاح'), findsOneWidget);
    expect(find.text('تبويب الموظفين: غير متاح'), findsOneWidget);

    // Test tapping locked buttons
    await tester.tap(find.text('الموظفين (مغلق)'));
    await tester.tap(find.text('العهد المالية (مغلق)'));
    await tester.tap(find.text('الهوالك والتوالف (مغلق)'));
    await tester.tap(find.text('التصنيع (مغلق)'));
    await tester.pump();

    expect(lockedClicks['staff_management'], equals(1));
    expect(lockedClicks['custody'], equals(1));
    expect(lockedClicks['damaged_goods'], equals(1));
    expect(lockedClicks['manufacturing'], equals(1));
    expect(activatedClicks['staff_management'], isNull);

    // Test tapping an active core button
    await tester.tap(find.text('نقطة البيع'));
    await tester.pump();
    expect(activatedClicks['pos'], equals(1));

    // ── Phase 2: Live Upgrade to POS-NUR2-8921-X4K9 (All Add-ons Included) ──
    final upgradeRes = await tester.runAsync(() => onlineService.activateLicense('POS-NUR2-8921-X4K9'));
    expect(upgradeRes?.isAllowed, isTrue);

    // Trigger reactive Riverpod refresh
    container.read(licenseRefreshProvider.notifier).state++;
    await tester.runAsync(() => container.read(currentLicenseProvider.future));
    await tester.pump();

    // ── Verify Dynamically Unlocked State in UI without app restart ──
    expect(find.text('الموظفين (مغلق)'), findsNothing);
    expect(find.text('الموظفين'), findsOneWidget);

    expect(find.text('العهد المالية (مغلق)'), findsNothing);
    expect(find.text('العهد المالية'), findsOneWidget);

    expect(find.text('الهوالك والتوالف (مغلق)'), findsNothing);
    expect(find.text('الهوالك والتوالف'), findsOneWidget);

    expect(find.text('التصنيع (مغلق)'), findsNothing);
    expect(find.text('التصنيع'), findsOneWidget);

    // Sidebar items now active
    expect(find.text('تبويب العهد: غير متاح'), findsNothing);
    expect(find.text('تبويب العهد: متاح'), findsOneWidget);
    expect(find.text('تبويب الموظفين: غير متاح'), findsNothing);
    expect(find.text('تبويب الموظفين: متاح'), findsOneWidget);

    // Tap the newly unlocked add-on buttons to verify functionality
    await tester.tap(find.text('الموظفين'));
    await tester.tap(find.text('العهد المالية'));
    await tester.tap(find.text('الهوالك والتوالف'));
    await tester.tap(find.text('التصنيع'));
    await tester.pump();

    expect(activatedClicks['staff_management'], equals(1));
    expect(activatedClicks['custody'], equals(1));
    expect(activatedClicks['damaged_goods'], equals(1));
    expect(activatedClicks['manufacturing'], equals(1));
  });
}
