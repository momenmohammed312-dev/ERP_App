import '../config/license_config.dart';
import '../core/utils/logger.dart';
import 'license_manager.dart';

/// BUG-018 — the single place that answers "may this install use X?".
///
/// Before this there were three independent answers to that question, and they
/// disagreed:
///
///   * `isFeatureEnabledProvider` (Riverpod) accepted `'*'`, `'all'` or a name
///   * `FeatureGateService.hasFeature` accepted only `'*'` or a name
///   * the router answered nothing at all, and no DAO ever asked
///
/// A legacy license carrying `'all'` therefore opened a module in the home
/// screen and reported it as locked in the sidebar. Everything now routes
/// through here.
///
/// **Why an in-memory snapshot rather than awaiting the license?** Reading the
/// license means decrypting `secure_license.dat`. A DAO guard has to run
/// *inside* a Drift transaction, and holding a transaction open across a disk
/// read is how you get "database is locked" under load. [LicenseManager]
/// refreshes this snapshot on every read, so it is always current by the time
/// a write can happen.
class LicenseEntitlement {
  LicenseEntitlement._();
  static final LicenseEntitlement instance = LicenseEntitlement._();

  /// Always available — these are not sellable add-ons, they are the POS.
  static const Set<String> coreFeatures = {
    'pos',
    'cash_sales',
    'inventory',
    'reports',
  };

  /// Arabic display names, so a refusal explains itself to the operator
  /// instead of printing an internal key like "manufacturing".
  static const Map<String, String> arabicNames = {
    'pos': 'نقطة البيع',
    'cash_sales': 'المبيعات النقدية',
    'credit_sales': 'المبيعات الآجلة',
    'customers': 'العملاء',
    'suppliers': 'الموردون',
    'purchases': 'المشتريات',
    'inventory': 'المخزون',
    'reports': 'التقارير',
    'advanced_reports': 'التقارير المتقدمة',
    'backup': 'النسخ الاحتياطي',
    'auto_backup': 'النسخ التلقائي',
    'staff_management': 'الموظفون',
    'attendance': 'الحضور',
    'payroll': 'الرواتب',
    'custody': 'العهد المالية',
    'damaged_goods': 'التالف',
    'manufacturing': 'التصنيع',
    'admin_dashboard': 'لوحة الإدارة',
    'api_access': 'الواجهة البرمجية',
  };

  static String arabicName(String feature) => arabicNames[feature] ?? feature;

  /// Route path prefix → the feature it needs.
  ///
  /// Matched as an exact path or a `/`-delimited prefix, so
  /// `/manufacturing/orders/17` is covered by `/manufacturing`.
  static const Map<String, String> routeFeatures = {
    '/manufacturing': 'manufacturing',
    '/custody': 'custody',
    '/damaged-items': 'damaged_goods',
  };

  List<String> _granted = const <String>[];
  bool _loaded = false;

  /// A copy of the names currently granted. Empty until [update] runs.
  List<String> get granted => List<String>.unmodifiable(_granted);

  /// Whether [update] has run at least once this session.
  bool get isLoaded => _loaded;

  /// Refreshes the snapshot. Called by [LicenseManager] on every license read,
  /// and after an import or activation.
  void update(License? license) {
    if (license == null || !license.isValid) {
      _granted = const <String>[];
    } else {
      _granted = List<String>.from(license.features);
    }
    _loaded = true;
  }

  void reset() {
    _granted = const <String>[];
    _loaded = false;
  }

  /// Strict check: what this install is actually entitled to.
  ///
  /// Fails **closed** when the snapshot has not been loaded, because this is
  /// the check a write operation depends on — a licence must be proven, not
  /// assumed.
  bool grants(String feature) {
    if (LicenseConfig.isFreeVersion) return true;
    if (coreFeatures.contains(feature)) return true;
    if (!_loaded) return false;
    // '*' is the modern catch-all; 'all' is what the pre-RS256 generators
    // emitted and what _widenLegacyFeatures preserves.
    if (_granted.contains('*') || _granted.contains('all')) return true;
    return _granted.contains(feature);
  }

  /// The feature a route needs, or null when the route is not gated.
  static String? featureForRoute(String path) {
    String? match;
    for (final entry in routeFeatures.entries) {
      final isMatch = path == entry.key || path.startsWith('${entry.key}/');
      if (!isMatch) continue;
      // Longest prefix wins, so a future /manufacturing/x cannot be shadowed.
      if (match == null || entry.key.length > match.length) {
        match = entry.key;
      }
    }
    return match == null ? null : routeFeatures[match];
  }

  /// Navigation check, deliberately **lenient**: when the snapshot has not
  /// loaded yet this returns true.
  ///
  /// The asymmetry with [grants] is intentional. A false positive here bricks a
  /// cashier out of the register on a transient read failure, which is far
  /// worse than a momentary extra tap — and a customer who genuinely lacks the
  /// entitlement is still stopped at the DAO when they try to write.
  bool allowsNavigation(String path) {
    final feature = featureForRoute(path);
    if (feature == null) return true;
    if (!_loaded) {
      AppLogger.w(
        'Entitlement snapshot not loaded — allowing navigation to $path',
      );
      return true;
    }
    return grants(feature);
  }

  /// Guard for write paths. Throws before anything is persisted.
  void require(String feature, {String? operation}) {
    if (grants(feature)) return;
    throw FeatureNotLicensedException(feature, operation: operation);
  }
}

/// Thrown when a write is attempted on a module this install is not licensed
/// for. Carries the feature name so the UI can explain, not just refuse.
class FeatureNotLicensedException implements Exception {
  final String feature;
  final String? operation;

  const FeatureNotLicensedException(this.feature, {this.operation});

  @override
  String toString() {
    final what = operation ?? 'هذه العملية';
    return 'العملية «$what» تتطلب ترخيصاً لموديول '
        '«${LicenseEntitlement.arabicName(feature)}» غير متاح في هذا الترخيص.';
  }
}
