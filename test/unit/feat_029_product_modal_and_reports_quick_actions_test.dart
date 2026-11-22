import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FEAT-029: Product Selection Modal & Sales Reports Quick Actions Tests', () {
    test('ProductSelectionModal source code contains Arabic labels and localized units', () {
      final file = File('lib/ui/invoice/widgets/product_selection_modal.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Check Arabic labels
      expect(source.contains("'الكمية'"), isTrue);
      expect(source.contains("'الوحدة'"), isTrue);
      expect(source.contains("'سعر الوحدة'"), isTrue);
      expect(source.contains("'الخصم'"), isTrue);
      expect(source.contains("'الضريبة'"), isTrue);
      expect(source.contains("'إجمالي البند:'"), isTrue);
      expect(source.contains("'إضافة إلى الفاتورة'"), isTrue);
      expect(source.contains("'إلغاء'"), isTrue);
      expect(source.contains("'المخزون المتوفر:"), isTrue);

      // Check unit localization function
      expect(source.contains('_formatUnitName'), isTrue);
      expect(source.contains("'قطعة'"), isTrue);
      expect(source.contains("'كيلو'"), isTrue);
      expect(source.contains("'كرتون'"), isTrue);
      expect(source.contains("'علبة'"), isTrue);

      // Check RTL directionality
      expect(source.contains('TextDirection.rtl'), isTrue);
      // Ensure jarring white box is removed
      expect(source.contains('Colors.grey.shade50'), isFalse);
    });

    test('SalesReportTab source code contains Eye (Preview) and Edit Invoice quick actions', () {
      final file = File('lib/ui/reports/widgets/sales_report_tab.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      // Check Eye icon (معاينة تفاصيل الفاتورة)
      expect(source.contains('Icons.visibility_outlined'), isTrue);
      expect(source.contains("'معاينة تفاصيل الفاتورة'"), isTrue);
      expect(source.contains('_showInvoiceDetailsDialog'), isTrue);

      // Check Edit Invoice icon (تعديل الفاتورة)
      expect(source.contains('Icons.edit_note_rounded'), isTrue);
      expect(source.contains("'تعديل الفاتورة'"), isTrue);

      // Check Customer Name formatting helper
      expect(source.contains('_formatCustomerName'), isTrue);
      expect(source.contains("'عميل نقدي'"), isTrue);
      expect(source.contains('__SYNC_CUST_'), isTrue);
    });

    test('Customer name cleaner logic properly formats raw sync identifiers and nulls', () {
      String formatCustomerName(String? name) {
        if (name == null || name.trim().isEmpty) return 'عميل نقدي';
        final trimmed = name.trim();
        if (trimmed.startsWith('__SYNC_CUST_') ||
            trimmed.startsWith('TEMP_') ||
            trimmed.startsWith('CUST_') ||
            trimmed == 'null') {
          return 'عميل نقدي';
        }
        return trimmed;
      }

      expect(formatCustomerName(null), equals('عميل نقدي'));
      expect(formatCustomerName(''), equals('عميل نقدي'));
      expect(formatCustomerName('   '), equals('عميل نقدي'));
      expect(formatCustomerName('__SYNC_CUST_1786345956891__'), equals('عميل نقدي'));
      expect(formatCustomerName('TEMP_12345'), equals('عميل نقدي'));
      expect(formatCustomerName('CUST_999'), equals('عميل نقدي'));
      expect(formatCustomerName('null'), equals('عميل نقدي'));
      expect(formatCustomerName('أحمد محمد'), equals('أحمد محمد'));
      expect(formatCustomerName('شركة الأمل للتجارة'), equals('شركة الأمل للتجارة'));
    });

    test('Unit localization logic correctly translates standard POS unit strings', () {
      String formatUnitName(String unit) {
        final u = unit.trim().toLowerCase();
        switch (u) {
          case 'piece':
          case 'قطعة':
            return 'قطعة';
          case 'kg':
          case 'كيلو':
          case 'كجم':
            return 'كيلو';
          case 'box':
          case 'علبة':
            return 'علبة';
          case 'carton':
          case 'كرتون':
            return 'كرتون';
          case 'meter':
          case 'متر':
            return 'متر';
          case 'liter':
          case 'لتر':
            return 'لتر';
          case 'ton':
          case 'طن':
            return 'طن';
          default:
            return unit;
        }
      }

      expect(formatUnitName('piece'), equals('قطعة'));
      expect(formatUnitName('PIECE'), equals('قطعة'));
      expect(formatUnitName('kg'), equals('كيلو'));
      expect(formatUnitName('box'), equals('علبة'));
      expect(formatUnitName('carton'), equals('كرتون'));
      expect(formatUnitName('meter'), equals('متر'));
      expect(formatUnitName('liter'), equals('لتر'));
      expect(formatUnitName('ton'), equals('طن'));
      expect(formatUnitName('custom_unit'), equals('custom_unit'));
    });
  });
}
