import 'license_manager.dart';

/// Activation Service - يعالج عملية التفعيل محلياً فقط
class ActivationService {
  final LicenseManager _licenseManager = LicenseManager();

  /// تفعيل النسخة باستخدام مفتاح الترخيص محلياً
  Future<ActivationResult> activate(String licenseKey) async {
    try {
      // التحقق من صحة مفتاح الترخيص محلياً
      final validation = await _licenseManager.validateLicense(licenseKey);

      if (!validation.isValid) {
        return ActivationResult.error(
          validation.errorMessage ??
              'مفتاح الترخيص غير صالح أو منتهي الصلاحية.',
        );
      }

      return ActivationResult.success(
        'تم تفعيل البرنامج بنجاح! استمتع باستخدام النظام.',
      );
    } catch (e) {
      return ActivationResult.error('خطأ في التفعيل: $e');
    }
  }
}

class ActivationResult {
  final bool isSuccess;
  final String message;

  ActivationResult.success(this.message) : isSuccess = true;
  ActivationResult.error(this.message) : isSuccess = false;
}
