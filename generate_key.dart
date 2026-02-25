import 'dart:convert';
import 'package:crypto/crypto.dart';

// Copying the encryption logic from the generator
class Generator {
  static const String _secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';

  static String generate(String deviceId) {
    final now = DateTime.now();
    final expiry = now.add(Duration(days: 365));

    final licenseData = {
      'device': deviceId,
      'type': 'professional',
      'issue_date': now.toIso8601String(),
      'expiry': expiry.toIso8601String(),
      'features': [
        'sales',
        'inventory',
        'customers',
        'suppliers',
        'staff_management',
        'multi_user',
      ],
      'max_users': 5,
      'company_name': 'User Device',
      'contact_email': 'admin@mo2.com',
      'version': '1.0',
    };

    final jsonString = jsonEncode(licenseData);

    // Manual encryption implementation for the script
    final keyBytes = md5.convert(utf8.encode(_secretKey)).bytes;
    // We don't have the 'encrypt' package in this bare script context, so I'll just use a direct calculation or a simple mock if I can't run it.
    // Actually, I should just use the existing file and run it if possible.

    print('DATA: $jsonString');
    return jsonString;
  }
}

void main() {
  final deviceId =
      'db16569b055a26d5789151f1021b895e4106bdf9cf2045fbfc91e8313eeab023';
  Generator.generate(deviceId);
}
