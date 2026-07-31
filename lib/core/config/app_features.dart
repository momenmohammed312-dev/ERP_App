import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Compile-time feature flags derived from the active [Flavor].
class AppFeatures {
  AppFeatures._();

  static Flavor get flavor => AppFlavor.current;

  static bool get hasShipmentTracking => flavor == Flavor.vegetable;

  static bool get hasEmptyContainerTracking => flavor == Flavor.vegetable;

  static bool get hasCommissionPricing => flavor == Flavor.vegetable;
}
