import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('ProductDao barcode search', () {
    test('searchProducts finds a product by its barcode', () async {
      await database.productDao.insertProduct(
        ProductsCompanion.insert(name: 'طماطم', quantity: 50, price: 20),
      );
      await database.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'خيار',
          quantity: 30,
          price: 15,
          barcode: const Value('10000002'),
        ),
      );

      final results = await database.productDao.searchProducts('10000002');
      expect(results.length, 1);
      expect(results.single.name, 'خيار');
    });

    test('filterProducts finds a product by its barcode', () async {
      await database.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'طماطم',
          quantity: 50,
          price: 20,
          barcode: const Value('30000001'),
        ),
      );
      await database.productDao.insertProduct(
        ProductsCompanion.insert(name: 'خيار', quantity: 30, price: 15),
      );

      final results = await database.productDao.filterProducts(
        searchQuery: '30000001',
      );
      expect(results.length, 1);
      expect(results.single.name, 'طماطم');
    });

    test('getProductByBarcode returns the exact product', () async {
      await database.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'جزر',
          quantity: 40,
          price: 10,
          barcode: const Value('90000009'),
        ),
      );

      final product = await database.productDao.getProductByBarcode('90000009');
      expect(product, isNotNull);
      expect(product!.name, 'جزر');
    });

    test('insert without barcode auto-generates and persists one', () async {
      final id = await database.productDao.insertProduct(
        ProductsCompanion.insert(name: 'طماطم', quantity: 50, price: 20),
      );

      // نفس معادلة صفحة الملصقات: 10000000 + معرف المنتج
      final generated = await database.productDao.getProductById(id);
      expect(generated, isNotNull);
      expect(generated!.barcode, '${10000000 + id}');

      // يجب أن يظهر في البحث بنفس الكود فورًا (بعد الفورم مباشرة)
      final results = await database.productDao.searchProducts('$id');
      expect(results.any((p) => p.id == id), isTrue);

      final byCode = await database.productDao.getProductByBarcode('${10000000 + id}');
      expect(byCode, isNotNull);
      expect(byCode!.id, id);
    });

    test('insert with explicit barcode keeps it unchanged', () async {
      final id = await database.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'خيار',
          quantity: 30,
          price: 15,
          barcode: const Value('ABC-123'),
        ),
      );

      final product = await database.productDao.getProductById(id);
      expect(product!.barcode, 'ABC-123');
    });
  });
}
