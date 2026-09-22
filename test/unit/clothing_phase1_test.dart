import 'package:drift/drift.dart' hide Column, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/config/clothing_constants.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

void main() {
  group('Clothing Constants', () {
    test('standard clothing categories are well-defined', () {
      expect(ClothingConstants.defaultCategories, contains('رجالي'));
      expect(ClothingConstants.defaultCategories, contains('حريمي'));
      expect(ClothingConstants.defaultCategories, contains('أطفال أولاد'));
      expect(
        ClothingConstants.defaultCategories.length,
        greaterThanOrEqualTo(5),
      );
    });

    test('size presets contain expected sizes', () {
      expect(
        ClothingConstants.alphaSizes,
        containsAll(['S', 'M', 'L', 'XL', 'Free Size']),
      );
      expect(
        ClothingConstants.pantsSizes,
        containsAll(['28', '32', '36', '40']),
      );
      expect(
        ClothingConstants.shoeSizes,
        containsAll(['38', '40', '42', '44']),
      );
      expect(
        ClothingConstants.kidsSizes,
        containsAll(['0-3M', '1-2Y', '4-5Y']),
      );
    });

    test('color presets contain expected common colors', () {
      expect(
        ClothingConstants.colorNames,
        containsAll(['أسود', 'أبيض', 'كحلي', 'أحمر', 'رمادي']),
      );
    });
  });

  group('Clothing Product Database Operations (Schema v57)', () {
    late AppDatabase db;

    setUp(() {
      AppFlavor.initialize(Flavor.clothing);
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('schema version is at least 57 (current 58)', () {
      expect(db.schemaVersion, 58);
    });

    test('appFeatures.isClothing is true in clothing flavor', () {
      expect(AppFeatures.isClothing, isTrue);
      expect(AppFeatures.hasEmptyContainerTracking, isFalse);
    });

    test('can insert, read, and update product with size and color', () async {
      final productId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'تيشيرت بولو قطن - أسود - L',
          price: 280.0,
          quantity: 10,
          costPrice: const Value(160.0),
          category: const Value('رجالي'),
          unit: const Value('قطعة'),
          size: const Value('L'),
          color: const Value('أسود'),
        ),
      );

      expect(productId, greaterThan(0));

      final products = await db.productDao.getAllProducts();
      final inserted = products.firstWhere((p) => p.id == productId);

      expect(inserted.name, 'تيشيرت بولو قطن - أسود - L');
      expect(inserted.size, 'L');
      expect(inserted.color, 'أسود');
      expect(inserted.price, 280.0);
      expect(inserted.costPrice, 160.0);
      expect(inserted.category, 'رجالي');
      expect(inserted.barcode, isNotNull); // auto-generated barcode

      // Test updating size and color
      final updatedProduct = inserted.copyWith(
        size: const Value('XL'),
        color: const Value('كحلي'),
        price: 295.0,
      );

      await db.productDao.updateProduct(updatedProduct);

      final reloadedProducts = await db.productDao.getAllProducts();
      final reloaded = reloadedProducts.firstWhere((p) => p.id == productId);

      expect(reloaded.size, 'XL');
      expect(reloaded.color, 'كحلي');
      expect(reloaded.price, 295.0);
    });
  });
}
