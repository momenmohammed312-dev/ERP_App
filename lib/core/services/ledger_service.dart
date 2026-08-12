import 'package:drift/drift.dart';
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
}
