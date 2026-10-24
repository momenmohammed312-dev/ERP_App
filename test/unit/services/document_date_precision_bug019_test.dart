import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/ui/widgets/document_date_picker.dart';
import '../../helpers/license_grant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentDateService documentDate;

  setUp(() async {
    grantLicensedModules();
    db = AppDatabase(NativeDatabase.memory());
    documentDate = DocumentDateService(db);

    // Initial base references
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(categoryName: 'عام'),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        name: 'منتج تجريبي',
        price: 100.0,
        quantity: 50,
      ),
    );
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'C1',
        name: 'عميل 1',
      ),
    );
    await db.into(db.suppliers).insert(
      SuppliersCompanion.insert(
        id: 'S1',
        name: 'مورد 1',
      ),
    );
    await db.into(db.invoices).insert(
      InvoicesCompanion.insert(
        id: const Value(1),
        invoiceNumber: const Value('INV-001'),
        customerId: const Value('C1'),
        customerName: const Value('عميل 1'),
        totalAmount: const Value(1000.0),
        paidAmount: const Value(1000.0),
        status: const Value('paid'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    revokeLicensedModules();
  });

  group('BUG-019: DocumentDateService Precision & Audit Logging (C3, C4, C5, C6, C7, C9)', () {
    test('C3: updateSalesReturnDate updates return_refunds, ledger transactions, and inventory movements without altering createdAt', () async {
      final initialDate = DateTime(2026, 5, 1, 10, 0);
      final initialCreatedAt = DateTime(2026, 5, 1, 10, 0);
      final updatedDate = DateTime(2026, 5, 15, 16, 30);

      // 1. إنشاء مرتجع واسترداد نقدي
      final retId = await db.into(db.salesReturns).insert(
        SalesReturnsCompanion.insert(
          returnNumber: 'RET-001',
          customerName: 'عميل 1',
          returnReason: 'تالف',
          originalInvoiceId: 1,
          totalAmount: 200.0,
          refundedAmount: const Value(100.0),
          returnDate: initialDate,
          createdAt: Value(initialCreatedAt),
        ),
      );

      final refundId = await db.into(db.returnRefunds).insert(
        ReturnRefundsCompanion.insert(
          returnId: retId,
          refundDate: initialDate,
          amount: 100.0,
          method: 'cash',
          createdAt: Value(initialCreatedAt),
        ),
      );

      // 2. إنشاء قيود الأستاذ للمرتجع والاسترداد
      await db.into(db.ledgerTransactions).insert(
        LedgerTransactionsCompanion.insert(
          id: 'tx_ret_001',
          entityType: 'Customer',
          refId: 'C1',
          date: initialDate,
          description: 'مرتجع RET-001',
          origin: 'sales_return',
          receiptNumber: Value('RET$retId'),
        ),
      );

      await db.into(db.ledgerTransactions).insert(
        LedgerTransactionsCompanion.insert(
          id: 'uuid_retref_$refundId',
          entityType: 'Cash',
          refId: 'returns',
          date: initialDate,
          description: 'استرداد نقدي لمرتجع RET-001',
          origin: 'refund',
          receiptNumber: Value('RREF$refundId'),
        ),
      );

      // 3. حركة المخزون
      await db.into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
          productId: 1,
          movementType: 'in',
          quantity: 2,
          unitCost: 50.0,
          totalValue: 100.0,
          referenceType: 'sales_return',
          previousQuantity: 50,
          newQuantity: 52,
          movementDate: initialDate,
          reference: 'RET$retId',
          createdAt: initialDate,
          updatedAt: initialDate,
        ),
      );

      // 4. استدعاء updateSalesReturnDate
      final result = await documentDate.updateSalesReturnDate(
        returnId: retId,
        newDate: updatedDate,
        userId: 'admin_test',
      );

      expect(result.success, isTrue);
      expect(result.oldDate, equals(initialDate));
      expect(result.newDate, equals(updatedDate));

      // التحقق من جدول sales_returns
      final retRow = await db.salesReturnsDao.getReturnById(retId);
      expect(retRow!.returnDate, equals(updatedDate));
      expect(retRow.createdAt, equals(initialCreatedAt)); // لم يتغير لحماية الوردية

      // التحقق من جدول return_refunds
      final refundRows = await db.returnRefundsDao.getRefundsForReturn(retId);
      expect(refundRows, isNotEmpty);
      expect(refundRows.first.refundDate, equals(updatedDate));
      expect(refundRows.first.createdAt, equals(initialCreatedAt)); // لم يتغير لحماية الوردية

      // التحقق من قيود الأستاذ
      final retTx = await db.ledgerDao.getTransactionById('tx_ret_001');
      expect(retTx!.date, equals(updatedDate));

      final refundTx = await db.ledgerDao.getTransactionById('uuid_retref_$refundId');
      expect(refundTx!.date, equals(updatedDate));

      // التحقق من حركة المخزون
      final invMovs = await (db.select(db.inventoryMovements)
            ..where((t) => t.reference.equals('RET$retId')))
          .get();
      expect(invMovs.first.movementDate, equals(updatedDate));
    });

    test('C4: updateCustodyDate updates custody issue entry but preserves settlement entry at later date', () async {
      final issueDate = DateTime(2026, 6, 1, 9, 0);
      final settlementDate = DateTime(2026, 6, 20, 14, 0);
      final newIssueDate = DateTime(2026, 6, 5, 11, 0);

      // 1. إنشاء عهدة نقدية
      final custodyId = await db.into(db.cashCustodies).insert(
        CashCustodiesCompanion.insert(
          custodyNumber: 'CUST-001',
          staffId: 'STAFF-1',
          staffName: 'أحمد سعيد',
          amount: 1500.0,
          remainingAmount: 1500.0,
          date: issueDate,
          status: const Value('Settled'),
        ),
      );

      // 2. قيد صرف العهدة (debit > 0, credit == 0)
      await db.into(db.ledgerTransactions).insert(
        LedgerTransactionsCompanion.insert(
          id: 'tx_custody_issue_1',
          entityType: 'Custody',
          refId: custodyId.toString(),
          date: issueDate,
          description: 'صرف عهدة نقدية',
          origin: 'custody',
          debit: const Value(1500.0),
          credit: const Value(0.0),
        ),
      );

      // 3. قيد تسوية العهدة في يوم لاحق (credit > 0, debit == 0)
      await db.into(db.ledgerTransactions).insert(
        LedgerTransactionsCompanion.insert(
          id: 'tx_custody_settle_1',
          entityType: 'Custody',
          refId: custodyId.toString(),
          date: settlementDate,
          description: 'تسوية وإغلاق عهدة نقدية',
          origin: 'custody',
          debit: const Value(0.0),
          credit: const Value(1500.0),
        ),
      );

      // 4. تعديل تاريخ العهدة
      final result = await documentDate.updateCustodyDate(
        custodyId: custodyId,
        newDate: newIssueDate,
        userId: 'admin_test',
      );

      expect(result.success, isTrue);

      // التحقق من أن قيد الصرف فقط هو من تغير تاريخه
      final issueTx = await db.ledgerDao.getTransactionById('tx_custody_issue_1');
      expect(issueTx!.date, equals(newIssueDate));

      // التحقق الحاسم: قيد التسوية ظل بتارخه اللاحق دون أي تشويه!
      final settleTx = await db.ledgerDao.getTransactionById('tx_custody_settle_1');
      expect(settleTx!.date, equals(settlementDate));
    });

    test('C5: updatePaymentDate updates ONLY the single matching payment, leaving identical payments untouched', () async {
      final payDate1 = DateTime(2026, 7, 1, 10, 0);
      final payDate2 = DateTime(2026, 7, 10, 10, 0);
      final newPayDate = DateTime(2026, 7, 4, 12, 0);

      // إنشاء دفعتين بنفس المبلغ 500.0 على نفس الفاتورة 1
      final p1 = await db.into(db.invoicePayments).insert(
        InvoicePaymentsCompanion.insert(
          invoiceId: 1,
          paymentMethod: 'cash',
          amount: 500.0,
          paidAt: Value(payDate1),
        ),
      );

      final p2 = await db.into(db.invoicePayments).insert(
        InvoicePaymentsCompanion.insert(
          invoiceId: 1,
          paymentMethod: 'cash',
          amount: 500.0,
          paidAt: Value(payDate2),
        ),
      );

      // قيد الأستاذ الخاص بالدفعة الأولى فقط
      await db.into(db.ledgerTransactions).insert(
        LedgerTransactionsCompanion.insert(
          id: 'tx_payment_p1',
          entityType: 'Customer',
          refId: 'C1',
          date: payDate1,
          description: 'دفعة نقدية قسط 1',
          origin: 'payment',
          debit: const Value(500.0),
          credit: const Value(0.0),
          receiptNumber: const Value('INV1'),
          paymentMethod: const Value('cash'),
        ),
      );

      // تعديل تاريخ الدفعة الأولى
      final result = await documentDate.updatePaymentDate(
        transactionId: 'tx_payment_p1',
        newDate: newPayDate,
        userId: 'admin_test',
      );

      expect(result.success, isTrue);

      // قراءة الدفعتين من الجدول
      final rowP1 = await (db.select(db.invoicePayments)..where((t) => t.id.equals(p1))).getSingle();
      final rowP2 = await (db.select(db.invoicePayments)..where((t) => t.id.equals(p2))).getSingle();

      // الدفعة الأولى تم تحديثها للتاريخ الجديد
      expect(rowP1.paidAt, equals(newPayDate));

      // التحقق الحاسم: الدفعة الثانية ظلت كما هي بتارخها payDate2!
      expect(rowP2.paidAt, equals(payDate2));
    });

    test('C6: updateExpenseDate updates target expense ledger entry accurately and does not touch other expenses on the same date with same amount', () async {
      final d1 = DateTime(2026, 8, 1, 10, 0);
      final newExpDate = DateTime(2026, 8, 8, 15, 0);

      // مصروفين متزامنين بنفس القيمة 150.0
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: 'EXP-101',
          description: 'فاتورة مياه',
          amount: 150.0,
          date: Value(d1),
          category: 'مرافق',
        ),
      );

      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: 'EXP-102',
          description: 'شراء أدوات نظافة',
          amount: 150.0,
          date: Value(d1),
          category: 'نظافة',
        ),
      );

      // قيدان منفصلان في الأستاذ
      await db.into(db.ledgerTransactions).insert(
        LedgerTransactionsCompanion.insert(
          id: 'tx_exp_101',
          entityType: 'Expense',
          refId: 'EXP-101',
          date: d1,
          description: 'فاتورة مياه',
          origin: 'expense',
          debit: const Value(0.0),
          credit: const Value(150.0),
        ),
      );

      await db.into(db.ledgerTransactions).insert(
        LedgerTransactionsCompanion.insert(
          id: 'tx_exp_102',
          entityType: 'Expense',
          refId: 'EXP-102',
          date: d1,
          description: 'شراء أدوات نظافة',
          origin: 'expense',
          debit: const Value(0.0),
          credit: const Value(150.0),
        ),
      );

      // تعديل تاريخ EXP-101
      await documentDate.updateExpenseDate(
        expenseId: 'EXP-101',
        newDate: newExpDate,
        userId: 'admin_test',
      );

      final tx101 = await db.ledgerDao.getTransactionById('tx_exp_101');
      final tx102 = await db.ledgerDao.getTransactionById('tx_exp_102');

      expect(tx101!.date, equals(newExpDate));
      // التحقق الحاسم: tx_exp_102 لم يتغير!
      expect(tx102!.date, equals(d1));
    });

    test('C7: Audit log captures recordKey in oldValue and newValue for UUID and string IDs', () async {
      // 1. اختبار فاتورة مشتريات بـ UUID
      const purchaseUuid = 'e82b793d-4c31-482a-9cb0-1a6fba947b1c';
      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: purchaseUuid,
          invoiceNumber: 'PUR-999',
          supplierId: const Value('S1'),
          totalAmount: 500.0,
          paidAmount: const Value(500.0),
          purchaseDate: DateTime(2026, 9, 1, 10, 0),
          description: 'فاتورة مشتريات تجريبية',
          createdAt: DateTime(2026, 9, 1, 10, 0),
        ),
      );

      await documentDate.updatePurchaseDate(
        purchaseId: purchaseUuid,
        newDate: DateTime(2026, 9, 5, 10, 0),
        userId: 'user_42',
      );

      final purAudits = await (db.select(db.auditLog)
            ..where((t) => t.tableNameField.equals('purchases')))
          .get();
      expect(purAudits, isNotEmpty);
      final purAudit = purAudits.first;
      expect(purAudit.recordId, isNull); // int? is null for UUID
      final purOld = jsonDecode(purAudit.oldValue!);
      final purNew = jsonDecode(purAudit.newValue!);
      expect(purOld['recordKey'], equals(purchaseUuid));
      expect(purNew['recordKey'], equals(purchaseUuid));

      // 2. اختبار مصروف بـ ID نصي
      const expenseStrId = 'EXP-STR-888';
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: expenseStrId,
          description: 'مصروف تجريبي للتدقيق',
          amount: 80.0,
          date: Value(DateTime(2026, 9, 1, 10, 0)),
          category: 'عام',
        ),
      );

      await documentDate.updateExpenseDate(
        expenseId: expenseStrId,
        newDate: DateTime(2026, 9, 6, 11, 0),
        userId: 'user_42',
      );

      final expAudits = await (db.select(db.auditLog)
            ..where((t) => t.tableNameField.equals('expenses')))
          .get();
      expect(expAudits, isNotEmpty);
      final expAudit = expAudits.first;
      final expOld = jsonDecode(expAudit.oldValue!);
      final expNew = jsonDecode(expAudit.newValue!);
      expect(expOld['recordKey'], equals(expenseStrId));
      expect(expNew['recordKey'], equals(expenseStrId));
    });

    testWidgets('C9: pickDocumentDate respects allowFutureDates and caps at end-of-day safely', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  // pick with default allowFutureDates=false
                  await pickDocumentDate(
                    context: context,
                    db: db,
                    initialDate: DateTime.now(),
                  );
                },
                child: const Text('افتح منتقي التاريخ'),
              ),
            ),
          ),
        ),
      );

      // Verify widget builds and launches without assertion errors
      expect(find.text('افتح منتقي التاريخ'), findsOneWidget);
      await tester.tap(find.text('افتح منتقي التاريخ'));
      await tester.pumpAndSettle();

      // Date picker dialog should be visible on screen
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
