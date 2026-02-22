import 'package:flutter/material.dart';
import '../config/license_config.dart';
import 'license_manager.dart';

class FeatureGateService {
  static final FeatureGateService _instance = FeatureGateService._internal();
  factory FeatureGateService() => _instance;
  FeatureGateService._internal();

  final LicenseManager _licenseManager = LicenseManager();

  /// Check if current license has access to a specific feature
  Future<bool> hasFeature(String feature) async {
    try {
      final license = await _licenseManager.getCurrentLicense();
      if (license == null || !license.isValid) {
        return false;
      }
      return license.features.contains(feature);
    } catch (e) {
      return false;
    }
  }

  /// Check feature availability. UI should handle upgrade dialogs separately.
  Future<bool> checkFeature(
    String feature, {
    String? featureNameArabic,
    String? customMessage,
  }) async {
    final hasAccess = await hasFeature(feature);
    if (!hasAccess) return false;
    return true;
  }

  /// Get current package type
  Future<String> getCurrentPackage() async {
    try {
      final license = await _licenseManager.getCurrentLicense();
      return license?.licenseType ?? 'basic';
    } catch (e) {
      return 'basic';
    }
  }

  /// Get package info for a specific package type
  Map<String, dynamic> getPackageInfo(String packageType) {
    return LicenseConfig.licenseTypes[packageType] ??
        LicenseConfig.licenseTypes['basic']!;
  }

  /// Get required package for a feature
  String getRequiredPackageForFeature(String feature) {
    for (final packageType in LicenseConfig.licenseTypes.keys) {
      final package = LicenseConfig.licenseTypes[packageType]!;
      if (package['features'].contains(feature)) {
        return packageType;
      }
    }
    return 'professional'; // Default to highest tier
  }

  // Removed _showUpgradeDialog in favor of UI-driven handling of upgrades

  /// Get Arabic display name for feature
  String _getFeatureDisplayName(String feature) {
    final featureNames = {
      'credit_sales': 'المبيعات الآجلة',
      'customers': 'إدارة العملاء',
      'suppliers': 'إدارة الموردين',
      'purchases': 'المشتريات',
      'advanced_reports': 'التقارير المتقدمة',
      'auto_backup': 'النسخ الاحتياطي التلقائي',
      'staff_management': 'إدارة الموظفين',
      'attendance': 'الحضور والانصراف',
      'payroll': 'المرتبات والسلف',
      'admin_dashboard': 'لوحة التحكم',
      'api_access': 'الوصول للـ API',
    };
    return featureNames[feature] ?? feature;
  }

  /// Check if user can access customers
  Future<bool> canAccessCustomers() async => await hasFeature('customers');

  /// Check if user can access suppliers
  Future<bool> canAccessSuppliers() async => await hasFeature('suppliers');

  /// Check if user can access purchases
  Future<bool> canAccessPurchases() async => await hasFeature('purchases');

  /// Check if user can create credit sales
  Future<bool> canCreateCreditSales() async => await hasFeature('credit_sales');

  /// Check if user can access staff management
  Future<bool> canAccessStaffManagement() async =>
      await hasFeature('staff_management');

  /// Check if user can access attendance
  Future<bool> canAccessAttendance() async => await hasFeature('attendance');

  /// Check if user can access payroll
  Future<bool> canAccessPayroll() async => await hasFeature('payroll');

  /// Check if user can access advanced reports
  Future<bool> canAccessAdvancedReports() async =>
      await hasFeature('advanced_reports');

  /// Check if user has auto backup
  Future<bool> hasAutoBackup() async => await hasFeature('auto_backup');
}

/// Widget to wrap features that require specific license
class FeatureGuard extends StatelessWidget {
  final String feature;
  final Widget child;
  final Widget? fallback;
  final String? featureNameArabic;
  final String? customMessage;

  const FeatureGuard({
    super.key,
    required this.feature,
    required this.child,
    this.fallback,
    this.featureNameArabic,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: FeatureGateService().hasFeature(feature),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data == true) {
          return child;
        }

        return fallback ??
            FeatureLockedScreen(
              featureName:
                  featureNameArabic ??
                  FeatureGateService()._getFeatureDisplayName(feature),
              requiredPackage: FeatureGateService()
                  .getRequiredPackageForFeature(feature),
              customMessage: customMessage,
            );
      },
    );
  }
}

/// Screen shown when a feature is locked
class FeatureLockedScreen extends StatelessWidget {
  final String featureName;
  final String requiredPackage;
  final String? customMessage;

  const FeatureLockedScreen({
    super.key,
    required this.featureName,
    required this.requiredPackage,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    final packageInfo = FeatureGateService().getPackageInfo(requiredPackage);

    return Scaffold(
      appBar: AppBar(
        title: Text('ميزة غير متاحة'),
        backgroundColor: Colors.red[50],
        foregroundColor: Colors.red[700],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text(
                'ميزة "$featureName" غير متاحة في باقتك الحالية',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (customMessage != null) ...[
                Text(
                  customMessage!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'هذه الميزة متاحة في باقة ${packageInfo['name_arabic']}',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'السعر: ${packageInfo['price']} ج.م',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.green[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('عودة'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _showUpgradeDialog(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('ترقية الباقة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // _showUpgradeDialog removed; upgrade dialogs should be triggered by UI using FeatureLockedScreen data.

  void _showUpgradeDialog(BuildContext context) {
    final packageInfo = FeatureGateService().getPackageInfo(requiredPackage);
    showDialog(
      context: context,
      builder: (context) => UpgradeDialog(
        featureName: featureName,
        requiredPackage: packageInfo['name_arabic'] ?? requiredPackage,
        requiredPackagePrice: packageInfo['price'] ?? 0,
        customMessage: customMessage,
      ),
    );
  }
}

/// Upgrade dialog widget
class UpgradeDialog extends StatelessWidget {
  final String featureName;
  final String requiredPackage;
  final int requiredPackagePrice;
  final String? customMessage;

  const UpgradeDialog({
    super.key,
    required this.featureName,
    required this.requiredPackage,
    required this.requiredPackagePrice,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.upgrade, color: Colors.green),
          SizedBox(width: 8),
          Text('ترقية الباقة'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'للوصول إلى ميزة "$featureName"، تحتاج إلى ترقية باقتك إلى:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requiredPackage,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'السعر: $requiredPackagePrice ج.م',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[600],
                  ),
                ),
              ],
            ),
          ),
          if (customMessage != null) ...[
            SizedBox(height: 16),
            Text(customMessage!),
          ],
          SizedBox(height: 16),
          Text(
            'للترقية، تواصل معنا عبر:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('📞 +20 123 456 7890'),
          Text('📱 WhatsApp: +20 123 456 7890'),
          Text('📧 support@yourcompany.com'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('لاحقاً'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            _openWhatsApp();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: Text('تواصل الآن'),
        ),
      ],
    );
  }

  void _openWhatsApp() {
    // In a real app, this would open WhatsApp
    // url_launcher.launch('https://wa.me/201234567890');
  }
}

/// Widget to conditionally show UI elements based on feature access
class ConditionalWidget extends StatelessWidget {
  final String feature;
  final Widget child;
  final Widget? fallback;

  const ConditionalWidget({
    super.key,
    required this.feature,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: FeatureGateService().hasFeature(feature),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return child;
        }
        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}
