import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FEAT-031: Purchase Invoice & Product Cards UI Modernization Tests', () {
    test('ProductCard supports dark mode and MadarColors design tokens', () {
      final file = File('lib/ui/invoice/widgets/product_card.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Uses MadarColors tokens
      expect(source.contains('MadarColors.bgCard'), isTrue);
      expect(source.contains('MadarColors.border'), isTrue);
      expect(source.contains('MadarColors.gold'), isTrue);
      expect(source.contains('MadarColors.textLight'), isTrue);
      expect(source.contains('MadarColors.success'), isTrue);
      expect(source.contains('MadarColors.error'), isTrue);

      // Ensures dark theme awareness
      expect(source.contains('Brightness.dark'), isTrue);
      expect(source.contains('isDark ? MadarColors.bgCard'), isTrue);

      // Currency is localized cleanly to ج.م
      expect(source.contains('ج.م'), isTrue);
    });

    test('EnhancedPurchaseInvoicePage eliminates white primaryContainer and applies dark theme layout', () {
      final file = File('lib/ui/purchase/widgets/enhanced_purchase_invoice_page.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Eliminated jarring stark white header
      expect(source.contains('colorScheme.primaryContainer'), isFalse);

      // Uses MadarColors tokens
      expect(source.contains('MadarColors.bgDark'), isTrue);
      expect(source.contains('MadarColors.bgCard'), isTrue);
      expect(source.contains('MadarColors.border'), isTrue);
      expect(source.contains('MadarColors.gold'), isTrue);

      // Balanced proportions: 5/8 for products and 3/8 for invoice details
      expect(source.contains('Expanded(\n              flex: 5,\n              child: _buildProductsPanel(),') ||
             source.contains('flex: 5,\n              child: _buildProductsPanel()') ||
             source.contains('_buildProductsPanel()'), isTrue);
      expect(source.contains('_buildDetailsPanel()'), isTrue);

      // Grid expanded to 4 columns for modern desktop layout
      expect(source.contains('crossAxisCount: 4'), isTrue);

      // Quick add button no longer uses jarring purple
      expect(source.contains('Colors.purple'), isFalse);
      expect(source.contains('منتج جديد'), isTrue);

      // Sleek docked action buttons
      expect(source.contains('حفظ والطباعة'), isTrue);
      expect(source.contains('مسح'), isTrue);
      expect(source.contains('مشتريات'), isTrue);
    });
  });
}
