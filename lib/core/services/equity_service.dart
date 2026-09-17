import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import 'accounting_service.dart';

class EquityService {
  final AppDatabase _db;
  EquityService(this._db);

  /// Creates a partner (admin only, caller must check permission).
  Future<String> createPartner({required String name, String? phone, double? ownershipPercentage}) async {
    final id = const Uuid().v4();
    await _db.equityDao.insertPartner(PartnersCompanion.insert(
      id: id,
      name: name,
      phone: Value(phone),
      ownershipPercentage: Value(ownershipPercentage),
    ));
    return id;
  }

  /// Records a capital contribution / opening capital. Posts journal: Debit Cash/Bank, Credit Capital (3000).
  Future<String> recordCapitalContribution({
    required String partnerId,
    required double amount,
    required DateTime date,
    String? description,
    String paymentMethod = 'cash', // cash -> 1000, else 1010
    String? createdBy,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    final partner = await _db.equityDao.getPartnerById(partnerId);
    if (partner == null) throw Exception('Partner not found');

    final txId = const Uuid().v4();
    final isOpening = description != null && description.contains('افتتاحي');

    return _db.transaction(() async {
      await _db.equityDao.insertEquityTransaction(EquityTransactionsCompanion.insert(
        id: txId,
        partnerId: partnerId,
        type: isOpening ? 'opening_capital' : 'capital_contribution',
        amount: amount,
        date: date,
        description: Value(description ?? 'مساهمة رأس مال ${partner.name}'),
      ));

      // Journal
      final accounting = AccountingService(_db);
      Future<String> accId(String code) async {
        final a = await _db.accountsDao.getByCode(code);
        if (a == null) throw Exception('Account $code not found');
        return a.id;
      }

      final cashOrBankId = await accId(paymentMethod == 'cash' ? '1000' : '1010');
      final capitalId = await accId('3000');
      final journalId = await accounting.postCapitalContribution(
        sourceId: txId,
        date: date,
        amount: amount,
        cashOrBankAccountId: cashOrBankId,
        capitalAccountId: capitalId,
        createdBy: createdBy,
      );

      await _db.equityDao.updateEquityTransaction(
        (await _db.equityDao.getEquityTransactionById(txId))!.copyWith(journalEntryId: Value(journalId)),
      );

      return txId;
    });
  }

  Future<String> recordWithdrawal({
    required String partnerId,
    required double amount,
    required DateTime date,
    String? description,
    String paymentMethod = 'cash',
    String? createdBy,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    final partner = await _db.equityDao.getPartnerById(partnerId);
    if (partner == null) throw Exception('Partner not found');

    final txId = const Uuid().v4();
    return _db.transaction(() async {
      await _db.equityDao.insertEquityTransaction(EquityTransactionsCompanion.insert(
        id: txId,
        partnerId: partnerId,
        type: 'withdrawal',
        amount: amount,
        date: date,
        description: Value(description ?? 'مسحوبات ${partner.name}'),
      ));

      final accounting = AccountingService(_db);
      Future<String> accId(String code) async {
        final a = await _db.accountsDao.getByCode(code);
        if (a == null) throw Exception('Account $code not found');
        return a.id;
      }

      final cashOrBankId = await accId(paymentMethod == 'cash' ? '1000' : '1010');
      final drawingsId = await accId('3100');
      final journalId = await accounting.postWithdrawal(
        sourceId: txId,
        date: date,
        amount: amount,
        drawingsAccountId: drawingsId,
        cashOrBankAccountId: cashOrBankId,
        createdBy: createdBy,
      );

      await _db.equityDao.updateEquityTransaction(
        (await _db.equityDao.getEquityTransactionById(txId))!.copyWith(journalEntryId: Value(journalId)),
      );

      return txId;
    });
  }

  /// Manual profit allocation (user-entered amount per partner, no auto-split).
  Future<String> recordProfitAllocation({
    required String partnerId,
    required double amount,
    required DateTime date,
    String? description,
    String? createdBy,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    final partner = await _db.equityDao.getPartnerById(partnerId);
    if (partner == null) throw Exception('Partner not found');

    final txId = const Uuid().v4();
    await _db.equityDao.insertEquityTransaction(EquityTransactionsCompanion.insert(
      id: txId,
      partnerId: partnerId,
      type: 'profit_allocation',
      amount: amount,
      date: date,
      description: Value(description ?? 'توزيع أرباح ${partner.name}'),
    ));
    // No automatic journal for profit allocation in Phase 6 manual mode — user can post via opening_balance if needed.
    // Optionally, a future phase could post: Debit Retained Earnings 3200, Credit Capital 3000.
    return txId;
  }
}
