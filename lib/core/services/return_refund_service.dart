import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// طرق الاسترداد المدعومة.
class RefundMethod {
  /// خرج كاش من الصندوق — لازم يتخصم من رصيد اليوم المتوقع.
  static const cash = 'cash';

  /// رصيد للعميل: بيانته بتقل وهو يصرفه وقت ما يحب. مالوش علاقة بالصندوق.
  static const creditBalance = 'credit_balance';

  /// نفس طريقة الدفع الأصلية (كارت/بنك).
  static const original = 'original';

  static const all = [cash, creditBalance, original];

  static bool isValid(String v) => all.contains(v);
}

/// نتيجة تنفيذ الاسترداد — الـUI بيستخدمها عشان يحدّث الشاشة.
class RefundResult {
  final int refundId;
  final double amount;
  final String method;
  final double returnOutstanding;

  RefundResult({
    required this.refundId,
    required this.amount,
    required this.method,
    required this.returnOutstanding,
  });
}

/// خدمة استرداد أموال المرتجع.
///
/// **[اللي كانت ناقصة]** قبل v78 كان المرتجع بيتعامل معاه كأنه "كله فلوس"
/// أو "مفيش فلوس خالص":
/// - العميل الآجل → credit في الـledger (صحيح، بس مفيش سجل للاسترداد)
/// - العميل النقدي → المخزون بيرجع والفلوس بتختفي، ولا قيد ولا أثر في
///   رصيد اليوم. يعني يوم الإغلاق بيقول الرصيد صح وانت ناقصك قيمة المرتجع.
///
/// الخدمة دي بتعمل الاسترداد كـ**حدث مستقل بتاريخه هو** (مش تعديل على
/// المرتجع الأصلي)، وكله جوه transaction واحدة.
///
/// التوقيع المحاسبي (نفس اصطلاح المشروع: العميل = debit يزيد الرصيد،
/// المورد = credit يزيد الرصيد):
/// - `cash`           → ledger `Cash` credit  → نقد خرج من الصندوق
/// - `credit_balance` → ledger `Customer` credit → دين العميل قل
/// - `original`       → ledger `Customer` credit → نفس أثر الرصيد، ومتسجل
///                      كطريقة مرجعية للمطابقة البنكية
class ReturnRefundService {
  final AppDatabase _db;
  ReturnRefundService(this._db);

  /// استرداد مبلغ من مرتجع — نقدي أو رصيد للعميل.
  ///
  /// يقبل استرداد **جزئي**: ممكن ترجع مرتجع 100 وتسترد 60 دلوقتي و40 بعدين.
  /// بيتقفل عند `refundedAmount + amount > totalAmount`.
  Future<RefundResult> refund({
    required int returnId,
    required double amount,
    required String method,
    String? referenceNumber,
    int? applyToInvoiceId,
    String? notes,
    required String processedBy,
  }) async {
    if (amount <= 0) throw Exception('قيمة الاسترداد لازم تكون أكبر من صفر');
    if (!RefundMethod.isValid(method)) {
      throw Exception('طريقة استرداد غير معروفة: $method');
    }

    return _db.transaction(() async {
      // ---------- 1) تحقق كامل قبل أي كتابة ----------
      final ret = await (_db.select(_db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .getSingleOrNull();
      if (ret == null) throw Exception('المرتجع غير موجود');
      if (ret.status == 'voided') throw Exception('لا يمكن الاسترداد من مرتجع ملغى');

      final invoice = await (_db.select(_db.invoices)
            ..where((t) => t.id.equals(ret.originalInvoiceId)))
          .getSingleOrNull();

      // رصيد للعميل أو نفس طريقة الدفع: لازم يكون في عميل حقيقي.
      final hasCreditCustomer = invoice?.customerId != null &&
          invoice!.customerId!.isNotEmpty &&
          invoice.customerId != 'cash';
      if ((method == RefundMethod.creditBalance || method == RefundMethod.original) &&
          !hasCreditCustomer) {
        throw Exception(
          'الاسترداد كرصيد يحتاج عميل مسجّل على الفاتورة — '
          'الفاتورة دي نقدية، استخدم "نقدي"',
        );
      }

      final alreadyRefunded =
          await _db.returnRefundsDao.getRefundedAmountForReturn(returnId);
      final remaining = ret.totalAmount - alreadyRefunded;
      if (remaining <= 0.01) {
        throw Exception('المرتجع ده متسترد بالكامل بالفعل');
      }
      if (amount > remaining + 0.01) {
        throw Exception(
          'قيمة الاسترداد (${amount.toStringAsFixed(2)}) أكبر من المتبقي '
          '(${remaining.toStringAsFixed(2)})',
        );
      }

      // ---------- 2) سطر الاسترداد ----------
      final now = DateTime.now();
      final refundId = await _db.into(_db.returnRefunds).insert(
        ReturnRefundsCompanion.insert(
          returnId: returnId,
          refundDate: now,
          amount: amount,
          method: method,
          referenceNumber: Value(referenceNumber),
          applyToInvoiceId: Value(applyToInvoiceId),
          notes: Value(notes),
          processedBy: Value(processedBy),
          syncId: Value(const Uuid().v4()),
          createdAt: Value(now),
        ),
      );

      // ---------- 3) القيد المحاسبي ----------
      await _postLedger(
        refundId: refundId,
        method: method,
        amount: amount,
        invoice: invoice,
        returnNumber: ret.returnNumber,
        invoiceNumber: invoice?.invoiceNumber,
        invoiceId: invoice?.id,
        date: now,
      );

      // ---------- 4) تحديث تجميعات المرتجع والفاتورة ----------
      final newRefunded = alreadyRefunded + amount;
      // 'credited' = رصيد للعميل، 'refunded' = فلوس فعلاً خرجت (كاش/كارت).
      final paidOutInCash =
          method == RefundMethod.cash || method == RefundMethod.original;
      final newSettlement = newRefunded >= ret.totalAmount - 0.01
          ? (paidOutInCash ? 'refunded' : 'credited')
          : 'partially_refunded';

      await (_db.update(_db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .write(
        SalesReturnsCompanion(
          refundedAmount: Value(newRefunded),
          settlementStatus: Value(newSettlement),
        ),
      );

      if (invoice != null && paidOutInCash) {
        await (_db.update(_db.invoices)..where((t) => t.id.equals(invoice.id)))
            .write(
          InvoicesCompanion(
            refundedAmount: Value(invoice.refundedAmount + amount),
          ),
        );
      }

      // ---------- 5) سجل مراجعة ----------
      await _audit(
        refundId: refundId,
        returnId: returnId,
        invoiceId: invoice?.id,
        amount: amount,
        method: method,
        processedBy: processedBy,
        newSettlement: newSettlement,
        remaining: (remaining - amount) < 0 ? 0.0 : remaining - amount,
      );

      final newOutstanding = remaining - amount;
      return RefundResult(
        refundId: refundId,
        amount: amount,
        method: method,
        returnOutstanding: newOutstanding < 0 ? 0.0 : newOutstanding,
      );
    });
  }

  /// القيد المحاسبي للاسترداد — **cash بس**.
  ///
  /// ⚠️ ليه بس الكاش؟
  /// `SalesReturnService.processPartialReturn` بيكتب من قبله قيد عكسي
  /// (`origin='reversal'`) للعميل الآجل لحظة تسجيل المرتجع. لو كتبنا هنا
  /// credit تاني للعميل عن نفس المبلغ، رصيده هينزل **مرتين** — وده بالظبط
  /// اللي الـtest كشفه. فالمسؤولية مقسومة:
  ///
  /// | المسار | الأثر المحاسبي |
  /// |---|---|
  /// | مرتجع عميل آجل | `Customer credit` بـ `origin='reversal'` (من الخدمة القديمة) |
  /// | مرتجع عميل نقدي | **مفيش** — ده كانت الثغرة |
  /// | استرداد **نقدي** | `Cash credit` بـ `origin='refund'` ← **الجديد، ده الفايدة** |
  /// | استرداد كرصيد/نفس الدفع | **سجل بس** — الرصيد اتظبط مع المرتجع خلاص |
  ///
  /// سجل `return_refunds` موجود في كل الحالات عشان متابعة التسوية والـaudit.
  Future<void> _postLedger({
    required int refundId,
    required String method,
    required double amount,
    required Invoice? invoice,
    required String returnNumber,
    required String? invoiceNumber,
    required int? invoiceId,
    required DateTime date,
  }) async {
    // الكاش والكارت = فلوس فعلاً خرجت من الشركة.
    final moneyLeftBuilding =
        method == RefundMethod.cash || method == RefundMethod.original;
    if (!moneyLeftBuilding) return;

    final label = invoiceNumber == null
        ? 'فاتورة ${invoiceId ?? '—'}'
        : 'فاتورة $invoiceNumber';

    await _db.ledgerDao.insertTransaction(
      LedgerTransactionsCompanion.insert(
        id: '${const Uuid().v4()}_retref_$refundId',
        entityType: 'Cash',
        refId: 'returns',
        date: date,
        description: 'استرداد مرتجع $returnNumber — $label',
        debit: const Value(0.0),
        credit: Value(amount),
        origin: 'refund',
        paymentMethod: Value(method),
        receiptNumber: Value('RREF$refundId'),
      ),
    );
  }

  Future<void> _audit({
    required int refundId,
    required int returnId,
    required int? invoiceId,
    required double amount,
    required String method,
    required String processedBy,
    required String newSettlement,
    required double remaining,
  }) async {
    try {
      await _db.auditDao.logAudit(
        action: 'REFUND',
        tableName: 'return_refunds',
        recordId: refundId,
        details: 'return=$returnId invoice=${invoiceId ?? '-'} '
            'amount=$amount method=$method by=$processedBy '
            'settlement=$newSettlement remaining=$remaining',
      );
    } catch (_) {
      // سجل المراجعة ماينفعش يوقف عملية مالية.
    }
  }

  /// استرداد كل المتبقي دفعة واحدة.
  Future<RefundResult> refundRemaining({
    required int returnId,
    required String method,
    String? referenceNumber,
    String? notes,
    required String processedBy,
  }) async {
    final outstanding = await _db.returnRefundsDao.getOutstandingForReturn(returnId);
    if (outstanding <= 0.01) throw Exception('مفيش مبلغ متبقّي للاسترداد');
    return refund(
      returnId: returnId,
      amount: outstanding,
      method: method,
      referenceNumber: referenceNumber,
      notes: notes,
      processedBy: processedBy,
    );
  }
}