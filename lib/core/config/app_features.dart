import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Compile-time feature flags derived from the active [Flavor].
class AppFeatures {
  AppFeatures._();

  static Flavor get flavor => AppFlavor.current;

  static bool get hasShipmentTracking => flavor == Flavor.vegetable;

  static bool get hasEmptyContainerTracking => flavor == Flavor.vegetable;

  static bool get hasCommissionPricing => flavor == Flavor.vegetable;

  /// Vegetable flavor day-close settlement view (net cash, variance,
  /// settlement entry) inside CloseDayDialog.
  static bool get hasDaySettlement => flavor == Flavor.vegetable;

  /// Staff module (employees tab + launcher). Hidden in the base build by
  /// client agreement (invoices/customers/suppliers/reports only); other
  /// flavors keep it. Single source of truth — no scattered flavor ifs.
  static bool get hasStaffModule => flavor != Flavor.base;

  /// Damaged-goods module (launcher button). Same agreement as staff.
  static bool get hasDamagedModule => flavor != Flavor.base;
}
