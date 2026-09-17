import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../tables/ledger_transactions_table.dart';
import '../app_database.dart';

part 'ledger_dao.g.dart';

@DriftAccessor(tables: [LedgerTransactions])
class LedgerDao extends DatabaseAccessor<AppDatabase> with _$LedgerDaoMixin {
  LedgerDao(super.db);

  Future<List<LedgerTransaction>> getAllTransactions() =>
      select(ledgerTransactions).get();

  Future<List<LedgerTransaction>> getRecentTransactions(int limit) =>
      (select(ledgerTransactions)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            ])
            ..limit(limit))
          .get();

  Future<List<LedgerTransaction>> getTransactionsByEntity(
    String entityType,
    String refId,
  ) =>
      (select(ledgerTransactions)
            ..where(
              (tbl) =>
                  tbl.entityType.equals(entityType) & tbl.refId.equals(refId),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
            ]))
          .get();

  Future<List<LedgerTransaction>> getTransactionsByDateRange(
    String entityType,
    String refId,
    DateTime from,
    DateTime to,
  ) =>
      (select(ledgerTransactions)
            ..where(
              (tbl) =>
                  tbl.entityType.equals(entityType) &
                  tbl.refId.equals(refId) &
                  tbl.date.isBetweenValues(from, to),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
            ]))
          .get();

  Future<List<LedgerTransaction>> getCustomerTransactionsByDateRange(
    String customerId,
    DateTime from,
    DateTime to,
  ) => getTransactionsByDateRange('Customer', customerId, from, to);

  Future<List<LedgerTransaction>> getAllTransactionsByDateRange(
    DateTime from,
    DateTime to,
  ) =>
      (select(ledgerTransactions)
            ..where((tbl) => tbl.date.isBetweenValues(from, to))
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
            ]))
          .get();

  Future<LedgerTransaction> insertTransaction(
    LedgerTransactionsCompanion transaction,
  ) async {
    final id = transaction.id.present
        ? transaction.id.value
        : const Uuid().v4();
    final transactionWithId = transaction.copyWith(id: Value(id));
    await into(ledgerTransactions).insert(transactionWithId);
    return await getTransactionById(id) ??
        (throw Exception('Failed to insert transaction'));
  }

  Future<LedgerTransaction?> getTransactionById(String id) => (select(
    ledgerTransactions,
  )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  /// Update an existing ledger transaction by its primary key (id).
  Future<int> updateTransaction(LedgerTransactionsCompanion transaction) {
    return (update(ledgerTransactions)
          ..where((tbl) => tbl.id.equals(transaction.id.value)))
        .write(transaction);
  }

  /// Delete a ledger transaction by its primary key (id).
  Future<int> deleteTransaction(String id) =>
      (delete(ledgerTransactions)..where((tbl) => tbl.id.equals(id))).go();

  /// Fetch all ledger transactions that share a given receipt number
  /// (e.g. all rows linked to invoice 'INV123').
  Future<List<LedgerTransaction>> getTransactionsByReceiptNumber(
    String receiptNumber,
  ) =>
      (select(ledgerTransactions)
            ..where((tbl) => tbl.receiptNumber.equals(receiptNumber)))
          .get();

  /// Delete every ledger transaction linked to a receipt number.
  /// Used to fully reverse an invoice's impact (sale + payment + commission)
  /// before re-applying the edited version. Wrapped in a caller transaction.
  Future<int> deleteTransactionsByReceiptNumber(String receiptNumber) =>
      (delete(ledgerTransactions)
            ..where((tbl) => tbl.receiptNumber.equals(receiptNumber)))
          .go();

  Future<double> getRunningBalance(
    String entityType,
    String refId, {
    DateTime? upToDate,
  }) async {
    double openingBalance = 0.0;
    if (entityType == 'Customer') {
      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(refId))).getSingleOrNull();
      openingBalance = customer?.openingBalance ?? 0.0;
    } else if (entityType == 'Supplier') {
      final supplier = await (db.select(
        db.suppliers,
      )..where((t) => t.id.equals(refId))).getSingleOrNull();
      openingBalance = supplier?.openingBalance ?? 0.0;
    }

    final query = selectOnly(ledgerTransactions)
      ..addColumns([ledgerTransactions.debit, ledgerTransactions.credit])
      ..where(
        ledgerTransactions.entityType.equals(entityType) &
            ledgerTransactions.refId.equals(refId),
      );

    if (upToDate != null) {
      query.where(ledgerTransactions.date.isSmallerOrEqualValue(upToDate));
    }

    final result = await query.get();
    double total = openingBalance;
    for (final row in result) {
      final debit = row.read(ledgerTransactions.debit) ?? 0.0;
      final credit = row.read(ledgerTransactions.credit) ?? 0.0;
      if (entityType == 'Supplier') {
        total += credit - debit;
      } else {
        total += debit - credit;
      }
    }
    return total;
  }

  Stream<double> watchCurrentBalance() {
    return (select(ledgerTransactions)).watch().map((transactions) {
      double total = 0.0;
      for (final transaction in transactions) {
        total += transaction.debit - transaction.credit;
      }
      return total;
    });
  }

  Stream<List<LedgerTransaction>> watchAllTransactions() {
    return (select(ledgerTransactions)..orderBy([
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Future<List<LedgerTransactionWithBalance>> getTransactionsWithRunningBalance(
    String entityType,
    String refId,
    DateTime from,
    DateTime to,
  ) async {
    final transactions = await getTransactionsByDateRange(
      entityType,
      refId,
      from,
      to,
    );

    final result = <LedgerTransactionWithBalance>[];
    double runningBalance = 0.0;

    // Get opening balance before the period
    if (from != DateTime(1970)) {
      runningBalance = await getRunningBalance(
        entityType,
        refId,
        upToDate: from.subtract(const Duration(seconds: 1)),
      );
    }

    for (final transaction in transactions) {
      if (entityType == 'Supplier') {
        runningBalance += (transaction.credit - transaction.debit);
      } else {
        runningBalance += (transaction.debit - transaction.credit);
      }
      result.add(
        LedgerTransactionWithBalance(
          transaction: transaction,
          runningBalance: runningBalance,
        ),
      );
    }

    return result;
  }

  Future<int> lockTransactionsForDay(DateTime date) {
    final lockBatch =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return (update(ledgerTransactions)
          ..where((tbl) => tbl.date.equals(date) & tbl.lockBatch.isNull()))
        .write(LedgerTransactionsCompanion(lockBatch: Value(lockBatch)));
  }

  Future<bool> isDayLocked(DateTime date) {
    final lockBatch =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return (selectOnly(ledgerTransactions)
          ..addColumns([ledgerTransactions.id])
          ..where(ledgerTransactions.lockBatch.equals(lockBatch)))
        .get()
        .then((result) => result.isNotEmpty);
  }

  Future<double> getCustomerBalance(String customerId) async {
    final customer = await (db.select(
      db.customers,
    )..where((t) => t.id.equals(customerId))).getSingleOrNull();
    final openingBalance = customer?.openingBalance ?? 0.0;

    final transactions =
        await (select(ledgerTransactions)..where(
              (tbl) =>
                  tbl.entityType.equals('Customer') &
                  tbl.refId.equals(customerId),
            ))
            .get();

    return transactions.fold<double>(openingBalance, (sum, transaction) {
      return sum + transaction.debit - transaction.credit;
    });
  }

  Future<double> getSupplierBalance(String supplierId) async {
    final supplier = await (db.select(
      db.suppliers,
    )..where((t) => t.id.equals(supplierId))).getSingleOrNull();
    final openingBalance = supplier?.openingBalance ?? 0.0;

    final transactions =
        await (select(ledgerTransactions)..where(
              (tbl) =>
                  tbl.entityType.equals('Supplier') &
                  tbl.refId.equals(supplierId),
            ))
            .get();

    return transactions.fold<double>(openingBalance, (sum, transaction) {
      return sum + transaction.credit - transaction.debit;
    });
  }

  /// إجمالي الرصيد المستحق للموردين عبر كل الفترات (شحنات عمولة + مشتريات).
  ///
  /// القاعدة القانونية (D8/D11): رصيد المورد = opening + Σ(credit − debit)
  /// (المشتريات/العمولة دائن يزيد المستحق، والمدفوعات مدين ينقصه — نفس
  /// [getSupplierBalance] و [getAllSupplierBalances] و [getRunningBalance]
  /// و `SupplierDao.getSupplierBalance`/`watchTotalSuppliersDues`).
  /// كان هنا `SUM(debit − credit)` (معكوس) — إصلاح Agent 4.
  /// يستخدم في تسوية نهاية اليوم للمعرض فقط — عرض فقط.
  Future<double> getSupplierOutstandingBalance() async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(credit - debit), 0) as total FROM ledger_transactions '
      "WHERE entity_type = 'Supplier'",
      readsFrom: {ledgerTransactions},
    ).getSingle();

    return row.read<double>('total');
  }

  Stream<double> watchTotalReceivables() {
    return customSelect(
      'SELECT SUM(balance) as total FROM ('
      '  SELECT c.opening_balance + SUM(COALESCE(l.debit, 0) - COALESCE(l.credit, 0)) as balance '
      '  FROM customers c '
      '  LEFT JOIN ledger_transactions l ON l.ref_id = c.id AND l.entity_type = \'Customer\' '
      '  WHERE c.is_active = 1 '
      '  GROUP BY c.id'
      ') WHERE balance > 0',
      readsFrom: {db.customers, db.ledgerTransactions},
    ).watchSingle().map((row) => row.readNullable<double>('total') ?? 0.0);
  }

  /// إجمالي مديونيات العملاء المستحقة (آجل) — نفس حساب [watchTotalReceivables]
  /// لكن كـ Future لواحد-shot (مطابق لنمط تحميل الـDashboard).
  Future<double> getTotalReceivables() async {
    final row = await customSelect(
      'SELECT SUM(balance) as total FROM ('
      '  SELECT c.opening_balance + SUM(COALESCE(l.debit, 0) - COALESCE(l.credit, 0)) as balance '
      '  FROM customers c '
      '  LEFT JOIN ledger_transactions l ON l.ref_id = c.id AND l.entity_type = \'Customer\' '
      '  WHERE c.is_active = 1 '
      '  GROUP BY c.id'
      ') WHERE balance > 0',
      readsFrom: {db.customers, db.ledgerTransactions},
    ).getSingle();
    return row.readNullable<double>('total') ?? 0.0;
  }

  /// المستحق للموردين من شحنات العمولة — مجموع (credit − debit) لكل
  /// `LedgerTransactions` فيها `origin` بيع (`'sale'` للمسار الحي، `'import'`
  /// لمستورد سوق الخضار) و `entityType = 'Supplier'`.
  ///
  /// القاعدة القانونية (D8): العمولة payable = دائن (credit) بصافي المستحق
  /// (sell − commission). كان هنا `SUM(debit − credit)` (معكوس) — إصلاح Agent 4.
  Future<double> getSupplierCommissionDue() async {
    final rows = await customSelect(
      'SELECT COALESCE(SUM(credit - debit), 0) as total '
      "FROM ledger_transactions WHERE origin IN ('sale', 'import') AND entity_type = 'Supplier'",
      readsFrom: {ledgerTransactions},
    ).get();
    return (rows.first.data['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getAllCustomerBalances() async {
    final rows = await customSelect(
      'SELECT c.id, c.name, c.phone, (c.opening_balance + SUM(COALESCE(l.debit, 0) - COALESCE(l.credit, 0))) as balance '
      'FROM customers c '
      'LEFT JOIN ledger_transactions l ON l.ref_id = c.id AND l.entity_type = \'Customer\' '
      'WHERE c.is_active = 1 '
      'GROUP BY c.id '
      'ORDER BY balance DESC',
      readsFrom: {db.customers, db.ledgerTransactions},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSupplierBalances() async {
    final rows = await customSelect(
      'SELECT s.id, s.name, s.phone, (s.opening_balance + SUM(COALESCE(l.credit, 0) - COALESCE(l.debit, 0))) as balance '
      'FROM suppliers s '
      'LEFT JOIN ledger_transactions l ON l.ref_id = s.id AND l.entity_type = \'Supplier\' '
      "WHERE s.status = 'Active' "
      'GROUP BY s.id '
      'ORDER BY balance DESC',
      readsFrom: {db.suppliers, db.ledgerTransactions},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  /// صفوف الدفع (`origin = 'payment'`) المرتبطة بإيصال فاتورة (`'INV<id>'`).
  /// تُستخدم لحارس الدفع المزدوج (D3) وللحفاظ على history المدفوعات في
  /// التعديل/الإلغاء (لا تُعكس ولا تُحذف — النقدية المستلمة تبقى).
  Future<List<LedgerTransaction>> getPaymentsForReceipt(
    String receiptNumber,
  ) =>
      (select(ledgerTransactions)
            ..where(
              (tbl) =>
                  tbl.receiptNumber.equals(receiptNumber) &
                  tbl.origin.equals('payment'),
            ))
          .get();

  /// كاشف دفعات مكررة تشخيصي (D3): هل توجد دفعة بنفس المبلغ على نفس الإيصال
  /// داخل نافذة [window] حول [around]؟ محفوظة للتشخيص فقط — لا يستخدمها الكاتب
  /// الموحّد (الدليل: كبتت دفعات FIFO مشروعة متساوية متتالية؛ الحماية الآن عبر
  /// حارس التجاوز + مفاتيح اليومية الفريدة، والـdouble-tap على الـUI).
  Future<bool> hasDuplicatePayment({
    required String receiptNumber,
    required double amount,
    required DateTime around,
    Duration window = const Duration(seconds: 30),
  }) async {
    final from = around.subtract(window);
    final to = around.add(window);
    final rows =
        await (select(ledgerTransactions)
              ..where(
                (tbl) =>
                    tbl.receiptNumber.equals(receiptNumber) &
                    tbl.origin.equals('payment') &
                    tbl.credit.equals(amount) &
                    tbl.date.isBetweenValues(from, to),
              ))
            .get();
    return rows.isNotEmpty;
  }

  /// يعكس كل صفوف إيصال (`receiptNumber`) بصفوف عكسية (mirror) — debit↔credit —
  /// بنفس الكيان والمرجع، `origin = 'reversal'`، وإيصال [reversalReceipt]
  /// (مثال `'REV-INV<id>'`) حتى لا تختلط مع الأصل في حذف/استعلام الإيصال.
  ///
  /// قاعدة التدقيق (D4/D5): دفتر الأستاذ append-only — لا حذف فيزيائي لتاريخ
  /// مرحّل؛ العكس يحفظ الأصل + القيد العكسي معًا. يعمل داخل transaction
  /// المستدعي (لا يفتح transaction خاصة). يرجع الصفوف العكسية المُدخلة.
  ///
  /// [onlyOrigins] لتقييد العكس (مثال `{'sale'}` في الـvoid لإبقاء المدفوعات
  /// كـhistory — قرار D5: النقدية المستلمة لا تُعكس ضمنيًا، الاسترداد حركة
  /// صريحة منفصلة).
  Future<List<LedgerTransaction>> reverseTransactionsByReceipt({
    required String receiptNumber,
    required String reversalReceipt,
    Set<String>? onlyOrigins,
    String descriptionPrefix = 'عكس',
  }) async {
    final originals = await getTransactionsByReceiptNumber(receiptNumber);
    final targets = onlyOrigins == null
        ? originals
        : originals.where((t) => onlyOrigins.contains(t.origin)).toList();
    final now = DateTime.now();
    final inserted = <LedgerTransaction>[];
    for (final t in targets) {
      // لا تعكس صفًا عكسيًا سابقًا — يمنع التضاعف في void/edit متكرر.
      if (t.origin == 'reversal') continue;
      final row = await insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${const Uuid().v4()}_rev',
          entityType: t.entityType,
          refId: t.refId,
          date: now,
          description: '$descriptionPrefix: ${t.description}',
          debit: Value(t.credit),
          credit: Value(t.debit),
          origin: 'reversal',
          paymentMethod: Value(t.paymentMethod),
          receiptNumber: Value(reversalReceipt),
        ),
      );
      inserted.add(row);
    }
    return inserted;
  }
}

class LedgerTransactionWithBalance {
  final LedgerTransaction transaction;
  final double runningBalance;

  LedgerTransactionWithBalance({
    required this.transaction,
    required this.runningBalance,
  });
}
