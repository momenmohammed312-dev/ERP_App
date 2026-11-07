import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Compile-time feature flags derived from the active [Flavor].
class AppFeatures {
  AppFeatures._();

  static Flavor get flavor =>
      AppFlavor.isInitialized ? AppFlavor.current : AppFlavor.fromEnvironment();

  /// Flag to enable all features for complete testing/demo across all modules.
  static bool? enableAllFeaturesOverride;
  static bool get enableAllFeatures =>
      enableAllFeaturesOverride ??
      (flavor == Flavor.all ||
          const bool.fromEnvironment(
            'ENABLE_ALL_FEATURES',
            defaultValue: false,
          ));

  /// Product variants (الألوان والمقاسات والأصناف المتعددة).
  /// مفعلة في التطبيق الأساسي والتجارة العامة ونكهة الملابس والنسخة الشاملة، ومعطلة فقط في سوق الخضار.
  static bool? hasProductVariantsOverride;
  static bool get hasProductVariants =>
      hasProductVariantsOverride ??
      (enableAllFeatures || flavor != Flavor.vegetable);

  static bool get hasShipmentTracking =>
      enableAllFeatures || flavor == Flavor.vegetable;

  static bool get hasEmptyContainerTracking =>
      enableAllFeatures || flavor == Flavor.vegetable;

  static bool get hasCommissionPricing =>
      enableAllFeatures || flavor == Flavor.vegetable;

  /// Vegetable flavor day-close settlement view (net cash, variance,
  /// settlement entry) inside CloseDayDialog.
  static bool get hasDaySettlement =>
      enableAllFeatures || flavor == Flavor.vegetable;

  /// Staff module (employees tab + launcher). Active in base and all builds.
  static bool get hasStaffModule =>
      enableAllFeatures || flavor == Flavor.base;

  /// Damaged-goods module (launcher button). Active in base and all builds.
  static bool get hasDamagedModule =>
      enableAllFeatures || flavor == Flavor.base;

  /// Custody module (العهد المالية). Hidden in clothing flavor.
  static bool get hasCustodyModule =>
      enableAllFeatures || flavor != Flavor.clothing;

  /// Suppliers module (الموردين). Available across flavors.
  static bool get hasSuppliersModule => true;

  /// Manufacturing (BOM, production orders, scrap). Hidden in clothing —
  /// that flavor only needs invoices, purchases and reports.
  static bool get hasManufacturing =>
      enableAllFeatures || flavor != Flavor.clothing;

  /// Smart Analytics & Predictive Engine (المستشار والتحليل الذكي).
  /// Enabled by default across flavors, overridable or toggleable via settings.
  static bool? hasSmartAnalyticsOverride;
  static bool get hasSmartAnalytics =>
      hasSmartAnalyticsOverride ?? true;
}
