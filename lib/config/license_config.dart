class LicenseConfig {
  // SECURITY: Production-secure key - CHANGE BEFORE DEPLOYMENT!
  static const String secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';

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
  static const String appVersion = '2.0.0';
  static const String appName = 'Professional POS System';

  // Support contact
  static const String supportEmail = 'support@yourcompany.com';
  static const String supportPhone = '+20 XXX XXX XXXX';
}
