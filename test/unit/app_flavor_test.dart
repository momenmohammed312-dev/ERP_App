import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';

void main() {
  group('AppFlavor', () {
    test('parse maps known flavor strings', () {
      expect(AppFlavor.parse('base'), Flavor.base);
      expect(AppFlavor.parse('vegetable'), Flavor.vegetable);
      expect(AppFlavor.parse('veg'), Flavor.vegetable);
      expect(AppFlavor.parse('clothing'), Flavor.clothing);
      expect(AppFlavor.parse('unknown'), Flavor.base);
    });

    test('databaseName is flavor-specific', () {
      AppFlavor.initialize(Flavor.base);
      expect(AppFlavor.databaseName, 'pos_offline_desktop_database');

      AppFlavor.initialize(Flavor.vegetable);
      expect(AppFlavor.databaseName, 'pos_vegetable');
    });
  });

  group('AppFeatures', () {
    test('vegetable-only flags are enabled for vegetable flavor', () {
      AppFlavor.initialize(Flavor.vegetable);
      expect(AppFeatures.hasShipmentTracking, isTrue);
      expect(AppFeatures.hasEmptyContainerTracking, isTrue);
      expect(AppFeatures.hasCommissionPricing, isTrue);
    });

    test('vegetable-only flags are disabled for base flavor', () {
      AppFlavor.initialize(Flavor.base);
      expect(AppFeatures.hasShipmentTracking, isFalse);
      expect(AppFeatures.hasEmptyContainerTracking, isFalse);
      expect(AppFeatures.hasCommissionPricing, isFalse);
    });
  });
}
