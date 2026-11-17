import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_settlement_service.dart';
import 'package:pos_offline_desktop/core/services/vegetable_excel_export_service.dart';
import 'package:pos_offline_desktop/core/services/vegetable_market_import_service.dart';

Uint8List _buildTestOpeningBalanceWorkbook() {
  final excel = Excel.createExcel();

  final cust = excel['العملاء'];
  cust.appendRow([
    TextCellValue('الاسم'),
    TextCellValue('الهاتف'),
    TextCellValue('العنوان'),
    TextCellValue('رصيد الآجل الافتتاحي'),
    TextCellValue('رصيد البرانيك الفارغة'),
    TextCellValue('ملاحظات'),
  ]);
  cust.appendRow([
    TextCellValue('أحمد الإسكندراني'),
    TextCellValue('01001112222'),
    TextCellValue('وكالة الخضار'),
    DoubleCellValue(2500.0),
    IntCellValue(15),
    TextCellValue('جملة'),
  ]);
  // Normalized Arabic duplicate of above row (should be detected & skipped)
  cust.appendRow([
    TextCellValue('احمد الاسكندرانى'),
    TextCellValue('01099998888'),
    TextCellValue('مكرر'),
    DoubleCellValue(900.0),
    IntCellValue(5),
    TextCellValue(''),
  ]);
  // Matches pre-seeded DB customer "إبراهيم محمود" without hamza
  cust.appendRow([
    TextCellValue('ابراهيم محمود'),
    TextCellValue('01200001111'),
    TextCellValue('شبرا'),
    DoubleCellValue(300.0),
    IntCellValue(2),
    TextCellValue(''),
  ]);

  final sup = excel['الموردين'];
  sup.appendRow([
    TextCellValue('الاسم'),
    TextCellValue('الهاتف'),
    TextCellValue('العنوان'),
    TextCellValue('الرصيد الافتتاحي'),
  ]);
  sup.appendRow([
    TextCellValue('مزارع البركة'),
    TextCellValue('01112223333'),
    TextCellValue('الإسماعيلية'),
    DoubleCellValue(7500.0),
  ]);
  // Duplicate by normalized name (ال prefix + ة/ه equivalence)
  sup.appendRow([
    TextCellValue('مزارع بركه'),
    TextCellValue('01119990000'),
    TextCellValue(''),
    DoubleCellValue(1000.0),
  ]);

  if (excel.tables.containsKey('Sheet1')) {
    excel.delete('Sheet1');
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase E — Excel Opening Balance Import & Comprehensive Export', () {
    test('generateOpeningBalanceTemplateBytes creates valid Arabic .xlsx sheets', () {
      final bytes = VegetableMarketImportService.generateOpeningBalanceTemplateBytes();
      final decoded = Excel.decodeBytes(bytes);

      expect(decoded.tables.keys, contains('العملاء'));
      expect(decoded.tables.keys, contains('الموردين'));
      expect(decoded.tables.keys.contains('Sheet1'), isFalse);

      final custHeaders = decoded.tables['العملاء']!.rows.first
          .map((c) => c?.value.toString())
          .toList();
      expect(
        custHeaders,
        containsAll(['الاسم', 'الهاتف', 'العنوان', 'رصيد الآجل الافتتاحي', 'رصيد البرانيك الفارغة']),
      );

      final supHeaders = decoded.tables['الموردين']!.rows.first
          .map((c) => c?.value.toString())
          .toList();
      expect(
        supHeaders,
        containsAll(['الاسم', 'الهاتف', 'العنوان', 'الرصيد الافتتاحي']),
      );
    });

    test('previewExcelBytes & importFromFile(.xlsx) import opening balances and skip Arabic duplicates', () async {
      await db.customerDao.insertCustomer(
        CustomersCompanion.insert(
          id: 'SEED-CUST',
          name: 'إبراهيم محمود',
        ),
      );

      final bytes = _buildTestOpeningBalanceWorkbook();
      final service = VegetableMarketImportService(db);

      final preview = await service.previewExcelBytes(bytes);
      expect(preview.customers.length, 3);
      expect(preview.suppliers.length, 2);
      expect(preview.duplicateWarnings.length, 3);

      // Write to temp .xlsx and exercise importFromFile (verifies JSON-decode bug fix)
      final tempDir = await Directory.systemTemp.createTemp('veg_excel_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final xlsxFile = File('${tempDir.path}/opening.xlsx');
      await xlsxFile.writeAsBytes(bytes, flush: true);

      final result = await service.importFromFile(xlsxFile.path);
      expect(result.errors, isEmpty);
      expect(result.customers, 1);
      expect(result.suppliers, 1);
      expect(result.emptyBarnika, 1);
      expect(result.skippedDuplicates, 3);

      final allCust = await db.customerDao.getAllCustomers();
      expect(allCust.length, 2); // SEED-CUST + أحمد الإسكندراني
      final importedCust = allCust.firstWhere((c) => c.name == 'أحمد الإسكندراني');
      expect(importedCust.openingBalance, closeTo(2500.0, 0.01));
      expect(
        await db.ledgerDao.getCustomerBalance(importedCust.id),
        closeTo(2500.0, 0.01),
      );
      expect(
        await db.emptyBarnikaTrackingDao.getCustomerOutstandingBalance(importedCust.id),
        15,
      );

      final allSup = await db.supplierDao.getAllSuppliers();
      expect(allSup.length, 1);
      expect(allSup.first.name, 'مزارع البركة');
      expect(allSup.first.openingBalance, closeTo(7500.0, 0.01));
      expect(
        await db.ledgerDao.getSupplierBalance(allSup.first.id),
        closeTo(7500.0, 0.01),
      );
    });

    test('VegetableExcelExportService exports all 4 Arabic sheets with accurate settlement, debts, barnikas & expenses', () async {
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'SUP-E',
              name: 'مزارع البحيرة',
              phone: const Value('01055556666'),
            ),
          );
      await db.customerDao.insertCustomer(
        CustomersCompanion.insert(
          id: 'CUST-E',
          name: 'الحاج سعيد',
          phone: const Value('01233334444'),
          openingBalance: const Value(200.0),
        ),
      );

      final prodId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'بارنيكة طماطم',
          quantity: 50,
          price: 0.0,
          barneka: const Value(true),
        ),
      );

      final shpId = await db.vegetableShipmentDao.insertShipment(
        VegetableShipmentsCompanion.insert(
          supplierId: 'SUP-E',
          shipmentNumber: 'EXP-100',
          pricingMode: ShipmentPricingMode.commission,
          totalBarnikaCount: 20,
          totalCost: 0.0,
          barnikaRemainingCount: 20,
          toppingCount: const Value(2),
          commissionPercentage: const Value(10.0),
        ),
      );

      // Sale: 5 crates * 200 = 1000 EGP, paid 400 EGP, credit 600 EGP, 5 barnikas out, 2 returned
      await InvoiceService(db).createInvoice(
        customerId: 'CUST-E',
        customerName: 'الحاج سعيد',
        paymentMethod: 'mixed',
        totalAmount: 1000.0,
        paidAmount: 400.0,
        cashAmount: 400.0,
        creditAmount: 600.0,
        status: 'partial',
        primaryShipmentId: shpId,
        emptyBarnikaOutCount: 5,
        emptyBarnikaReturnedCount: 2,
        items: [
          InvoiceItemParams(
            productId: prodId,
            quantity: 5,
            price: 200.0,
            shipmentId: shpId,
          ),
        ],
      );

      // Shipment expense (100) + shop expense (50)
      await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          id: 'EXP-SHP-1',
          description: 'نولون العربية',
          amount: 100.0,
          category: 'نولون / شحن',
          scope: const Value(ExpenseScope.shipment),
          shipmentId: Value(shpId),
        ),
      );
      await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          id: 'EXP-SHOP-1',
          description: 'شاي وقهوة',
          amount: 50.0,
          category: 'أكل / شاي',
          scope: const Value(ExpenseScope.shop),
        ),
      );

      // Close shipment -> net supplier due = 1000 - 100 (10%) - 100 (exp) = 800
      await ShipmentSettlementService(db).closeShipment(shipmentId: shpId);

      final exportBytes = await VegetableExcelExportService(db).buildWorkbookBytes();
      final wb = Excel.decodeBytes(exportBytes);

      expect(
        wb.tables.keys,
        containsAll([
          'كشوف الشحنات',
          'مديونيات الزباين',
          'أرصدة البرانيك الفارغة',
          'المصروفات',
        ]),
      );

      // Verify sheet 1: كشوف الشحنات
      final shpSheet = wb.tables['كشوف الشحنات']!;
      expect(shpSheet.rows.length, 2); // header + 1 shipment
      final shpRow = shpSheet.rows[1].map((c) => c?.value.toString()).toList();
      expect(shpRow[0], '#EXP-100');
      expect(shpRow[2], 'مزارع البحيرة');
      expect(shpRow[3], 'مقفولة');
      expect(double.parse(shpRow[8]!), closeTo(1000.0, 0.01)); // totalSales
      expect(double.parse(shpRow[10]!), closeTo(100.0, 0.01)); // commission 10%
      expect(double.parse(shpRow[11]!), closeTo(100.0, 0.01)); // shipmentExpensesTotal
      expect(double.parse(shpRow[12]!), closeTo(800.0, 0.01)); // netSupplierDue

      // Verify sheet 2: مديونيات الزباين (opening 200 + credit 600 = 800; barnika = 3)
      final debtSheet = wb.tables['مديونيات الزباين']!;
      expect(debtSheet.rows.length, 2);
      final debtRow = debtSheet.rows[1].map((c) => c?.value.toString()).toList();
      expect(debtRow[0], 'الحاج سعيد');
      expect(double.parse(debtRow[4]!), closeTo(800.0, 0.01));
      expect(debtRow[5], '3');

      // Verify sheet 3: أرصدة البرانيك الفارغة
      final barnikaSheet = wb.tables['أرصدة البرانيك الفارغة']!;
      expect(barnikaSheet.rows.length, 2);
      final bRow = barnikaSheet.rows[1].map((c) => c?.value.toString()).toList();
      expect(bRow[0], 'الحاج سعيد');
      expect(bRow[4], '5');
      expect(bRow[5], '2');
      expect(bRow[6], '3');

      // Verify sheet 4: المصروفات
      final expSheet = wb.tables['المصروفات']!;
      expect(expSheet.rows.length, 3); // header + 2 expenses
      final expTypes = expSheet.rows.skip(1).map((r) => r[1]?.value.toString()).toList();
      expect(expTypes, containsAll(['مصروف شحنة', 'مصروف محل']));
    });

    test('imports transactional ERP workbook with title rows, Row-3 headers, FormulaCellValue, and consolidated balances', () async {
      final excel = Excel.createExcel();

      // Sheet: موردين (Row 1 title, Row 2 empty, Row 3 headers)
      final sup = excel['موردين'];
      sup.appendRow([TextCellValue('شحنات الموردين - تجريبي')]);
      sup.appendRow([]);
      sup.appendRow([
        TextCellValue('م'),
        TextCellValue('التاريخ'),
        TextCellValue('اسم المورد'),
        TextCellValue('رقم الشحنة'),
        TextCellValue('عدد البرانيك'),
        TextCellValue('سعر الطماطم للبرنيكة'),
        TextCellValue('إجمالي التكلفة'),
      ]);
      sup.appendRow([
        IntCellValue(1),
        TextCellValue('2026-07-17'),
        TextCellValue('مورد تجريبي أ'),
        TextCellValue('ش-001'),
        IntCellValue(100),
        DoubleCellValue(150),
        FormulaCellValue('=E4*F4'),
      ]);
      // Repeat normalized supplier + empty supplier row (should consolidate & skip empty)
      sup.appendRow([
        IntCellValue(2),
        TextCellValue('2026-07-18'),
        TextCellValue('مورد تجريبى ا'),
        TextCellValue('ش-002'),
        IntCellValue(80),
        null,
        FormulaCellValue('=E5*F5'),
      ]);
      sup.appendRow([
        IntCellValue(3),
        TextCellValue('2026-07-19'),
        null,
        TextCellValue('ش-003'),
        IntCellValue(50),
      ]);

      // Sheet: زباين (Row 1 title, Row 2 empty, Row 3 headers, formulas in total/remaining)
      final cust = excel['زباين'];
      cust.appendRow([TextCellValue('مبيعات الزباين - كاش وآجل')]);
      cust.appendRow([]);
      cust.appendRow([
        TextCellValue('م'),
        TextCellValue('التاريخ'),
        TextCellValue('اسم الزبون'),
        TextCellValue('نوع الزبون'),
        TextCellValue('رقم الشحنة (مورد)'),
        TextCellValue('عدد البرانيك'),
        TextCellValue('سعر بيع البرنيكة'),
        TextCellValue('إجمالي المستحق'),
        TextCellValue('المدفوع'),
        TextCellValue('خصومات'),
        TextCellValue('الباقي (آجل)'),
        TextCellValue('البرانيك المستلمه'),
        TextCellValue('البرانيك المتبقيه'),
      ]);
      // Row 1 for الزبون التجريبي: 10 * 160 = 1600, paid 600, discount 100 -> debt 900; barnika 10 - 3 = 7
      cust.appendRow([
        IntCellValue(1),
        TextCellValue('2026-07-17'),
        TextCellValue('أحمد التجريبي'),
        TextCellValue('تاجر'),
        TextCellValue('ش-001'),
        IntCellValue(10),
        DoubleCellValue(160),
        FormulaCellValue('=F4*G4'),
        DoubleCellValue(600),
        DoubleCellValue(100),
        FormulaCellValue('=H4-I4-J4'),
        IntCellValue(3),
        FormulaCellValue('=F4-L4'),
      ]);
      // Row 2 for same customer without hamza: 5 * 200 = 1000, paid 200 -> debt 800; barnika 5 - 1 = 4
      cust.appendRow([
        IntCellValue(2),
        TextCellValue('2026-07-18'),
        TextCellValue('احمد التجريبى'),
        TextCellValue('تاجر'),
        TextCellValue('ش-002'),
        IntCellValue(5),
        DoubleCellValue(200),
        FormulaCellValue('=F5*G5'),
        DoubleCellValue(200),
        null,
        FormulaCellValue('=H5-I5'),
        IntCellValue(1),
        FormulaCellValue('=F5-L5'),
      ]);
      // Walk-in cash pseudo-name (must be skipped)
      cust.appendRow([
        IntCellValue(3),
        TextCellValue('2026-07-18'),
        TextCellValue('نقديه'),
        TextCellValue('نقدي'),
        TextCellValue('ش-002'),
        IntCellValue(4),
        DoubleCellValue(150),
        FormulaCellValue('=F6*G6'),
        DoubleCellValue(600),
        null,
        FormulaCellValue('=H6-I6'),
        IntCellValue(4),
        FormulaCellValue('=F6-L6'),
      ]);

      // Sheet: تحصيلات (Row 1 headers): 300 collected from أحمد التجريبي -> net debt = 900 + 800 - 300 = 1400
      final col = excel['تحصيلات'];
      col.appendRow([
        TextCellValue('م'),
        TextCellValue('التاريخ'),
        TextCellValue('اسم الزبون'),
        TextCellValue('المبلغ المحصل'),
      ]);
      col.appendRow([
        IntCellValue(1),
        TextCellValue('2026-07-19'),
        TextCellValue('أحمد التجريبي'),
        DoubleCellValue(300),
      ]);

      // Sheet: مصروفات (Row 1 title, Row 2 empty, Row 3 headers - should not crash Excel import)
      final exp = excel['مصروفات'];
      exp.appendRow([TextCellValue('المصروفات التشغيلية')]);
      exp.appendRow([]);
      exp.appendRow([
        TextCellValue('م'),
        TextCellValue('التاريخ'),
        TextCellValue('البند'),
        TextCellValue('الوصف'),
        TextCellValue('المبلغ'),
      ]);
      exp.appendRow([
        IntCellValue(1),
        TextCellValue('2026-07-17'),
        TextCellValue('نقل'),
        TextCellValue('نولون'),
        DoubleCellValue(500),
      ]);

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
      final bytes = Uint8List.fromList(excel.encode()!);

      final service = VegetableMarketImportService(db);
      final preview = await service.previewExcelBytes(bytes);
      expect(preview.suppliers.length, 1);
      expect(preview.suppliers.first.name, 'مورد تجريبي أ');
      expect(preview.customers.length, 1);
      expect(preview.customers.first.name, 'أحمد التجريبي');
      expect(preview.customers.first.openingDebt, closeTo(1400.0, 0.01));
      expect(preview.customers.first.openingBarnikas, 11);
      expect(preview.expensesCount, 0);
      expect(preview.collectionsCount, 0);

      final result = await service.importFromExcelBytes(bytes);
      expect(result.errors, isEmpty);
      expect(result.customers, 1);
      expect(result.suppliers, 1);
      expect(result.emptyBarnika, 1);

      final allCust = await db.customerDao.getAllCustomers();
      expect(allCust.length, 1);
      expect(allCust.first.openingBalance, closeTo(1400.0, 0.01));
      expect(
        await db.emptyBarnikaTrackingDao.getCustomerOutstandingBalance(allCust.first.id),
        11,
      );
    });
  });
}
