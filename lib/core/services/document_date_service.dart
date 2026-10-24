import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'audit_log_service.dart';

/// نتيجة عملية تعديل تاريخ المستند
class DocumentDateUpdateResult {
  final bool success;
  final DateTime oldDate;
  final DateTime newDate;
  final bool isClosedDay;
  final String? message;

  const DocumentDateUpdateResult({
    required this.success,
    required this.oldDate,
    required this.newDate,
    required this.isClosedDay,
    this.message,
  });
}

/// خدمة مركزية موحدة لتعديل تاريخ المستندات المالية والتحقق من الأيام المغلقة
/// [MONEY] كل التعديلات تجري داخل معاملة ذرية واحدة (db.transaction) للحفاظ على اتساق الأرصدة
class DocumentDateService {
  final AppDatabase db;

  DocumentDateService(this.db);

  /// يدمج التاريخ المختار (السنة والشهر واليوم) مع وقت اللحظة الحالية أو وقت محدد (الساعة والدقيقة والثانية)
  static DateTime mergeWithCurrentTime(DateTime selectedDate, [DateTime? timeSource]) {
    final now = timeSource ?? DateTime.now();
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
    );
  }

  /// فحص هل يقع التاريخ في يوم تم إغلاقه سابقاً عبر جدول days
  /// يرجع true إذا كان هناك سجل يوم لهذا التاريخ وجميع جلساته مغلقة (isOpen == false)
  Future<bool> isDateInClosedDay(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    final rows = await (db.select(db.days)
      ..where((t) => t.date.isBetweenValues(startOfDay, endOfDay)))
      .get();

    if (rows.isEmpty) return false;
    // إذا كان هناك أي يوم مفتوح، فاليوم ليس مغلقاً كلياً. إن كانت كل السجلات مغلقة، فهو يوم مغلق.
    return rows.every((r) => !r.isOpen);
  }

  /// تعديل تاريخ فاتورة مبيعات
  /// - يعدل invoices.date (دون المساس بـ created_at أو رقم الفاتورة)
  /// - يحدث ledger_transactions (للمبيعات والدفعة الأولى المرتبطة)
  /// - يحدث invoice_payments.paid_at
  /// - يحدث inventory_movements.movement_date
  /// - يوثق التعديل في سجل التدقيق audit_logs مع وسم day_closed_warning
  Future<DocumentDateUpdateResult> updateInvoiceDate({
    required int invoiceId,
    required DateTime newDate,
    String? userId,
  }) async {
    final invoice = await db.invoiceDao.getInvoiceById(invoiceId);
    if (invoice == null) {
      throw Exception('الفاتورة غير موجودة (ID: $invoiceId)');
    }

    final oldDate = invoice.date;
    final isClosed = await isDateInClosedDay(newDate);

    await db.transaction(() async {
      // 1. تحديث جدول الفواتير (تاريخ الفاتورة فقط، created_at يبقى دون تغيير)
      await (db.update(db.invoices)..where((t) => t.id.equals(invoiceId))).write(
        InvoicesCompanion(
          date: Value(newDate),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 2. تحديث قيود دفتر الأستاذ المرتبطة بالفاتورة
      final invReceipt = 'INV$invoiceId';
      final invNumber = invoice.invoiceNumber;

      await (db.update(db.ledgerTransactions)
        ..where((t) {
          var expr = t.receiptNumber.equals(invReceipt);
          if (invNumber != null && invNumber.isNotEmpty) {
            expr = expr | t.receiptNumber.equals(invNumber);
          }
          return expr;
        })
      ).write(
        LedgerTransactionsCompanion(
          date: Value(newDate),
        ),
      );

      // دعم الحالات القديمة إذا كانت الفاتورة مرتبطة بعميل وقيد المبيعات يحمل نفس التاريخ والوصف
      if (invoice.customerId != null && invoice.customerId != 'cash' && invoice.customerId!.isNotEmpty) {
        await (db.update(db.ledgerTransactions)
          ..where((t) =>
            t.entityType.equals('Customer') &
            t.refId.equals(invoice.customerId!) &
            t.origin.isIn(['sale', 'payment']) &
            t.date.equals(oldDate) &
            (t.receiptNumber.isNull() | t.receiptNumber.equals(''))
          )
        ).write(
          LedgerTransactionsCompanion(
            date: Value(newDate),
          ),
        );
      }

      // 3. تحديث جدول مدفوعات الفاتورة invoice_payments
      await (db.update(db.invoicePayments)..where((t) => t.invoiceId.equals(invoiceId))).write(
        InvoicePaymentsCompanion(
          paidAt: Value(newDate),
        ),
      );

      // 4. تحديث حركات المخزون inventory_movements المرتبطة بالفاتورة
      await (db.update(db.inventoryMovements)
        ..where((t) {
          var expr = t.reference.equals(invoiceId.toString()) |
                     t.reference.equals(invReceipt);
          if (invNumber != null && invNumber.isNotEmpty) {
            expr = expr | t.reference.equals(invNumber);
          }
          return expr;
        })
      ).write(
        InventoryMovementsCompanion(
          movementDate: Value(newDate),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 5. توثيق العملية في سجل التدقيق audit_logs
      await AuditService.log(
        db: db,
        action: 'DATE_CHANGE',
        tableName: 'invoices',
        recordId: invoiceId,
        details: '[MONEY] تعديل تاريخ فاتورة مبيعات ${invoice.invoiceNumber ?? invoiceId} من ${oldDate.toIso8601String()} إلى ${newDate.toIso8601String()}${isClosed ? ' (تحذير: يوم مغلق)' : ''}',
        oldValue: {
          'recordKey': invoiceId.toString(),
          'date': oldDate.toIso8601String(),
          'day_closed_warning': false,
        },
        newValue: {
          'recordKey': invoiceId.toString(),
          'date': newDate.toIso8601String(),
          'day_closed_warning': isClosed,
          'userId': userId,
        },
        userId: int.tryParse(userId ?? ''),
      );
    });

    return DocumentDateUpdateResult(
      success: true,
      oldDate: oldDate,
      newDate: newDate,
      isClosedDay: isClosed,
    );
  }

  /// تعديل تاريخ فاتورة مشتريات
  /// - يعدل purchases.purchase_date (دون المساس بـ created_at)
  /// - يحدث قيود المورد في دفتر الأستاذ (الشراء والدفعة المصاحبة)
  /// - يحدث حركات المخزون المرتبطة بالفاتورة
  /// - يوثق التعديل في سجل التدقيق audit_logs
  Future<DocumentDateUpdateResult> updatePurchaseDate({
    required String purchaseId,
    required DateTime newDate,
    String? userId,
  }) async {
    final purchase = await (db.select(db.purchases)
      ..where((t) => t.id.equals(purchaseId) | t.invoiceNumber.equals(purchaseId)))
      .getSingleOrNull();

    if (purchase == null) {
      throw Exception('فاتورة المشتريات غير موجودة (ID: $purchaseId)');
    }

    final oldDate = purchase.purchaseDate;
    final isClosed = await isDateInClosedDay(newDate);
    final invNum = purchase.invoiceNumber;

    await db.transaction(() async {
      // 1. تحديث جدول المشتريات
      await (db.update(db.purchases)..where((t) => t.id.equals(purchase.id))).write(
        PurchasesCompanion(
          purchaseDate: Value(newDate),
        ),
      );

      // 2. تحديث قيود المورد في دفتر الأستاذ
      await (db.update(db.ledgerTransactions)
        ..where((t) =>
          t.id.equals('${invNum}_ledger') |
          t.id.equals('${invNum}_ledger_pay') |
          t.id.equals('${purchase.id}_ledger') |
          t.id.equals('${purchase.id}_ledger_pay') |
          t.receiptNumber.equals(invNum) |
          t.receiptNumber.equals(purchase.id) |
          t.receiptNumber.equals('PUR${purchase.id}')
        )
      ).write(
        LedgerTransactionsCompanion(
          date: Value(newDate),
        ),
      );

      // 3. تحديث حركات المخزون inventory_movements
      await (db.update(db.inventoryMovements)
        ..where((t) =>
          t.reference.equals(invNum) |
          t.reference.equals(purchase.id) |
          t.reference.equals('PUR${purchase.id}')
        )
      ).write(
        InventoryMovementsCompanion(
          movementDate: Value(newDate),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 4. توثيق العملية في سجل التدقيق audit_logs
      await AuditService.log(
        db: db,
        action: 'DATE_CHANGE',
        tableName: 'purchases',
        recordId: int.tryParse(purchase.id),
        details: '[MONEY] تعديل تاريخ فاتورة مشتريات $invNum من ${oldDate.toIso8601String()} إلى ${newDate.toIso8601String()}${isClosed ? ' (تحذير: يوم مغلق)' : ''}',
        oldValue: {
          'recordKey': purchase.id,
          'date': oldDate.toIso8601String(),
          'day_closed_warning': false,
        },
        newValue: {
          'recordKey': purchase.id,
          'date': newDate.toIso8601String(),
          'day_closed_warning': isClosed,
          'userId': userId,
        },
        userId: int.tryParse(userId ?? ''),
      );
    });

    return DocumentDateUpdateResult(
      success: true,
      oldDate: oldDate,
      newDate: newDate,
      isClosedDay: isClosed,
    );
  }

  /// تعديل تاريخ مصروف
  /// - يعدل expenses.date (دون المساس بـ created_at)
  /// - يحدث قيد الأستاذ المقابل إن وجد
  /// - يوثق التعديل في سجل التدقيق audit_logs
  Future<DocumentDateUpdateResult> updateExpenseDate({
    required String expenseId,
    required DateTime newDate,
    String? userId,
  }) async {
    final expense = await db.expenseDao.getExpenseById(expenseId);
    if (expense == null) {
      throw Exception('المصروف غير موجود (ID: $expenseId)');
    }

    final oldDate = expense.date;
    final isClosed = await isDateInClosedDay(newDate);

    await db.transaction(() async {
      // 1. تحديث جدول المصروفات
      await (db.update(db.expenses)..where((t) => t.id.equals(expenseId))).write(
        ExpensesCompanion(
          date: Value(newDate),
        ),
      );

      // 2. تحديث قيد الأستاذ المقابل بدقة وتجنب تحديث قيود مصروفات أخرى مصادفة (العيب C6)
      // نبحث أولاً عن القيود المرتبطة مباشرة بمعرف المصروف
      final directMatches = await (db.select(db.ledgerTransactions)
        ..where((t) {
          var expr = t.refId.equals(expenseId) |
                     t.id.equals(expenseId) |
                     t.id.equals('${expenseId}_ledger') |
                     t.receiptNumber.equals(expenseId);
          if (expense.receiptNumber != null && expense.receiptNumber!.isNotEmpty) {
            expr = expr | t.receiptNumber.equals(expense.receiptNumber!);
          }
          return expr;
        })).get();

      if (directMatches.isNotEmpty) {
        final matchIds = directMatches.map((e) => e.id).toList();
        await (db.update(db.ledgerTransactions)
          ..where((t) => t.id.isIn(matchIds))
        ).write(
          LedgerTransactionsCompanion(
            date: Value(newDate),
          ),
        );
      } else {
        // في حال عدم وجود ربط مباشر، نبحث عن القيود اليتيمة لنفس المصروف والمبلغ والتاريخ القديم
        // مع تفضيل القيد المطابق بالوصف واختيار قيد واحد فقط لتفادي تضرر مصروفات أخرى متزامنة
        final fallbackMatches = await (db.select(db.ledgerTransactions)
          ..where((t) =>
            t.origin.equals('expense') &
            t.credit.equals(expense.amount) &
            t.date.equals(oldDate)
          )).get();

        if (fallbackMatches.isNotEmpty) {
          LedgerTransaction? targetTx;
          for (final tx in fallbackMatches) {
            if (tx.description.contains(expense.description) ||
                expense.description.contains(tx.description)) {
              targetTx = tx;
              break;
            }
          }
          targetTx ??= fallbackMatches.first;

          await (db.update(db.ledgerTransactions)
            ..where((t) => t.id.equals(targetTx!.id))
          ).write(
            LedgerTransactionsCompanion(
              date: Value(newDate),
            ),
          );
        }
      }

      // 3. توثيق العملية في سجل التدقيق audit_logs مع حفظ المعرف النصي (العيب C7)
      await AuditService.log(
        db: db,
        action: 'DATE_CHANGE',
        tableName: 'expenses',
        recordId: int.tryParse(expenseId),
        details: '[MONEY] تعديل تاريخ المصروف ${expense.description} من ${oldDate.toIso8601String()} إلى ${newDate.toIso8601String()}${isClosed ? ' (تحذير: يوم مغلق)' : ''}',
        oldValue: {
          'recordKey': expenseId,
          'date': oldDate.toIso8601String(),
          'day_closed_warning': false,
        },
        newValue: {
          'recordKey': expenseId,
          'date': newDate.toIso8601String(),
          'day_closed_warning': isClosed,
          'userId': userId,
        },
        userId: int.tryParse(userId ?? ''),
      );
    });

    return DocumentDateUpdateResult(
      success: true,
      oldDate: oldDate,
      newDate: newDate,
      isClosedDay: isClosed,
    );
  }

  /// تعديل تاريخ دفعة (سداد عميل أو مورد)
  /// - يعدل ledger_transactions.date
  /// - يحدث حركة invoice_payments المقابلة إن وجدت
  /// - يوثق التعديل في سجل التدقيق audit_logs
  Future<DocumentDateUpdateResult> updatePaymentDate({
    required String transactionId,
    required DateTime newDate,
    String? userId,
  }) async {
    final tx = await db.ledgerDao.getTransactionById(transactionId);
    if (tx == null) {
      throw Exception('المعاملة غير موجودة (ID: $transactionId)');
    }

    final oldDate = tx.date;
    final isClosed = await isDateInClosedDay(newDate);

    await db.transaction(() async {
      // 1. تحديث صف دفتر الأستاذ
      await (db.update(db.ledgerTransactions)..where((t) => t.id.equals(transactionId))).write(
        LedgerTransactionsCompanion(
          date: Value(newDate),
        ),
      );

      // 2. تحديث حركة invoice_payments بدقة إن كانت الدفعة مرتبطة بفاتورة (INV<id>) (العيب C5)
      final invMatch = tx.receiptNumber != null
          ? RegExp(r'^INV(\d+)$').firstMatch(tx.receiptNumber!)
          : null;
      if (invMatch != null) {
        final invoiceId = int.tryParse(invMatch.group(1) ?? '');
        if (invoiceId != null) {
          final amount = tx.credit > 0 ? tx.credit : tx.debit;
          final payments = await (db.select(db.invoicePayments)
            ..where((t) => t.invoiceId.equals(invoiceId) & t.amount.equals(amount)))
            .get();

          if (payments.isNotEmpty) {
            // مطابقة أدق دفعة بالزمن القديم أو طريقة الدفع لتجنب تعديل دفعات أخرى متساوية
            InvoicePayment? targetPayment;
            for (final p in payments) {
              if (p.paidAt == oldDate) {
                targetPayment = p;
                break;
              }
            }
            if (targetPayment == null && tx.paymentMethod != null) {
              for (final p in payments) {
                if (p.paymentMethod == tx.paymentMethod) {
                  targetPayment = p;
                  break;
                }
              }
            }
            if (targetPayment == null) {
              payments.sort((a, b) =>
                (a.paidAt.difference(oldDate).abs()).compareTo(b.paidAt.difference(oldDate).abs())
              );
              targetPayment = payments.first;
            }

            await (db.update(db.invoicePayments)
              ..where((t) => t.id.equals(targetPayment!.id)))
              .write(InvoicePaymentsCompanion(paidAt: Value(newDate)));
          }
        }
      }

      // 3. توثيق العملية في سجل التدقيق audit_logs مع حفظ المعرف النصي (العيب C7)
      await AuditService.log(
        db: db,
        action: 'DATE_CHANGE',
        tableName: 'ledger_transactions',
        recordId: int.tryParse(transactionId),
        details: '[MONEY] تعديل تاريخ الدفعة ${tx.description} من ${oldDate.toIso8601String()} إلى ${newDate.toIso8601String()}${isClosed ? ' (تحذير: يوم مغلق)' : ''}',
        oldValue: {
          'recordKey': transactionId,
          'date': oldDate.toIso8601String(),
          'day_closed_warning': false,
        },
        newValue: {
          'recordKey': transactionId,
          'date': newDate.toIso8601String(),
          'day_closed_warning': isClosed,
          'userId': userId,
        },
        userId: int.tryParse(userId ?? ''),
      );
    });

    return DocumentDateUpdateResult(
      success: true,
      oldDate: oldDate,
      newDate: newDate,
      isClosedDay: isClosed,
    );
  }

  /// تعديل تاريخ عهدة نقدية
  /// - يعدل cash_custodies.date (دون المساس بـ created_at)
  /// - يحدث حركة العهدة في دفتر الأستاذ
  /// - يوثق التعديل في سجل التدقيق audit_logs
  Future<DocumentDateUpdateResult> updateCustodyDate({
    required int custodyId,
    required DateTime newDate,
    String? userId,
  }) async {
    final custody = await db.custodyDao.getCustodyById(custodyId);
    if (custody == null) {
      throw Exception('العهدة غير موجودة (ID: $custodyId)');
    }

    final oldDate = custody.date;
    final isClosed = await isDateInClosedDay(newDate);

    await db.transaction(() async {
      // 1. تحديث جدول العهد
      await (db.update(db.cashCustodies)..where((t) => t.id.equals(custodyId))).write(
        CashCustodiesCompanion(
          date: Value(newDate),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 2. تحديث حركة صرف العهدة فقط في دفتر الأستاذ دون المساس بقيد التسوية أو الرد (العيب C4)
      await (db.update(db.ledgerTransactions)
        ..where((t) =>
          t.entityType.equals('Custody') &
          (t.refId.equals(custodyId.toString()) | t.id.like('%_custody_$custodyId')) &
          t.debit.isBiggerThanValue(0.0) &
          t.credit.equals(0.0)
        )
      ).write(
        LedgerTransactionsCompanion(
          date: Value(newDate),
        ),
      );

      // 3. توثيق العملية في سجل التدقيق audit_logs مع حفظ المعرف (العيب C7)
      await AuditService.log(
        db: db,
        action: 'DATE_CHANGE',
        tableName: 'cash_custodies',
        recordId: custodyId,
        details: '[MONEY] تعديل تاريخ العهدة ${custody.custodyNumber} من ${oldDate.toIso8601String()} إلى ${newDate.toIso8601String()}${isClosed ? ' (تحذير: يوم مغلق)' : ''}',
        oldValue: {
          'recordKey': custodyId.toString(),
          'date': oldDate.toIso8601String(),
          'day_closed_warning': false,
        },
        newValue: {
          'recordKey': custodyId.toString(),
          'date': newDate.toIso8601String(),
          'day_closed_warning': isClosed,
          'userId': userId,
        },
        userId: int.tryParse(userId ?? ''),
      );
    });

    return DocumentDateUpdateResult(
      success: true,
      oldDate: oldDate,
      newDate: newDate,
      isClosedDay: isClosed,
    );
  }

  /// تعديل تاريخ مرتجع مبيعات
  /// - يعدل sales_returns.return_date (ممنوع مرتجعات الشراء)
  /// - يحدث قيد العكس في دفتر الأستاذ
  /// - يوثق التعديل في سجل التدقيق audit_logs
  Future<DocumentDateUpdateResult> updateSalesReturnDate({
    required int returnId,
    required DateTime newDate,
    String? userId,
  }) async {
    final ret = await db.salesReturnsDao.getReturnById(returnId);
    if (ret == null) {
      throw Exception('مرتجع المبيعات غير موجود (ID: $returnId)');
    }

    final oldDate = ret.returnDate;
    final isClosed = await isDateInClosedDay(newDate);

    await db.transaction(() async {
      // 1. تحديث جدول مرتجعات المبيعات
      await (db.update(db.salesReturns)..where((t) => t.id.equals(returnId))).write(
        SalesReturnsCompanion(
          returnDate: Value(newDate),
        ),
      );

      // 2. تحديث سجلات الاسترداد النقدي return_refunds المرتبطة بالمرتجع (العيب C3)
      final refunds = await db.returnRefundsDao.getRefundsForReturn(returnId);
      await (db.update(db.returnRefunds)..where((t) => t.returnId.equals(returnId))).write(
        ReturnRefundsCompanion(
          refundDate: Value(newDate),
        ),
      );

      // 3. تحديث قيد العكس في دفتر الأستاذ الخاص بالمرتجع
      await (db.update(db.ledgerTransactions)
        ..where((t) =>
          t.receiptNumber.equals('RET$returnId') |
          t.id.like('%_ret_$returnId')
        )
      ).write(
        LedgerTransactionsCompanion(
          date: Value(newDate),
        ),
      );

      // 4. تحديث قيود الاسترداد النقدي في دفتر الأستاذ ledger_transactions (العيب C3)
      for (final rf in refunds) {
        await (db.update(db.ledgerTransactions)
          ..where((t) =>
            t.receiptNumber.equals('RREF${rf.id}') |
            t.id.like('%_retref_${rf.id}') |
            (t.entityType.equals('SalesReturnRefund') & t.refId.equals(rf.id.toString()))
          )
        ).write(
          LedgerTransactionsCompanion(
            date: Value(newDate),
          ),
        );
      }

      // 5. تحديث حركات المخزون inventory_movements المرتبطة بالمرتجع
      await (db.update(db.inventoryMovements)
        ..where((t) {
          var expr = t.reference.equals('RET$returnId');
          if (ret.returnNumber.isNotEmpty) {
            expr = expr | t.reference.equals(ret.returnNumber);
          }
          return expr;
        })
      ).write(
        InventoryMovementsCompanion(
          movementDate: Value(newDate),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 6. توثيق العملية في سجل التدقيق audit_logs مع حفظ المعرف (العيب C7)
      await AuditService.log(
        db: db,
        action: 'DATE_CHANGE',
        tableName: 'sales_returns',
        recordId: returnId,
        details: '[MONEY] تعديل تاريخ مرتجع المبيعات ${ret.returnNumber} من ${oldDate.toIso8601String()} إلى ${newDate.toIso8601String()}${isClosed ? ' (تحذير: يوم مغلق)' : ''}',
        oldValue: {
          'recordKey': returnId.toString(),
          'date': oldDate.toIso8601String(),
          'day_closed_warning': false,
        },
        newValue: {
          'recordKey': returnId.toString(),
          'date': newDate.toIso8601String(),
          'day_closed_warning': isClosed,
          'userId': userId,
        },
        userId: int.tryParse(userId ?? ''),
      );
    });

    return DocumentDateUpdateResult(
      success: true,
      oldDate: oldDate,
      newDate: newDate,
      isClosedDay: isClosed,
    );
  }
}
