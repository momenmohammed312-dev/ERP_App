import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/config/clothing_constants.dart';

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
}
