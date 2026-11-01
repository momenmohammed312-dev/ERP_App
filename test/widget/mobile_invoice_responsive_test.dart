import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/ui/invoice/models/invoice_models.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/invoice_type_selection_modal.dart';

void main() {
  group('InvoiceTypeSelectionModal Responsive Tests', () {
    testWidgets('renders on mobile screen (360x780) without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      InvoiceType? selectedType;

      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceTypeSelectionModal(
            onSelectType: (type) => selectedType = type,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and description
      expect(find.text('اختر نوع الفاتورة'), findsOneWidget);
      expect(find.text('نوع الفاتورة'), findsOneWidget);

      // Check mobile option cards
      expect(find.text('نقدي (كاش)'), findsOneWidget);
      expect(find.text('آجل (على الحساب)'), findsOneWidget);
      expect(find.text('توريد (شراء)'), findsOneWidget);

      // Tap cash option
      await tester.tap(find.text('نقدي (كاش)'));
      await tester.pump();
      expect(selectedType, equals(InvoiceType.cash));
    });

    testWidgets('renders on desktop screen (1280x800) with desktop cards',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      InvoiceType? selectedType;

      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceTypeSelectionModal(
            onSelectType: (type) => selectedType = type,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check desktop option cards
      expect(find.text('نقدي'), findsOneWidget);
      expect(find.text('آجل'), findsOneWidget);
      expect(find.text('توريد'), findsOneWidget);

      // Tap credit option
      await tester.tap(find.text('آجل'));
      await tester.pump();
      expect(selectedType, equals(InvoiceType.credit));
    });
  });
}
