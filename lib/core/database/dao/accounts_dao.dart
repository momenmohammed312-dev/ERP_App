import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/accounts_table.dart';

part 'accounts_dao.g.dart';

@DriftAccessor(tables: [Accounts])
class AccountsDao extends DatabaseAccessor<AppDatabase> with _$AccountsDaoMixin {
  AccountsDao(super.db);

  Future<List<Account>> getAllAccounts() => select(accounts).get();

  Future<List<Account>> getActiveAccounts() =>
      (select(accounts)..where((a) => a.isActive.equals(true))).get();

  Future<Account?> getById(String id) =>
      (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<Account?> getByCode(String code) =>
      (select(accounts)..where((a) => a.code.equals(code))).getSingleOrNull();

  Future<List<Account>> getByType(String type) =>
      (select(accounts)..where((a) => a.type.equals(type))).get();

  Stream<List<Account>> watchAll() => select(accounts).watch();

  Future<int> insertAccount(AccountsCompanion entry) => into(accounts).insert(entry);

  Future<bool> updateAccount(Account account) => update(accounts).replace(account);

  /// System accounts cannot be deleted via UI — enforced here.
  Future<void> deleteAccount(String id) async {
    final acc = await getById(id);
    if (acc == null) return;
    if (acc.isSystem) throw Exception('لا يمكن حذف حساب نظام');
    await (delete(accounts)..where((a) => a.id.equals(id))).go();
  }
}
