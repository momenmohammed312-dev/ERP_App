import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/empty_barnika_tracking_table.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/shipment_settlement_service.dart';

/// خدمة تصدير تقارير سوق الخضار الشاملة إلى ملف إكسل `.xlsx` (4 أوراق عمل):
/// 1. كشوف الشحنات (المبيعات، العمولة، مصروفات الشحنة، صافي المورد، المدفوع، المتبقي)
/// 2. مديونيات الزباين وأرصدة البرانيك
/// 3. أرصدة البرانيك الفارغة التفصيلية
/// 4. المصروفات (مقسمة بين مصروف شحنة ومصروف محل)
class VegetableExcelExportService {
  final AppDatabase _db;
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');

  VegetableExcelExportService(this._db);

  Future<Uint8List> buildWorkbookBytes({
    DateTime? from,
    DateTime? to,
  }) async {
    final excel = Excel.createExcel();
    final start = from != null ? DateTime(from.year, from.month, from.day) : null;
    final end = to != null
        ? DateTime(to.year, to.month, to.day, 23, 59, 59, 999)
        : null;

    final suppliers = await _db.supplierDao.getAllSuppliers();
    final supplierById = {for (final s in suppliers) s.id: s};

    final customers = await _db.customerDao.getAllCustomers();
    final customerById = {for (final c in customers) c.id: c};

    final shipments = await _db.vegetableShipmentDao.getAll();
    final shipmentById = {for (final s in shipments) s.id: s};

    // 1. كشوف الشحنات
    final settlementService = ShipmentSettlementService(_db);
    final shipmentsSheet = excel['كشوف الشحنات'];
    shipmentsSheet.appendRow([
      TextCellValue('رقم الشحنة'),
      TextCellValue('التاريخ'),
      TextCellValue('المورد'),
      TextCellValue('الحالة'),
      TextCellValue('المستلم (برنيكة)'),
      TextCellValue('المباع'),
      TextCellValue('التكميل'),
      TextCellValue('المتبقي'),
      TextCellValue('إجمالي المبيعات'),
      TextCellValue('نسبة العمولة %'),
      TextCellValue('عمولة المحل'),
      TextCellValue('مصروفات الشحنة (النولون)'),
      TextCellValue('صافي مستحق المورد'),
      TextCellValue('المدفوع للمورد'),
      TextCellValue('المتبقي للمورد'),
    ]);

    for (final s in shipments) {
      if (start != null && s.date.isBefore(start)) continue;
      if (end != null && s.date.isAfter(end)) continue;

      final st = await settlementService.getShipmentStatement(s.id);
      shipmentsSheet.appendRow([
        TextCellValue('#${s.shipmentNumber}'),
        TextCellValue(_dateFmt.format(s.date)),
        TextCellValue(
          st.supplier?.name ?? supplierById[s.supplierId]?.name ?? 'مورد غير محدد',
        ),
        TextCellValue(
          s.status == VegetableShipmentStatus.closed ? 'مقفولة' : 'مفتوحة',
        ),
        IntCellValue(s.totalBarnikaCount),
        IntCellValue(s.barnikaSoldCount),
        IntCellValue(s.toppingCount),
        IntCellValue(st.remainingCount),
        DoubleCellValue(st.totalSales),
        DoubleCellValue(s.commissionPercentage ?? 0.0),
        DoubleCellValue(st.commissionAmount),
        DoubleCellValue(st.shipmentExpenses),
        DoubleCellValue(st.netSupplierDue),
        DoubleCellValue(st.paidForShipment),
        DoubleCellValue(st.remainingForShipment),
      ]);
    }

    // 2. مديونيات الزباين
    final debtSheet = excel['مديونيات الزباين'];
    debtSheet.appendRow([
      TextCellValue('اسم الزبون'),
      TextCellValue('الهاتف'),
      TextCellValue('العنوان'),
      TextCellValue('الرصيد الافتتاحي (آجل)'),
      TextCellValue('صافي المديونية الحالية (ج.م)'),
      TextCellValue('عهدة البرانيك الفارغة'),
    ]);

    final balances = await _db.ledgerDao.getAllCustomerBalances();
    for (final row in balances) {
      final id = row['id'] as String;
      final name = row['name'] as String;
      final phone = (row['phone'] as String?) ?? '';
      final balance = (row['balance'] as num?)?.toDouble() ?? 0.0;
      final barnikaBal = await _db.emptyBarnikaTrackingDao
          .getCustomerOutstandingBalance(id);
      if (balance.abs() <= 0.005 && barnikaBal == 0) continue;

      final cust = customerById[id];
      debtSheet.appendRow([
        TextCellValue(name),
        TextCellValue(phone),
        TextCellValue(cust?.address ?? ''),
        DoubleCellValue(cust?.openingBalance ?? 0.0),
        DoubleCellValue(balance),
        IntCellValue(barnikaBal),
      ]);
    }

    // 3. أرصدة البرانيك الفارغة
    final barnikaSheet = excel['أرصدة البرانيك الفارغة'];
    barnikaSheet.appendRow([
      TextCellValue('الزبون'),
      TextCellValue('الهاتف'),
      TextCellValue('تاريخ الخروج'),
      TextCellValue('رقم الفاتورة'),
      TextCellValue('البرانيك الخارجة'),
      TextCellValue('المستلمة'),
      TextCellValue('المتبقي في العهدة'),
      TextCellValue('الحالة'),
    ]);

    final outstandingBarnikas =
        await _db.emptyBarnikaTrackingDao.watchAllOutstanding().first;
    final invoices = await _db.select(_db.invoices).get();
    final invoiceById = {for (final inv in invoices) inv.id: inv};

    for (final eb in outstandingBarnikas) {
      if (start != null && eb.dateOut.isBefore(start)) continue;
      if (end != null && eb.dateOut.isAfter(end)) continue;

      final cust = customerById[eb.customerId];
      final inv = eb.invoiceId != null ? invoiceById[eb.invoiceId!] : null;
      final invDisplay = eb.invoiceId == null
          ? 'رصيد افتتاحي / يدوي'
          : (displayInvoiceNumber(inv?.invoiceNumber, eb.invoiceId!) ??
              '#${eb.invoiceId}');
      final remaining = eb.quantityOut - eb.quantityReturned;

      barnikaSheet.appendRow([
        TextCellValue(cust?.name ?? eb.customerId),
        TextCellValue(cust?.phone ?? ''),
        TextCellValue(_dateFmt.format(eb.dateOut)),
        TextCellValue(invDisplay),
        IntCellValue(eb.quantityOut),
        IntCellValue(eb.quantityReturned),
        IntCellValue(remaining < 0 ? 0 : remaining),
        TextCellValue(
          eb.status == EmptyBarnikaStatus.partial ? 'مرتجع جزئي' : 'خارج / مستحق',
        ),
      ]);
    }

    // 4. المصروفات
    final expensesSheet = excel['المصروفات'];
    expensesSheet.appendRow([
      TextCellValue('التاريخ'),
      TextCellValue('النوع'),
      TextCellValue('رقم الشحنة'),
      TextCellValue('المورد'),
      TextCellValue('الفئة'),
      TextCellValue('البيان'),
      TextCellValue('المبلغ'),
      TextCellValue('طريقة الدفع'),
      TextCellValue('ملاحظات'),
    ]);

    final expenses = await _db.expenseDao.getAllExpenses();
    for (final e in expenses) {
      if (start != null && e.date.isBefore(start)) continue;
      if (end != null && e.date.isAfter(end)) continue;

      final shp = e.shipmentId != null ? shipmentById[e.shipmentId!] : null;
      final supName = shp != null ? (supplierById[shp.supplierId]?.name ?? '') : '';

      expensesSheet.appendRow([
        TextCellValue(_dateFmt.format(e.date)),
        TextCellValue(
          e.scope == ExpenseScope.shipment ? 'مصروف شحنة' : 'مصروف محل',
        ),
        TextCellValue(shp != null ? '#${shp.shipmentNumber}' : ''),
        TextCellValue(supName),
        TextCellValue(e.category),
        TextCellValue(e.description),
        DoubleCellValue(e.amount),
        TextCellValue(e.paymentMethod),
        TextCellValue(e.notes ?? ''),
      ]);
    }

    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    excel.setDefaultSheet('كشوف الشحنات');

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('تعذر إنشاء ملف التصدير');
    }
    return Uint8List.fromList(encoded);
  }

  Future<String> saveWorkbookToDocuments({
    DateTime? from,
    DateTime? to,
    String? customDirectoryPath,
  }) async {
    final bytes = await buildWorkbookBytes(from: from, to: to);
    final dirPath =
        customDirectoryPath ?? (await getApplicationDocumentsDirectory()).path;
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filePath = path.join(dirPath, 'تقرير_سوق_الخضار_$stamp.xlsx');
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  Future<String> exportAndShareWorkbook({
    DateTime? from,
    DateTime? to,
  }) async {
    final filePath = await saveWorkbookToDocuments(from: from, to: to);
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'تقارير سوق الخضار - مدار',
    );
    return filePath;
  }
}
