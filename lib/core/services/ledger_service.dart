import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/audit_log_service.dart';

/// خدمة تعديل المدفوعات المالية بأمان (atomic) مع الحفاظ على اتساق
/// رصيد العميل والفاتورة المرتبطة. تعتمد على نفس conventions النظام الحالي:
/// الدفعة المرتبطة بفاتورة مرتبطة عبر `receiptNumber = 'INV<id>'`.
class LedgerService {
  final AppDatabase _db;

  LedgerService(this._db);

  static final _invReceipt = RegExp(r'^INV(\d+)$');

  /// يعدّل دفعة عميل (ledger transaction بـ origin = 'payment').
  ///
  /// - لو الدفعة مرتبطة بفاتورة: يحدّث مبلغ الدفعة في دفتر الأستاذ
  ///   ويحدّث `paidAmount`/الحالة في الفاتورة تلقائياً.
  /// - لو دفعة مستقلة: يحدّث صف الدفتر فقط.
  /// كل التحديثات داخل transaction واحد.
  Future<void> editCustomerPayment({
    required String transactionId,
    required double newAmount,
    required DateTime date,
    required String paymentMethod,
    String? note,
    String? performedBy,
  }) async {
    if (newAmount <= 0) throw Exception('مبلغ الدفعة يجب أن يكون أكبر من صفر');

    final tx = await _db.ledgerDao.getTransactionById(transactionId);
    if (tx == null) throw Exception('المعاملة غير موجودة');
    if (tx.origin != 'payment') {
      throw Exception('هذه المعاملة ليست دفعة قابلة للتعديل');
    }

    final invMatch = tx.receiptNumber != null
        ? _invReceipt.firstMatch(tx.receiptNumber!)
        : null;
    final int? invoiceId = invMatch != null
        ? int.tryParse(invMatch.group(1) ?? '')
        : null;

    final oldValues = {
      'id': tx.id,
      'amount': tx.credit > 0 ? tx.credit : tx.debit,
      'date': tx.date.toIso8601String(),
      'paymentMethod': tx.paymentMethod,
      'description': tx.description,
    };

    await _db.transaction(() async {
      // 1. تحديث صف الدفتر.
      await _db.ledgerDao.updateTransaction(
        LedgerTransactionsCompanion(
          id: Value(tx.id),
          entityType: Value(tx.entityType),
          refId: Value(tx.refId),
          date: Value(date),
          description:
              Value(note != null && note.isNotEmpty ? note : tx.description),
          debit: const Value(0.0),
          credit: Value(newAmount),
          origin: Value(tx.origin),
          paymentMethod: Value(paymentMethod),
          receiptNumber: Value(tx.receiptNumber),
        ),
      );

      // 2. لو مرتبطة بفاتورة: مزامنة الفاتورة.
      if (invoiceId != null) {
        final invoice = await _db.invoiceDao.getInvoiceById(invoiceId);
        if (invoice == null) throw Exception('الفاتورة المرتبطة غير موجودة');

        final total = invoice.totalAmount;
        final status = newAmount >= total
            ? 'paid'
            : (newAmount > 0 ? 'partial' : 'pending');

        await _db.invoiceDao.updateInvoice(
          invoice.copyWith(
            paidAmount: newAmount,
            status: status,
            cashAmount: paymentMethod == 'cash' ? newAmount : 0,
            cardAmount: paymentMethod == 'visa' ||
                    paymentMethod == 'card' ||
                    paymentMethod == 'bank'
                ? newAmount
                : 0,
            creditAmount: paymentMethod == 'credit' ? newAmount : 0,
          ),
        );
      }
    });

    if (performedBy != null) {
      await AuditService.log(
        db: _db,
        action: 'UPDATE',
        tableName: 'ledger_transactions',
        recordId: null,
        details: 'تعديل دفعة عميل${invoiceId != null ? ' (فاتورة #$invoiceId)' : ''}',
        oldValue: oldValues,
        newValue: {
          'id': tx.id,
          'amount': newAmount,
          'date': date.toIso8601String(),
          'paymentMethod': paymentMethod,
          'description': note,
        },
      );
    }
  }

  /// يحذف دفعة مستقلة (ليست مرتبطة بفاتورة) ويرجع مبلغها لرصيد العميل.
  /// الدفعات المرتبطة بفاتورة لا تُحذف مباشرة (يُعدّل مبلغ الفاتورة بدلاً منها).
  Future<void> deleteStandalonePayment({
    required String transactionId,
    String? performedBy,
  }) async {
    final tx = await _db.ledgerDao.getTransactionById(transactionId);
    if (tx == null) throw Exception('المعاملة غير موجودة');
    if (tx.receiptNumber != null && _invReceipt.hasMatch(tx.receiptNumber!)) {
      throw Exception('هذه الدفعة مرتبطة بفاتورة، عدّل الفاتورة بدلاً من حذفها');
    }

    final oldValues = {
      'id': tx.id,
      'amount': tx.credit > 0 ? tx.credit : tx.debit,
      'refId': tx.refId,
    };

    await _db.ledgerDao.deleteTransaction(transactionId);

    if (performedBy != null) {
      await AuditService.log(
        db: _db,
        action: 'DELETE',
        tableName: 'ledger_transactions',
        recordId: null,
        details: 'حذف دفعة عميل مستقلة',
        oldValue: oldValues,
        newValue: null,
      );
    }
  }

  // ── Supplier ──

  /// يعدّل حركة مورد (شراء/دفعة/تسوية).
  /// للمورد: المشتريات تزيد الرصيد (credit)، المدفوعات تنقصه (debit) —
  /// لكن نحافظ على توافق مع بيانات قديمة عبر تحديث الحقل المستخدم أصلاً (credit vs debit).
  Future<void> editSupplierTransaction({
    required String transactionId,
    required double newAmount,
    required DateTime date,
    String? paymentMethod,
    String? note,
    String? performedBy,
  }) async {
    if (newAmount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    final tx = await _db.ledgerDao.getTransactionById(transactionId);
    if (tx == null) throw Exception('المعاملة غير موجودة');
    if (tx.entityType != 'Supplier') throw Exception('هذه ليست حركة مورد');

    final oldValues = {
      'id': tx.id,
      'amount': tx.credit > 0 ? tx.credit : tx.debit,
      'date': tx.date.toIso8601String(),
      'paymentMethod': tx.paymentMethod,
      'description': tx.description,
      'origin': tx.origin,
    };

    // Preserve which side was used (credit/debit) for backward compatibility.
    final isCreditSide = tx.credit > 0;
    // For supplier, if original was credit (purchase) keep credit, if debit (payment) keep debit.
    // If both zero (shouldn't happen), default by origin.
    final useCredit = isCreditSide || (tx.credit == 0 && tx.debit == 0 && (tx.origin == 'purchase' || tx.origin == 'opening'));

    await _db.transaction(() async {
      await _db.ledgerDao.updateTransaction(
        LedgerTransactionsCompanion(
          id: Value(tx.id),
          entityType: Value(tx.entityType),
          refId: Value(tx.refId),
          date: Value(date),
          description: Value(note != null && note.isNotEmpty ? note : tx.description),
          debit: Value(useCredit ? 0.0 : newAmount),
          credit: Value(useCredit ? newAmount : 0.0),
          origin: Value(tx.origin),
          paymentMethod: paymentMethod != null ? Value(paymentMethod) : Value(tx.paymentMethod),
          receiptNumber: Value(tx.receiptNumber),
        ),
      );
    });

    if (performedBy != null) {
      await AuditService.log(
        db: _db,
        action: 'UPDATE',
        tableName: 'ledger_transactions',
        recordId: null,
        details: 'تعديل حركة مورد (${tx.origin})',
        oldValue: oldValues,
        newValue: {
          'id': tx.id,
          'amount': newAmount,
          'date': date.toIso8601String(),
          'paymentMethod': paymentMethod,
          'description': note,
        },
      );
    }
  }

  /// يحذف حركة مورد مستقلة (غير مرتبطة بفاتورة مشتريات مؤرشفة).
  Future<void> deleteSupplierTransaction({
    required String transactionId,
    String? performedBy,
  }) async {
    final tx = await _db.ledgerDao.getTransactionById(transactionId);
    if (tx == null) throw Exception('المعاملة غير موجودة');
    if (tx.entityType != 'Supplier') throw Exception('هذه ليست حركة مورد');

    final oldValues = {
      'id': tx.id,
      'amount': tx.credit > 0 ? tx.credit : tx.debit,
      'refId': tx.refId,
      'origin': tx.origin,
    };

    await _db.ledgerDao.deleteTransaction(transactionId);

    if (performedBy != null) {
      await AuditService.log(
        db: _db,
        action: 'DELETE',
        tableName: 'ledger_transactions',
        recordId: null,
        details: 'حذف حركة مورد (${tx.origin})',
        oldValue: oldValues,
        newValue: null,
      );
    }
  }

  /// إضافة حركة مورد جديدة (شراء/دفعة/تسوية/افتتاحي) بشكل ذري.
  Future<String> addSupplierTransaction({
    required String supplierId,
    required String description,
    required double amount,
    required String origin, // purchase | payment | opening | adjustment
    String? paymentMethod,
    String? receiptNumber,
    DateTime? date,
    String? performedBy,
  }) async {
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    if (!['purchase', 'payment', 'opening', 'adjustment', 'reversal'].contains(origin)) {
      throw Exception('origin غير صالح');
    }
    // For supplier: purchase/opening increase balance (credit), payment/reversal decrease (debit)
    final isCredit = origin == 'purchase' || origin == 'opening' || origin == 'adjustment';
    // But keep 'payment' as debit, 'reversal' as debit? Actually reversal could be either. Use credit for purchase-like.
    final debit = (origin == 'payment' || origin == 'reversal') ? amount : 0.0;
    final credit = (origin == 'purchase' || origin == 'opening' || origin == 'adjustment') ? amount : 0.0;

    final id = const Uuid().v4();
    await _db.ledgerDao.insertTransaction(
      LedgerTransactionsCompanion.insert(
        id: id,
        entityType: 'Supplier',
        refId: supplierId,
        date: date ?? DateTime.now(),
        description: description,
        debit: Value(debit),
        credit: Value(credit),
        origin: origin,
        paymentMethod: Value(paymentMethod),
        receiptNumber: Value(receiptNumber),
        createdAt: Value(DateTime.now()),
      ),
    );

    if (performedBy != null) {
      await AuditService.log(
        db: _db,
        action: 'INSERT',
        tableName: 'ledger_transactions',
        recordId: null,
        details: 'إضافة حركة مورد ($origin)',
        oldValue: null,
        newValue: {'id': id, 'supplierId': supplierId, 'amount': amount, 'origin': origin},
      );
    }
    return id;
  }
}
