import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          return '.';
        },
      );

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> addCustomer(String id, String name, {bool isActive = true}) async {
    await database.into(database.customers).insert(
      CustomersCompanion.insert(
        id: id,
        name: name,
        isActive: Value(isActive),
      ),
    );
  }

  Future<void> addSupplier(
    String id,
    String name, {
    String status = 'Active',
  }) async {
    await database.into(database.suppliers).insert(
      SuppliersCompanion.insert(
        id: id,
        name: name,
        status: Value(status),
      ),
    );
  }

  Future<void> addTx(
    String id,
    String entityType,
    String refId, {
    double debit = 0.0,
    double credit = 0.0,
  }) async {
    await database.ledgerDao.insertTransaction(
      LedgerTransactionsCompanion.insert(
        id: id,
        entityType: entityType,
        refId: refId,
        date: DateTime.now(),
        description: 'tx',
        debit: Value(debit),
        credit: Value(credit),
        origin: 'sale',
      ),
    );
  }

  group('getAllCustomerBalances (أرصدة الحسابات الموحدة)', () {
    test('soft-deleted customers are excluded (only active rows shown)',
        () async {
      // Original customer with movements, then soft-deleted.
      await addCustomer('c1', 'أحمد');
      await addTx('tx1', 'Customer', 'c1', debit: 100.0);
      await database.customerDao.deleteCustomer('c1'); // isActive=false

      // Active customer with the same name (created after soft delete).
      await addCustomer('c2', 'أحمد');
      await addTx('tx2', 'Customer', 'c2', debit: 50.0);

      final balances = await database.ledgerDao.getAllCustomerBalances();
      final ahmed = balances.where((b) => b['name'] == 'أحمد').toList();

      expect(ahmed.length, 1, reason: 'نسخة واحدة فقط لكل اسم');
      expect(ahmed.single['id'], 'c2');
      expect((ahmed.single['balance'] as num?)?.toDouble(), 50.0);
    });

    test('active customers still appear with correct balance', () async {
      await addCustomer('c1', 'محمد');
      await addTx('tx1', 'Customer', 'c1', debit: 100.0, credit: 30.0);

      final balances = await database.ledgerDao.getAllCustomerBalances();
      final mohammed = balances.where((b) => b['name'] == 'محمد').single;

      expect(mohammed['id'], 'c1');
      expect((mohammed['balance'] as num?)?.toDouble(), 70.0);
    });
  });

  group('getAllSupplierBalances', () {
    test('Inactive suppliers are excluded', () async {
      await addSupplier('s1', 'مورد قديم', status: 'Inactive');
      await addSupplier('s2', 'مورد نشط');
      await addTx('tx1', 'Supplier', 's2', credit: 200.0);

      final balances = await database.ledgerDao.getAllSupplierBalances();
      expect(balances.length, 1);
      expect(balances.single['id'], 's2');
    });
  });

  group('إجمالي مديونيات العملاء', () {
    test('getTotalReceivables ignores soft-deleted customers', () async {
      // Soft-deleted debtor with outstanding balance.
      await addCustomer('c1', 'مدين قديم');
      await addTx('tx1', 'Customer', 'c1', debit: 500.0);
      await database.customerDao.deleteCustomer('c1');

      // Active debtor.
      await addCustomer('c2', 'مدين نشط');
      await addTx('tx2', 'Customer', 'c2', debit: 300.0);

      final total = await database.ledgerDao.getTotalReceivables();
      expect(total, 300.0);
    });

    test('watchTotalReceivables ignores soft-deleted customers', () async {
      await addCustomer('c1', 'مدين قديم');
      await addTx('tx1', 'Customer', 'c1', debit: 500.0);
      await database.customerDao.deleteCustomer('c1');

      await addCustomer('c2', 'مدين نشط');
      await addTx('tx2', 'Customer', 'c2', debit: 300.0);

      final total = await database.ledgerDao
          .watchTotalReceivables()
          .first
          .timeout(const Duration(seconds: 5));
      expect(total, 300.0);
    });
  });
}