import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/services/unified_print_service.dart';

/// FEAT-010: the MO production/consumption PDF card must render through
/// the unified print pipeline from plain maps - no Drift, no UI needed.
/// Font/logo loads are protected inside the service, so this also guards
/// against regressions that would crash the print path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // SettingsService reads shared_preferences (store info/logo): mock an
    // empty store so the test never needs the real plugin.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (MethodCall methodCall) async => <String, Object>{},
        );
  });

  test('P1: manufacturing card document builds and saves bytes', () async {
    final pdf = await UnifiedPrintService.generateUnifiedDocument(
      documentType: DocumentType.manufacturingCard,
      data: <String, dynamic>{
        'orderNumber': 'MO-TEST-1',
        'status': 'مكتمل',
        'orderType': 'تصنيع للغير',
        'customerName': 'عميل اختبار',
        'bomName': 'وصفة اختبار',
        'finishedProductName': 'منتج اختبار',
        'createdDate': '2026/10/18',
        'startedDate': '2026/10/18',
        'completedDate': '—',
        'plannedQuantity': 223.0,
        'producedQuantity': 223.0,
        'deliveredQuantity': 223.0,
        'consumedQuantity': 223.0,
        'custodyOnHand': 413.0,
      },
      additionalData: <String, dynamic>{
        'movements': <Map<String, dynamic>>[
          {
            'date': '2026/10/18 13:23',
            'movementType': 'صرف للأمر',
            'productName': 'قماش جيبيد',
            'quantity': 223.0,
            'reference': 'MO-TEST-1',
          },
          {
            'date': '2026/10/18 13:23',
            'movementType': 'تسليم للعميل',
            'productName': 'منتج اختبار',
            'quantity': 223.0,
            'reference': 'DN-2026-0002',
          },
        ],
        'balances': <Map<String, dynamic>>[
          {
            'productName': 'أزر',
            'quantityOnHand': 90.0,
            'quantityAllocated': 0.0,
            'colorSize': null,
          },
        ],
      },
    );

    final bytes = await pdf.save();
    expect(bytes.lengthInBytes, greaterThan(1000));
  });

  test('P2: card renders without any movements or balances', () async {
    final pdf = await UnifiedPrintService.generateUnifiedDocument(
      documentType: DocumentType.manufacturingCard,
      data: <String, dynamic>{
        'orderNumber': 'MO-TEST-2',
        'status': 'مخطط',
        'orderType': 'job',
        'plannedQuantity': 5.0,
        'producedQuantity': 0.0,
        'deliveredQuantity': 0.0,
        'consumedQuantity': 0.0,
        'custodyOnHand': 0.0,
      },
      additionalData: const <String, dynamic>{},
    );

    final bytes = await pdf.save();
    expect(bytes.lengthInBytes, greaterThan(1000));
  });
}
