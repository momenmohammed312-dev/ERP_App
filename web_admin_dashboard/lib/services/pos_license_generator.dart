import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

class POSLicenseGenerator {
  static const String _secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';

  static String generateFloatingKey({
    required String type,
    required DateTime expiryDate,
    required String companyName,
    required String contactEmail,
  }) {
    final now = DateTime.now();

    final licenseData = {
      'device': 'UNBOUND', // Floating - will be bound on first activation
      'type': type,
      'issue_date': now.toIso8601String(),
      'expiry': expiryDate.toIso8601String(),
      'features': _getFeaturesForPackage(type),
      'max_users': _getMaxUsersForType(type),
      'company_name': companyName,
      'contact_email': contactEmail,
      'version': '1.0',
    };

    final jsonString = jsonEncode(licenseData);
    final encryptedData = _encrypt(jsonString);
    final signature = _generateSignature(encryptedData);

    return '$encryptedData.$signature';
  }

  static String _encrypt(String plainText) {
    final keyBytes = md5.convert(utf8.encode(_secretKey)).bytes;
    final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt_pkg.IV(Uint8List(16)); // 16 bytes of zeros
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  static String _generateSignature(String data) {
    final bytes = utf8.encode(data + _secretKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static int _getMaxUsersForType(String type) {
    switch (type) {
      case 'trial':
      case 'basic':
        return 1;
      case 'standard':
        return 3;
      case 'professional':
        return 5;
      case 'enterprise':
        return 10;
      default:
        return 1;
    }
  }

  static List<String> _getFeaturesForPackage(String packageType) {
    switch (packageType.toLowerCase()) {
      case 'basic':
        return ['cash_sales', 'inventory', 'reports', 'backup'];
      case 'standard':
        return [
          'cash_sales',
          'inventory',
          'reports',
          'backup',
          'credit_sales',
          'customers',
          'suppliers',
          'purchases',
          'advanced_reports'
        ];
      case 'professional':
        return [
          'cash_sales',
          'inventory',
          'reports',
          'backup',
          'credit_sales',
          'customers',
          'suppliers',
          'purchases',
          'advanced_reports',
          'staff_management',
          'attendance',
          'payroll',
          'admin_dashboard',
          'api_access'
        ];
      case 'enterprise':
        return [
          'cash_sales',
          'inventory',
          'reports',
          'backup',
          'credit_sales',
          'customers',
          'suppliers',
          'purchases',
          'advanced_reports',
          'staff_management',
          'attendance',
          'payroll',
          'admin_dashboard',
          'api_access'
        ];
      default:
        return ['cash_sales', 'inventory', 'reports'];
    }
  }
}
