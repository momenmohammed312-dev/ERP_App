import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';

void main() {
  group('AppFlavor', () {
    test('parse maps known flavor strings', () {
      expect(AppFlavor.parse('base'), Flavor.base);
      expect(AppFlavor.parse('vegetable'), Flavor.vegetable);
      expect(AppFlavor.parse('veg'), Flavor.vegetable);
      expect(AppFlavor.parse('clothing'), Flavor.clothing);
      expect(AppFlavor.parse('all'), Flavor.all);
      expect(AppFlavor.parse('unknown'), Flavor.base);
    });

    test('databaseName is flavor-specific', () {
      AppFlavor.initialize(Flavor.base);
      expect(AppFlavor.databaseName, 'pos_offline_desktop_database');

      AppFlavor.initialize(Flavor.vegetable);
      expect(AppFlavor.databaseName, 'pos_vegetable');

      AppFlavor.initialize(Flavor.all);
      expect(AppFlavor.databaseName, 'pos_offline_desktop_database');
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

    test('all flags are enabled for all flavor', () {
      AppFlavor.initialize(Flavor.all);
      expect(AppFeatures.enableAllFeatures, isTrue);
      expect(AppFeatures.hasProductVariants, isTrue);
      expect(AppFeatures.hasShipmentTracking, isTrue);
      expect(AppFeatures.hasEmptyContainerTracking, isTrue);
      expect(AppFeatures.hasCommissionPricing, isTrue);
      expect(AppFeatures.hasDaySettlement, isTrue);
      expect(AppFeatures.hasStaffModule, isTrue);
      expect(AppFeatures.hasDamagedModule, isTrue);
      expect(AppFeatures.hasCustodyModule, isTrue);
      expect(AppFeatures.hasSuppliersModule, isTrue);
      expect(AppFeatures.hasManufacturing, isTrue);
      expect(PlatformUtils.hidesStaffFeaturesOnMobile, isFalse);
    });
  });
}
