import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../database/tables/journal_lines_table.dart';

/// Headless accounting core — the only place that knows how to turn a business event
/// into a balanced journal entry. Never opens its own transaction; caller must already
/// be inside db.transaction() (see §24 of the accounting plan).
class AccountingService {
  final AppDatabase _db;
  AccountingService(this._db);

  /// Low-level helper — inserts a balanced entry via JournalDao.
  /// All postX methods below delegate here.
  Future<String> _post({
    required String postingKey,
    required DateTime date,
    required String description,
    required String sourceType,
    required String sourceId,
    required List<JournalLinesCompanion> lines,
    String? createdBy,
  }) {
    return _db.journalDao.insertBalancedEntry(
      postingKey: postingKey,
      date: date,
      description: description,
      sourceType: sourceType,
      sourceId: sourceId,
      lines: lines,
      createdBy: createdBy,
    );
  }

  // ── Sales ──

  Future<String> postSale({
    required String sourceId,
    required DateTime date,
    required String description,
    required double revenueAmount,
    required String revenueAccountId,
    required String debitAccountId, // Cash/Bank (1000/1010) or AR (1100)
    String? createdBy,
  }) {
    // postingKey: sale:INV<id> — second call with same key is no-op (idempotency)
    return _post(
      postingKey: 'sale:INV$sourceId',
      date: date,
      description: description,
      sourceType: 'sale',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: debitAccountId, debit: Value(revenueAmount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: revenueAccountId, debit: const Value(0), credit: Value(revenueAmount)),
      ],
    );
  }

  Future<String> postSaleCogs({
    required String sourceId,
    required DateTime date,
    required double cogsAmount,
    required String cogsAccountId, // 5000
    required String inventoryAccountId, // 1200
    String? createdBy,
  }) {
    if (cogsAmount <= 0) throw ArgumentError('cogsAmount must be > 0');
    return _post(
      postingKey: 'sale_cogs:INV$sourceId',
      date: date,
      description: 'تكلفة بضاعة فاتورة $sourceId',
      sourceType: 'sale_cogs',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: cogsAccountId, debit: Value(cogsAmount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: inventoryAccountId, debit: const Value(0), credit: Value(cogsAmount)),
      ],
    );
  }

  Future<String> postCustomerPayment({
    required String sourceId,
    required DateTime date,
    required double amount,
    required String cashOrBankAccountId,
    required String arAccountId, // 1100
    String? createdBy,
  }) {
    return _post(
      postingKey: 'customer_payment:$sourceId',
      date: date,
      description: 'تحصيل عميل $sourceId',
      sourceType: 'customer_payment',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: cashOrBankAccountId, debit: Value(amount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: arAccountId, debit: const Value(0), credit: Value(amount)),
      ],
    );
  }

  // ── Purchases ──

  Future<String> postPurchase({
    required String sourceId,
    required DateTime date,
    required double totalAmount,
    required String inventoryAccountId, // 1200
    required String creditAccountId, // 1000 Cash or 2000 AP
    String description = 'مشتريات',
    String? createdBy,
  }) {
    return _post(
      postingKey: 'purchase:PUR$sourceId',
      date: date,
      description: description,
      sourceType: 'purchase',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: inventoryAccountId, debit: Value(totalAmount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: creditAccountId, debit: const Value(0), credit: Value(totalAmount)),
      ],
    );
  }

  // ── Expenses ──

  Future<String> postExpense({
    required String sourceId,
    required DateTime date,
    required double amount,
    required String expenseAccountId, // 5100
    required String creditAccountId, // 1000/1010 or 2000
    String description = 'مصروف',
    String? createdBy,
  }) {
    return _post(
      postingKey: 'expense:$sourceId',
      date: date,
      description: description,
      sourceType: 'expense',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: expenseAccountId, debit: Value(amount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: creditAccountId, debit: const Value(0), credit: Value(amount)),
      ],
    );
  }

  // ── Sales returns ──

  Future<String> postSalesReturn({
    required String sourceId,
    required DateTime date,
    required double amount,
    required String salesReturnsAccountId, // 4100
    required String debitAccountId, // 1100 or 1000
    String? createdBy,
  }) {
    return _post(
      postingKey: 'sale_return:RET$sourceId',
      date: date,
      description: 'مرتجع مبيعات $sourceId',
      sourceType: 'sale_return',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: salesReturnsAccountId, debit: Value(amount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: debitAccountId, debit: const Value(0), credit: Value(amount)),
      ],
    );
  }

  // ── Equity ──

  Future<String> postCapitalContribution({
    required String sourceId,
    required DateTime date,
    required double amount,
    required String cashOrBankAccountId,
    required String capitalAccountId, // 3000
    String? createdBy,
  }) {
    return _post(
      postingKey: 'equity:$sourceId',
      date: date,
      description: 'مساهمة رأس مال $sourceId',
      sourceType: 'capital',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: cashOrBankAccountId, debit: Value(amount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: capitalAccountId, debit: const Value(0), credit: Value(amount)),
      ],
    );
  }

  Future<String> postWithdrawal({
    required String sourceId,
    required DateTime date,
    required double amount,
    required String drawingsAccountId, // 3100
    required String cashOrBankAccountId,
    String? createdBy,
  }) {
    return _post(
      postingKey: 'equity:$sourceId',
      date: date,
      description: 'مسحوبات $sourceId',
      sourceType: 'withdrawal',
      sourceId: sourceId,
      createdBy: createdBy,
      lines: [
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: drawingsAccountId, debit: Value(amount), credit: const Value(0)),
        JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: cashOrBankAccountId, debit: const Value(0), credit: Value(amount)),
      ],
    );
  }
}
