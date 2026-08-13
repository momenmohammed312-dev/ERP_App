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

  group('CustomerDao duplicate name after soft delete', () {
    test('adding a customer whose name was soft-deleted succeeds', () async {
      // 1. Add a customer
      await database.customerDao.insertCustomer(
        CustomersCompanion.insert(id: 'c1', name: 'أحمد'),
      );
      // 2. Soft delete it (the app's deleteCustomer sets isActive = false)
      await database.customerDao.deleteCustomer('c1');

      // 3. Re-adding the same name should now succeed (deleted row is ignored)
      await database.customerDao.insertCustomer(
        CustomersCompanion.insert(id: 'c2', name: 'أحمد'),
      );

      final active = await database.customerDao.getActiveCustomerByName('أحمد');
      expect(active, isNotNull);
      expect(active!.id, 'c2');
      expect(active.isActive, isTrue);
    });

    test('adding a duplicate of an ACTIVE customer name is rejected', () async {
      await database.customerDao.insertCustomer(
        CustomersCompanion.insert(id: 'c1', name: 'محمد'),
      );

      expect(
        () => database.customerDao.insertCustomer(
          CustomersCompanion.insert(id: 'c2', name: 'محمد'),
        ),
        throwsA(
          predicate((e) => e.toString().contains('العميل موجود بالفعل')),
        ),
      );
    });

    test('soft-deleted customer is excluded from active list and search',
        () async {
      await database.customerDao.insertCustomer(
        CustomersCompanion.insert(id: 'c1', name: 'سارة'),
      );
      await database.customerDao.deleteCustomer('c1');

      final active = await database.customerDao.getAllActiveCustomers();
      expect(active.where((c) => c.name == 'سارة'), isEmpty);

      final searched = await database.customerDao.searchCustomers('سارة');
      expect(searched.where((c) => c.name == 'سارة'), isEmpty);
    });
  });
}
