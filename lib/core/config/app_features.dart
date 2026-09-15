import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Compile-time feature flags derived from the active [Flavor].
class AppFeatures {
  AppFeatures._();

  static Flavor get flavor => AppFlavor.current;

  /// true only for the clothing distribution (توزيع ملابس) flavor.
  static bool get isClothingDistribution => flavor == Flavor.clothing;

  static bool get hasShipmentTracking => flavor == Flavor.vegetable;

  static bool get hasEmptyContainerTracking => flavor == Flavor.vegetable;

  static bool get hasCommissionPricing => flavor == Flavor.vegetable;

  /// Vegetable flavor day-close settlement view (net cash, variance,
  /// settlement entry) inside CloseDayDialog.
  static bool get hasDaySettlement => flavor == Flavor.vegetable;

  /// Manufacturing / BOM / Material management (Phase 1+).
  /// Disabled for clothing — they only need invoices, purchases, reports.
  static bool get hasManufacturing =>
      flavor != Flavor.clothing;

  /// Staff / attendance management — disabled for clothing distribution.
  static bool get hasStaffManagement =>
      flavor != Flavor.clothing;

  /// Damaged items tracking — disabled for clothing distribution.
  static bool get hasDamagedItems =>
      flavor != Flavor.clothing;

  /// Purchase flow with inline product creation & markup pricing.
  /// Enabled for clothing, useful for all flavors but gated initially.
  static bool get hasInlinePurchaseProductCreation =>
      flavor == Flavor.clothing;

  /// Equity and partners screen — disabled for clothing distribution.
  static bool get hasEquity => flavor != Flavor.clothing;

  /// Accounting Hub screen — disabled for clothing distribution.
  static bool get hasAccountingHub => flavor != Flavor.clothing;

  /// Backup screen launcher — disabled for clothing distribution.
  static bool get hasBackupLauncher => flavor != Flavor.clothing;

  /// Multi-device sync (Supabase outbox queue & periodic sync).
  /// Disabled for clothing distribution to keep it completely isolated and offline.
  static bool get hasMultiDeviceSync => flavor != Flavor.clothing;
}
