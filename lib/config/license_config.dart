class LicenseConfig {
  static const String secretKey = String.fromEnvironment(
    'LICENSE_SECRET_KEY',
    defaultValue: 'CHANGE_ME',
  );

  /// Throws if the release build still has the insecure default key.
  static void assertSecretKeyConfigured() {
    if (secretKey == 'CHANGE_ME') {
      throw StateError(
        "LICENSE_SECRET_KEY not injected via --dart-define. "
        "Refusing to run with insecure 'CHANGE_ME' default in release.",
      );
    }
  }


  /// When true, runs in fully-free mode — no license activation required.
  /// Set via: --dart-define=FREE_VERSION=true
  static bool get isFreeVersion =>
    const bool.fromEnvironment('FREE_VERSION', defaultValue: false);

  /// Trial license key shown when user taps "تجربة مجانية".
  /// Only used when isFreeVersion == false.
  static const String trialLicenseKey = String.fromEnvironment(
    'TRIAL_LICENSE_KEY',
    defaultValue: 'r7Jpnj56A/w4MTvtuxRek4X+X4Y7mAxSGVp/KsyB81Qh/Je/8qOCrMeP5HzGrwMgpU7CC3T/VC5o0o+4pDzF1u/9hzpu7ehTBx/ZbRCCiVQBAMgQ0sAONhnYcvrXOSbH1qaKKQC4FQOJqjnDXF9okTsRLGhhLHljiu671eS/Vq4gTOo92b04ExAmAWEAeqLi1wHbHS8NOtldiPLOFMpn97ZmZ7Z1o89wOuYn8B2i0BEC8PNZ23iHUKJTrHXTBFFB7t4alZ2yxt+lBJgaqOPOXQB7kFMG7bmPBwgl+3LACNIV3jUdFDpvgFIkLIPJGbn6gE54oh0oW8Pjk6n0ddrh4lepfUszrKWhi+Qwno3qFizKWel8eW44ve0Z17u3dOj4j9dTOsZc8RzeCPOWxpnIAOsuP3kNatTBWQsgRwMSengx3n3HOkArfq+dtorI7j4a.4bd8438ef9a81c07bc4ccee67ccf30d9f145673393270e0f1123bb309c044de3',
  );

  // License duration types
  static const Map<String, Map<String, dynamic>> licenseDurations = {
    'monthly': {'name': 'شهري', 'days': 30, 'price_multiplier': 1.0},
    'yearly': {
      'name': 'سنوي',
      'days': 365,
      'price_multiplier': 10.0, // 10 months for 12 = 2 months free
    },
    'lifetime': {
      'name': 'مدى الحياة',
      'days': 36500, // 100 years
      'price_multiplier': 20.0, // 20x monthly for lifetime
    },
  };

  // License duration in days
  static const int defaultLicenseDays = 365;

  // Available features
  static const List<String> availableFeatures = [
    'cash_sales', // Cash sales only
    'credit_sales', // Credit sales for customers
    'customers', // Customer Management
    'suppliers', // Supplier Management
    'purchases', // Purchase/Supply management
    'inventory', // Inventory Management
    'reports', // Basic Reports
    'advanced_reports', // Advanced Reports & Analytics
    'backup', // Backup & Restore
    'auto_backup', // Automatic backup
    'staff_management', // Staff management (Enterprise only)
    'attendance', // Attendance system
    'payroll', // Payroll and salaries
    'admin_dashboard', // Admin dashboard web
    'api_access', // API for integration
  ];

  // License types with 3 packages as per updated plan
  static const Map<String, Map<String, dynamic>> licenseTypes = {
    'basic': {
      'name': 'Basic',
      'name_arabic': 'أساسي',
      'max_users': 1,
      'features': ['cash_sales', 'inventory', 'reports', 'backup'],
      'price': 250,
      'description': 'فواتير نقدية فقط + مخزون بسيط',
      'description_arabic': 'فواتير نقدية فقط + مخزون بسيط',
      'ideal_for': 'محل صغير، خضروات، كشك',
      'ideal_for_arabic': 'محل صغير، خضروات، كشك',
    },
    'standard': {
      'name': 'Standard',
      'name_arabic': 'قياسي',
      'max_users': 1,
      'features': [
        'cash_sales',
        'credit_sales',
        'customers',
        'suppliers',
        'purchases',
        'inventory',
        'reports',
        'advanced_reports',
        'auto_backup',
      ],
      'price': 400,
      'description': 'عملاء + موردين + مشتريات + تقارير',
      'description_arabic': 'عملاء + موردين + مشتريات + تقارير',
      'ideal_for': 'محل متوسط، سوبر ماركت صغير',
      'ideal_for_arabic': 'محل متوسط، سوبر ماركت صغير',
    },
    'professional': {
      'name': 'Professional',
      'name_arabic': 'احترافي',
      'max_users': 1,
      'features': [
        'cash_sales',
        'credit_sales',
        'customers',
        'suppliers',
        'purchases',
        'inventory',
        'advanced_reports',
        'auto_backup',
        'staff_management',
        'attendance',
        'payroll',
        'admin_dashboard',
        'api_access',
      ],
      'price': 600,
      'description': 'كل شيء + إدارة موظفين كاملة',
      'description_arabic': 'كل شيء + إدارة موظفين كاملة',
      'ideal_for': 'سوبر ماركت كبير، مطعم، محل به موظفين',
      'ideal_for_arabic': 'سوبر ماركت كبير، مطعم، محل به موظفين',
    },
  };

  // App version
  static const String appVersion = '2.1.0';
  static const String appName = 'Professional POS System';

  // Support contact
  static const String supportEmail = 'support@mo2-systems.com';
  static const String supportPhone = '+20 100 000 0000';
}

/// Canonical resolution of a `plan` value found in a license payload into a
/// [LicenseType] name (BUG-009).
///
/// License payloads are written by the admin dashboard and by the local
/// issuer, and their plan identifiers do NOT match `LicenseType`:
///
///   * `admin_dashboard/src/config/modules.js` → `trial · monthly · yearly ·
///     lifetime`
///   * `tools/simulator_db.json` → `standard · basic · professional · custom`
///
/// Resolving those with `LicenseType.values.firstWhere(...)` either THREW
/// (no `orElse`) or, worse, silently fell back to `basic` via
/// `orElse: () => LicenseType.basic`. The second case is what produced the
/// customer-facing bug: a customer on a `yearly` plan got `maxUsers == 1`,
/// so `UserSessionService.canAddUser()` / `canUserLogin()` blocked every
/// employee beyond the first.
///
/// This class returns the `LicenseType` NAME as a plain String because
/// `license_config.dart` is imported BY `license_manager.dart` — referencing
/// `LicenseType` here would create an import cycle.
class LicensePlans {
  LicensePlans._();

  /// Plan identifier → `LicenseType.name`.
  ///
  /// Duration-style plans are graded by breadth of access, not by price: a
  /// yearly or lifetime subscription is not a smaller product than monthly.
  static const Map<String, String> toLicenseTypeName = {
    // Canonical LicenseType names.
    'free': 'free',
    'trial': 'trial',
    'basic': 'basic',
    'standard': 'standard',
    'professional': 'professional',
    'enterprise': 'enterprise',
    // Duration-style plans used by the dashboard / local issuer.
    'monthly': 'standard',
    'yearly': 'professional',
    'lifetime': 'professional',
    'annual': 'professional',
    // Explicitly custom — treated as the full feature set.
    'custom': 'professional',
  };

  /// Used only when a payload carries no usable plan at all.
  static const String fallbackName = 'standard';

  /// Resolves a plan identifier to a `LicenseType.name`.
  ///
  /// Returns null when [plan] is unknown so the caller can log the bad value
  /// instead of silently downgrading a paying customer.
  static String? resolve(String? plan) {
    if (plan == null) return null;
    final key = plan.trim().toLowerCase();
    if (key.isEmpty) return null;
    return toLicenseTypeName[key];
  }

  /// Like [resolve] but never returns null — unknown plans degrade to
  /// [fallbackName] so a single bad row cannot lock a customer out.
  static String resolveOrFallback(String? plan) =>
      resolve(plan) ?? fallbackName;

  /// True when [plan] is not one of the known identifiers. Used by the issuer
  /// and the dashboard validation layer to reject typos at issuance time.
  static bool isUnknown(String? plan) => resolve(plan) == null;
}
