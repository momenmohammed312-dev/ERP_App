import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../database/dao/enhanced_purchase_dao.dart';
import '../database/dao/purchase_dao.dart';
import 'invoice_number_formatter.dart';
import 'settings_service.dart';
import 'unified_print_service.dart' as ups;

class PurchasePrintService {
  final EnhancedPurchaseDao _purchaseDao;

  PurchasePrintService(AppDatabase database)
    : _purchaseDao = EnhancedPurchaseDao(database);

  Future<void> printPurchaseInvoice(int purchaseId) async {
    try {
      // Get purchase data
      final purchase = await _purchaseDao.getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('فاتورة المشتريات غير موجودة');
      }

      // Get purchase items
      final items = await _purchaseDao.getItemsByPurchase(purchaseId);

      // Get supplier info
      final supplier = await _purchaseDao.getSupplierById(purchase.supplierId);

      // Create simple print data
      final printData = _createPurchaseInvoiceData(purchase, supplier, items);

      // Print using thermal printer (simplified)
      await _printThermalPurchaseInvoice(printData);
    } catch (e) {
      throw Exception('خطأ في طباعة فاتورة المشتريات: $e');
    }
  }

  Future<void> printPurchaseReceipt(int purchaseId) async {
    try {
      // Get purchase data
      final purchase = await _purchaseDao.getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('فاتورة المشتريات غير موجودة');
      }

      // Get purchase items
      final items = await _purchaseDao.getItemsByPurchase(purchaseId);

      // Get supplier info
      final supplier = await _purchaseDao.getSupplierById(purchase.supplierId);

      // Create receipt data
      final receiptData = _createPurchaseReceiptData(purchase, supplier, items);

      // Print receipt
      await _printThermalPurchaseReceipt(receiptData);
    } catch (e) {
      throw Exception('خطأ في طباعة إيصال المشتريات: $e');
    }
  }

  /// Prints a TEXT-id supplier purchase (the live `purchases` table) via the
  /// same SOP thermal layout the purchase page uses. Shared by the create
  /// page and the purchase detail dialog so reprints look identical.
  Future<void> printTextPurchase({
    required AppDatabase db,
    required String purchaseId,
  }) async {
    final purchase = await (db.select(db.purchases)
          ..where((t) => t.id.equals(purchaseId)))
        .getSingleOrNull();
    if (purchase == null) throw Exception('فاتورة المشتريات غير موجودة');

    final pairs = await PurchaseDao(db).getItemsWithProductsByPurchase(
      purchaseId,
    );
    String supplierName = 'مورد غير محدد';
    String supplierPhone = '';
    if (purchase.supplierId != null) {
      final supplier = await db.supplierDao.getSupplierById(
        purchase.supplierId!,
      );
      if (supplier != null) {
        supplierName = supplier.name;
        supplierPhone = supplier.phone ?? '';
      }
    }

    final items = pairs
        .map(
          (pair) => ups.InvoiceItem(
            id: 0,
            invoiceId: 0,
            description: pair.$2?.name ?? 'منتج غير محدد',
            unit: pair.$1.unit,
            quantity: pair.$1.quantity,
            unitPrice: pair.$1.unitPrice,
            totalPrice: pair.$1.totalPrice,
          ),
        )
        .toList();

    final data = ups.InvoiceData(
      invoice: ups.Invoice(
        id: 0,
        invoiceNumber:
            displayInvoiceNumber(purchase.invoiceNumber, null) ?? '',
        customerName: supplierName,
        customerPhone: supplierPhone,
        customerZipCode: '',
        customerState: '',
        invoiceDate: purchase.purchaseDate,
        subtotal: purchase.totalAmount,
        isCreditAccount: purchase.paymentMethod != 'cash',
        previousBalance: 0.0,
        totalAmount: purchase.totalAmount,
      ),
      items: items,
      storeInfo: ups.StoreInfo(
        storeName: await SettingsService.getBusinessName(),
        phone: await SettingsService.getBusinessPhone(),
        zipCode: '',
        state: await SettingsService.getBusinessAddress(),
        taxNumber: await SettingsService.getTaxNumber(),
        logoPath: await SettingsService.getBusinessLogoPath(),
      ),
    );

    await ups.UnifiedPrintService.printToThermalPrinter(
      documentType: ups.DocumentType.salesInvoice, // Reuse for now
      data: data,
    );
  }

  Map<String, dynamic> _createPurchaseInvoiceData(
    EnhancedPurchase purchase,
    EnhancedSupplier? supplier,
    List<EnhancedPurchaseItem> items,
  ) {
    return {
      'type': 'purchase_invoice',
      'invoiceNumber': purchase.purchaseNumber,
      'invoiceDate': _formatDate(purchase.purchaseDate),
      'supplierName': supplier?.businessName ?? 'غير محدد',
      'supplierPhone': supplier?.phone ?? '',
      'supplierAddress': supplier?.address ?? '',
      'subtotal': purchase.subtotal,
      'tax': purchase.tax,
      'discount': purchase.discount,
      'totalAmount': purchase.totalAmount,
      'paidAmount': purchase.paidAmount,
      'remainingAmount': purchase.remainingAmount,
      'paymentMethod': purchase.paymentMethod,
      'purchaseType': purchase.isCreditPurchase ? 'آجل' : 'نقدي',
      'notes': purchase.notes ?? '',
      'branding': 'Developed by MO2',
      'items': items
          .map(
            (item) => {
              'name': item.productName,
              'quantity': item.quantity,
              'unit': item.unit,
              'unitPrice': item.unitPrice,
              'totalPrice': item.totalPrice,
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> _createPurchaseReceiptData(
    EnhancedPurchase purchase,
    EnhancedSupplier? supplier,
    List<EnhancedPurchaseItem> items,
  ) {
    return {
      'type': 'purchase_receipt',
      'receiptNumber': purchase.purchaseNumber,
      'receiptDate': _formatDate(purchase.purchaseDate),
      'supplierName': supplier?.businessName ?? 'غير محدد',
      'supplierPhone': supplier?.phone ?? '',
      'totalAmount': purchase.totalAmount,
      'paidAmount': purchase.paidAmount,
      'remainingAmount': purchase.remainingAmount,
      'paymentMethod': purchase.paymentMethod,
      'receiptType': 'إيصال استلام',
      'branding': 'Developed by MO2',
      'items': items
          .map(
            (item) => {
              'name': item.productName,
              'quantity': item.quantity,
              'unit': item.unit,
              'unitPrice': item.unitPrice,
              'totalPrice': item.totalPrice,
            },
          )
          .toList(),
    };
  }

  Future<void> _printThermalPurchaseInvoice(Map<String, dynamic> data) async {
    // Simplified thermal printing for purchase invoices
    final lines = <String>[];

    lines.add('=====================================');
    lines.add('     فاتورة توريد');
    lines.add('=====================================');
    lines.add('');
    lines.add('رقم الفاتورة: ${data['invoiceNumber']}');
    lines.add('التاريخ: ${data['invoiceDate']}');
    lines.add('المورد: ${data['supplierName']}');
    lines.add('الهاتف: ${data['supplierPhone']}');
    lines.add('');
    lines.add('------------------------------------');

    // Items
    lines.add('البنود:');
    lines.add('------------------------------------');
    for (final item in data['items']) {
      lines.add('${item['name']}');
      lines.add('  الكمية: ${item['quantity']} ${item['unit']}');
      lines.add('  السعر: ${item['unitPrice']} ج.م');
      lines.add('  الإجمالي: ${item['totalPrice']} ج.م');
      lines.add('');
    }

    lines.add('------------------------------------');
    lines.add('الإجمالي الفرعي: ${data['subtotal'].toStringAsFixed(2)} ج.م');
    lines.add('الضريبة: ${data['tax'].toStringAsFixed(2)} ج.م');
    lines.add('خصم: ${data['discount'].toStringAsFixed(2)} ج.م');
    lines.add('الإجمالي الكلي: ${data['totalAmount'].toStringAsFixed(2)} ج.م');
    lines.add('المدفوع: ${data['paidAmount'].toStringAsFixed(2)} ج.م');
    lines.add('المتبقي: ${data['remainingAmount'].toStringAsFixed(2)} ج.م');
    lines.add('طريقة الدفع: ${data['paymentMethod']}');
    lines.add('النوع: ${data['purchaseType']}');
    lines.add('');

    if (data['notes'] != null && data['notes'].isNotEmpty) {
      lines.add('ملاحظات: ${data['notes']}');
      lines.add('');
    }

    lines.add('=====================================');
    lines.add('Developed by MO2');
    lines.add('=====================================');

    // Here you would integrate with actual thermal printer
    // For now, just show the content in a dialog
    _showPrintDialog(lines.join('\n'));
  }

  Future<void> _printThermalPurchaseReceipt(Map<String, dynamic> data) async {
    // Simplified receipt printing
    final lines = <String>[];

    lines.add('=====================================');
    lines.add('        إيصال استلام');
    lines.add('=====================================');
    lines.add('');
    lines.add('رقم الإيصال: ${data['receiptNumber']}');
    lines.add('التاريخ: ${data['receiptDate']}');
    lines.add('المورد: ${data['supplierName']}');
    lines.add('');
    lines.add('------------------------------------');

    // Items
    for (final item in data['items']) {
      lines.add('${item['name']} x${item['quantity']}');
      lines.add('  ${item['totalPrice'].toStringAsFixed(2)} ج.م');
    }

    lines.add('------------------------------------');
    lines.add('الإجمالي: ${data['totalAmount'].toStringAsFixed(2)} ج.ม');
    lines.add('المدفوع: ${data['paidAmount'].toStringAsFixed(2)} ج.م');
    lines.add('المتبقي: ${data['remainingAmount'].toStringAsFixed(2)} ج.م');
    lines.add('');
    lines.add('=====================================');
    lines.add('Developed by MO2');
    lines.add('=====================================');

    // Show in dialog
    _showPrintDialog(lines.join('\n'));
  }

  void _showPrintDialog(String content) {
    // This would integrate with actual printer
    // For now, just show the content
    debugPrint('=== PRINT CONTENT ===');
    debugPrint(content);
    debugPrint('====================');
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateShort(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> printPurchaseReport({
    DateTime? startDate,
    DateTime? endDate,
    String? supplierId,
  }) async {
    try {
      // Get filtered purchases
      List<EnhancedPurchase> purchases;
      if (supplierId != null) {
        purchases = await _purchaseDao.getPurchasesBySupplier(
          int.parse(supplierId),
        );
      } else {
        purchases = await _purchaseDao.getAllPurchases();
      }

      // Filter by date range if provided
      if (startDate != null && endDate != null) {
        purchases = purchases.where((purchase) {
          return purchase.purchaseDate.isAfter(
                startDate.subtract(Duration(days: 1)),
              ) &&
              purchase.purchaseDate.isBefore(endDate.add(Duration(days: 1)));
        }).toList();
      }

      // Calculate totals
      final totalPurchases = purchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );
      final creditPurchases = purchases
          .where((p) => p.isCreditPurchase)
          .fold(0.0, (sum, p) => sum + p.totalAmount);
      final cashPurchases = purchases
          .where((p) => !p.isCreditPurchase)
          .fold(0.0, (sum, p) => sum + p.totalAmount);

      // Create report content
      final lines = <String>[];
      lines.add('=====================================');
      lines.add('     تقرير المشتريات');
      lines.add('=====================================');
      lines.add('');
      lines.add(
        'الفترة: ${startDate != null ? _formatDateShort(startDate) : 'البدء'} - ${endDate != null ? _formatDateShort(endDate) : 'الآن'}',
      );
      lines.add('');
      lines.add('إجمالي المشتريات: ${totalPurchases.toStringAsFixed(2)} ج.م');
      lines.add('مشتريات آجلة: ${creditPurchases.toStringAsFixed(2)} ج.م');
      lines.add('مشتريات نقدية: ${cashPurchases.toStringAsFixed(2)} ج.م');
      lines.add('عدد الفواتير: ${purchases.length}');
      lines.add('');
      lines.add('------------------------------------');
      lines.add('تفاصيل الفواتير:');
      lines.add('------------------------------------');

      for (final purchase in purchases) {
        lines.add('${purchase.purchaseNumber} - ${purchase.supplierName}');
        lines.add('  التاريخ: ${_formatDateShort(purchase.purchaseDate)}');
        lines.add('  المبلغ: ${purchase.totalAmount.toStringAsFixed(2)} ج.م');
        lines.add('  النوع: ${purchase.isCreditPurchase ? 'آجل' : 'نقدي'}');
        lines.add(
          '  الحالة: ${purchase.remainingAmount > 0 ? 'متبقي' : 'مدفوع'}',
        );
        lines.add('');
      }

      lines.add('=====================================');
      lines.add('Developed by MO2');
      lines.add('=====================================');

      // Show in dialog
      _showPrintDialog(lines.join('\n'));
    } catch (e) {
      throw Exception('خطأ في طباعة تقرير المشتريات: $e');
    }
  }

  Future<void> printSupplierStatement(int supplierId) async {
    try {
      // Get supplier data
      final supplier = await _purchaseDao.getSupplierById(supplierId);
      if (supplier == null) {
        throw Exception('المورد غير موجود');
      }

      // Get supplier purchases and payments
      final purchases = await _purchaseDao.getPurchasesBySupplier(supplierId);
      final payments = await _purchaseDao.getPaymentsBySupplier(supplierId);

      // Calculate totals
      final totalPurchases = purchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );
      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
      final remainingBalance = totalPurchases - totalPaid;

      // Create statement content
      final lines = <String>[];
      lines.add('=====================================');
      lines.add('     كشف حساب المورد');
      lines.add('=====================================');
      lines.add('');
      lines.add('المورد: ${supplier.businessName}');
      lines.add('الهاتف: ${supplier.phone}');
      lines.add('العنوان: ${supplier.address ?? 'غير محدد'}');
      lines.add('');
      lines.add('الرصيد الحالي: ${remainingBalance.toStringAsFixed(2)} ج.م');
      lines.add('');
      lines.add('------------------------------------');
      lines.add('المعاملات:');
      lines.add('------------------------------------');

      // Add purchases
      for (final purchase in purchases) {
        lines.add(
          '${purchase.purchaseNumber} - ${_formatDateShort(purchase.purchaseDate)}',
        );
        lines.add(
          '  فاتورة شراء: ${purchase.totalAmount.toStringAsFixed(2)} ج.م',
        );
      }

      // Add payments
      for (final payment in payments) {
        lines.add(
          '${payment.paymentNumber} - ${_formatDateShort(payment.paymentDate)}',
        );
        lines.add('  دفعة: ${payment.amount.toStringAsFixed(2)} ج.م');
      }

      lines.add('------------------------------------');
      lines.add('إجمالي المشتريات: ${totalPurchases.toStringAsFixed(2)} ج.م');
      lines.add('إجمالي المدفوعات: ${totalPaid.toStringAsFixed(2)} ج.م');
      lines.add('الرصيد النهائي: ${remainingBalance.toStringAsFixed(2)} ج.م');
      lines.add('');
      lines.add('=====================================');
      lines.add('Developed by MO2');
      lines.add('=====================================');

      // Show in dialog
      _showPrintDialog(lines.join('\n'));
    } catch (e) {
      throw Exception('خطأ في طباعة كشف حساب المورد: $e');
    }
  }

  Future<void> printSupplierList() async {
    try {
      // Get all suppliers
      final suppliers = await _purchaseDao.getAllSuppliers();

      // Create list content
      final lines = <String>[];
      lines.add('=====================================');
      lines.add('     قائمة الموردين');
      lines.add('=====================================');
      lines.add('');

      for (final supplier in suppliers) {
        lines.add(supplier.businessName);
        lines.add('  الهاتف: ${supplier.phone}');
        lines.add('  العنوان: ${supplier.address ?? 'غير محدد'}');
        lines.add(
          '  الرصيد: ${supplier.currentBalance.toStringAsFixed(2)} ج.م',
        );
        lines.add('  الحالة: ${supplier.currentBalance > 0 ? 'دين' : 'رصيد'}');
        lines.add('');
      }

      lines.add('=====================================');
      lines.add('إجمالي الموردين: ${suppliers.length}');
      lines.add(
        'إجمالي الديون: ${suppliers.where((s) => s.currentBalance > 0).fold(0.0, (sum, s) => sum + s.currentBalance).toStringAsFixed(2)} ج.م',
      );
      lines.add(
        'إجمالي الأرصدة: ${suppliers.where((s) => s.currentBalance <= 0).fold(0.0, (sum, s) => sum + s.currentBalance.abs()).toStringAsFixed(2)} ج.م',
      );
      lines.add('');
      lines.add('=====================================');
      lines.add('Developed by MO2');
      lines.add('=====================================');

      // Show in dialog
      _showPrintDialog(lines.join('\n'));
    } catch (e) {
      throw Exception('خطأ في طباعة قائمة الموردين: $e');
    }
  }
}
