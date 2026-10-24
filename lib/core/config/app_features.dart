import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Compile-time feature flags derived from the active [Flavor].
class AppFeatures {
  AppFeatures._();

  static Flavor get flavor =>
      AppFlavor.isInitialized ? AppFlavor.current : AppFlavor.fromEnvironment();

  /// Product variants (الألوان والمقاسات والأصناف المتعددة).
  /// مفعلة في التطبيق الأساسي والتجارة العامة ونكهة الملابس، ومعطلة فقط في سوق الخضار.
  static bool? hasProductVariantsOverride;
  static bool get hasProductVariants =>
      hasProductVariantsOverride ?? (flavor != Flavor.vegetable);

  static bool get hasShipmentTracking => flavor == Flavor.vegetable;

  static bool get hasEmptyContainerTracking => flavor == Flavor.vegetable;

  static bool get hasCommissionPricing => flavor == Flavor.vegetable;

  /// Vegetable flavor day-close settlement view (net cash, variance,
  /// settlement entry) inside CloseDayDialog.
  static bool get hasDaySettlement => flavor == Flavor.vegetable;

  /// Staff module (employees tab + launcher). Active in the base build.
  static bool get hasStaffModule => flavor == Flavor.base;

  /// Damaged-goods module (launcher button). Active in the base build.
  static bool get hasDamagedModule => flavor == Flavor.base;

  /// Custody module (العهد المالية). Hidden in clothing flavor.
  static bool get hasCustodyModule => flavor != Flavor.clothing;

  /// Suppliers module (الموردين). Available across flavors.
  static bool get hasSuppliersModule => true;

  /// Manufacturing (BOM, production orders, scrap). Hidden in clothing —
  /// that flavor only needs invoices, purchases and reports.
  static bool get hasManufacturing => flavor != Flavor.clothing;
}
