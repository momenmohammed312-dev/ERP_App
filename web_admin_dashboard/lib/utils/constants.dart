import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryColor = Color(0xFF1E293B);
  static const Color secondaryColor = Color(0xFF334155);
  static const Color accentColor = Color(0xFF3B82F6);
  static const Color backgroundColor = Color(0xFFF1F5F9);
  static const Color cardColor = Colors.white;
  static const Color successColor = Color(0xFF10B981);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color infoColor = Color(0xFF06B6D4);

  // Package colors
  static const Color basicColor = Color(0xFF8B5CF6);
  static const Color standardColor = Color(0xFF3B82F6);
  static const Color professionalColor = Color(0xFF10B981);

  static const MaterialColor primary = MaterialColor(
    0xFF1E293B,
    <int, Color>{
      50: Color(0xFFE8F0FE),
      100: Color(0xFFC7D2FE),
      200: Color(0xFFA5B4FC),
      300: Color(0xFF818CF8),
      400: Color(0xFF6366F1),
      500: Color(0xFF4F46E5),
      600: Color(0xFF4338CA),
      700: Color(0xFF3730A3),
      800: Color(0xFF312E81),
      900: Color(0xFF1E293B),
    },
  );
}

class AppStrings {
  // App
  static const String appName = 'لوحة تحكم MO2';
  static const String appNameEn = 'MO2 Admin Dashboard';

  // Auth
  static const String login = 'تسجيل الدخول';
  static const String username = 'اسم المستخدم';
  static const String password = 'كلمة المرور';
  static const String loginButton = 'دخول';
  static const String logout = 'تسجيل الخروج';

  // Navigation
  static const String dashboard = 'لوحة التحكم';
  static const String overview = 'نظرة عامة';
  static const String analytics = 'التحليلات';
  static const String clients = 'العملاء';
  static const String licenses = 'التراخيص';
  static const String settings = 'الإعدادات';

  // Clients
  static const String addClient = 'إضافة عميل';
  static const String editClient = 'تعديل عميل';
  static const String deleteClient = 'حذف عميل';
  static const String clientName = 'اسم العميل';
  static const String clientPhone = 'رقم الهاتف';
  static const String clientEmail = 'البريد الإلكتروني';
  static const String clientAddress = 'العنوان';
  static const String clientPackage = 'الباقة';
  static const String clientNotes = 'ملاحظات';
  static const String searchClients = 'بحث في العملاء...';

  // Licenses
  static const String generateLicense = 'توليد ترخيص';
  static const String renewLicense = 'تجديد ترخيص';
  static const String revokeLicense = 'إلغاء ترخيص';
  static const String copyLicenseKey = 'نسخ المفتاح';
  static const String licenseKey = 'مفتاح الترخيص';
  static const String licenseStatus = 'حالة الترخيص';
  static const String licenseExpiry = 'تاريخ الانتهاء';
  static const String licenseDuration = 'مدة الاشتراك';

  // Packages
  static const String basicPackage = 'أساسي';
  static const String standardPackage = 'قياسي';
  static const String professionalPackage = 'احترافي';

  // Package descriptions
  static const String basicDescription = 'عمليات البيع فقط';
  static const String standardDescription = 'البيع + العملاء والموردين';
  static const String professionalDescription = 'كل المميزات + الموظفين';

  // Durations
  static const String trial = 'تجريبي (7 أيام)';
  static const String monthly = 'شهري';
  static const String yearly = 'سنوي';
  static const String lifetime = 'مدى الحياة';

  // Status
  static const String active = 'نشط';
  static const String expired = 'منتهي';
  static const String revoked = 'ملغي';
  static const String trialStatus = 'تجريبي';

  // Stats
  static const String totalClients = 'إجمالي العملاء';
  static const String activeLicenses = 'التراخيص النشطة';
  static const String totalRevenue = 'إجمالي الإيرادات';
  static const String expiringSoon = 'ينتهي قريباً';

  // Actions
  static const String save = 'حفظ';
  static const String cancel = 'إلغاء';
  static const String delete = 'حذف';
  static const String edit = 'تعديل';
  static const String confirm = 'تأكيد';
  static const String copied = 'تم النسخ!';

  // Messages
  static const String clientAdded = 'تم إضافة العميل بنجاح';
  static const String clientUpdated = 'تم تحديث العميل بنجاح';
  static const String clientDeleted = 'تم حذف العميل';
  static const String licenseGenerated = 'تم توليد الترخيص بنجاح';
  static const String licenseRenewed = 'تم تجديد الترخيص';
  static const String licenseRevoked = 'تم إلغاء الترخيص';
  static const String confirmDelete = 'هل أنت متأكد من الحذف؟';
  static const String noClients = 'لا يوجد عملاء';
  static const String noLicenses = 'لا يوجد تراخيص';
}

class AppRoutes {
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String clients = '/clients';
  static const String licenses = '/licenses';
}

/// Package pricing information
class PackagePricing {
  static const Map<String, double> basePrices = {
    'basic': 250.0,
    'standard': 400.0,
    'professional': 600.0,
  };

  static double getPrice(String packageType, String duration) {
    final basePrice = basePrices[packageType] ?? 250.0;
    switch (duration) {
      case 'trial':
        return 0.0;
      case 'monthly':
        return basePrice;
      case 'yearly':
        return basePrice * 10; // 2 months free
      case 'lifetime':
        return basePrice * 24;
      default:
        return basePrice;
    }
  }

  static String formatPrice(double price) {
    if (price == 0) return 'مجاني';
    return '${price.toStringAsFixed(0)} ج.م';
  }
}
