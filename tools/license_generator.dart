// This is a standalone script to generate licenses
// Run with: dart run tools/license_generator.dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

// Copy these values from lib/config/license_config.dart
const String secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';

// License duration configurations
const Map<String, Map<String, dynamic>> licenseDurations = {
  'monthly': {'name': 'شهري', 'days': 30, 'price_multiplier': 1.0},
  'yearly': {'name': 'سنوي', 'days': 365, 'price_multiplier': 10.0},
  'lifetime': {'name': 'مدى الحياة', 'days': 36500, 'price_multiplier': 20.0},
};

const Map<String, Map<String, dynamic>> licenseTypes = {
  '1': {
    'name': 'basic',
    'users': 1,
    'features': ['pos', 'inventory', 'customers', 'reports'],
  },
  '2': {
    'name': 'standard',
    'users': 3,
    'features': ['pos', 'inventory', 'customers', 'suppliers', 'reports'],
  },
  '3': {
    'name': 'professional',
    'users': 5,
    'features': [
      'pos',
      'inventory',
      'customers',
      'suppliers',
      'reports',
      'accounting',
      'users',
    ],
  },
  '4': {
    'name': 'enterprise',
    'users': 10,
    'features': [
      'pos',
      'inventory',
      'customers',
      'suppliers',
      'reports',
      'accounting',
      'users',
      'backup',
      'export',
    ],
  },
  '5': {
    'name': 'enterprise',
    'users': 999,
    'features': [
      'pos',
      'inventory',
      'customers',
      'suppliers',
      'reports',
      'accounting',
      'users',
      'backup',
      'export',
      'admin',
    ],
    'lifetime': true,
  },
  '6': {
    'name': 'trial',
    'users': 1,
    'features': [
      'pos',
      'inventory',
      'customers',
      'suppliers',
      'reports',
      'accounting',
      'users',
      'backup',
      'export',
      'admin',
    ],
    'trial': true,
  },
};

String _encrypt(String plainText) {
  final keyBytes = md5.convert(utf8.encode(secretKey)).bytes;
  final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt_pkg.IV.fromLength(16);
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
  );
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return encrypted.base64;
}

String _generateSignature(String data) {
  final bytes = utf8.encode(data + secretKey);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

void main(List<String> args) async {
  // Support non-interactive mode: --trial
  final isAutoTrial = args.contains('--trial');

  print('=================================');
  print('   LICENSE KEY GENERATOR');
  print('=================================\n');

  if (isAutoTrial) {
    print('⚡ Auto-generating TRIAL license...\n');
    _generateAndPrint(type: '6');
    return;
  }

  // Select license type
  print('\nLicense Types:');
  print('1. Basic (1 user)');
  print('2. Standard (3 users)');
  print('3. Professional (5 users)');
  print('4. Enterprise (10 users)');
  print('5. Administrator (lifetime, unlimited users)');
  print('6. TRIAL (7 days, UNBOUND, all features)');
  stdout.write('\nSelect type (1-6): ');
  final typeChoice = stdin.readLineSync()?.trim() ?? '1';

  final selectedType = licenseTypes[typeChoice] ?? licenseTypes['1']!;
  final isTrial = selectedType.containsKey('trial') && selectedType['trial'] == true;

  // For trial, auto-set device to UNBOUND and duration to 10 days
  final deviceFingerprint = isTrial ? 'UNBOUND' : _readDeviceId();
  int days;
  String durationName;
  double priceMultiplier;

  if (isTrial) {
    days = 7;
    durationName = '7 أيام';
    priceMultiplier = 0;
    print('\nTrial license — Device: UNBOUND, Duration: 7 days');
  } else {
    // Get device fingerprint
    stdout.write('Enter customer\'s Device ID: ');
    final input = stdin.readLineSync()?.trim() ?? '';
    if (input.isEmpty) {
      print('ERROR: Device ID is required!');
      exit(1);
    }

    // Select duration
    print('\nLicense Duration:');
    print('1. Monthly (30 days)');
    print('2. Yearly (365 days) - BEST VALUE (2 months free!)');
    print('3. Lifetime (100 years)');

    if (selectedType.containsKey('lifetime') &&
        selectedType['lifetime'] == true) {
      print('4. Administrator (lifetime - already selected)');
    }

    stdout.write('\nSelect duration (1-3): ');
    final durationChoice = stdin.readLineSync()?.trim() ?? '2';

    if (selectedType.containsKey('lifetime') &&
        selectedType['lifetime'] == true) {
      days = 36500;
      durationName = 'مدى الحياة';
      priceMultiplier = 0;
      print('\nAdministrator license - LIFETIME duration');
    } else {
      final selectedDuration =
          licenseDurations[durationChoice] ?? licenseDurations['yearly']!;
      days = selectedDuration['days'];
      durationName = selectedDuration['name'];
      priceMultiplier = selectedDuration['price_multiplier'];
      print('\nDuration: $durationName ($days days)');
    }
  }

  // Generate license
  final now = DateTime.now();
  final expiryDate = now.add(Duration(days: days));
  String companyName;
  if (isTrial) {
    companyName = 'Trial User';
  } else if (selectedType.containsKey('lifetime') && selectedType['lifetime'] == true) {
    companyName = 'Administrator';
  } else {
    companyName = 'Generated License';
  }

  final licenseData = {
    'device': deviceFingerprint,
    'type': selectedType['name'],
    'issue_date': now.toIso8601String(),
    'expiry': expiryDate.toIso8601String(),
    'features': selectedType['features'],
    'max_users': selectedType['users'],
    'company_name': companyName,
    'contact_email': 'support@company.com',
    'version': '1.0',
  };

  final jsonString = jsonEncode(licenseData);
  final encryptedData = _encrypt(jsonString);
  final signature = _generateSignature(encryptedData);
  final licenseKey = '$encryptedData.$signature';

  // Display results
  print('\n${'=' * 60}');
  print('LICENSE GENERATED SUCCESSFULLY');
  print('=' * 60);
  print('Type: ${selectedType['name']}');
  print('Duration: $durationName');
  print('Max Users: ${selectedType['users']}');
  if (isTrial) {
    print('Device: UNBOUND (any device)');
    print('Expires: ${expiryDate.toIso8601String().split('T')[0]}');
  } else if (days >= 36500) {
    print('Expires: Never (lifetime license)');
  } else {
    print('Expires: ${expiryDate.toIso8601String().split('T')[0]}');
  }
  print('Features: ${(selectedType['features'] as List).join(", ")}');
  print('=' * 60);
  print('\nLICENSE KEY:');
  print(licenseKey);
  print('=' * 60);

  // Save to file
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final filename = 'license_${selectedType['name']}_$timestamp.txt';
  final file = File('licenses/$filename');
  await file.create(recursive: true);
  await file.writeAsString('''
LICENSE INFORMATION
===================
Generated: ${DateTime.now()}
Device ID: $deviceFingerprint
Type: ${selectedType['name']}
Max Users: ${selectedType['users']}
${isTrial ? 'Duration: 10 days (TRIAL)\nDevice: UNBOUND' : days >= 36500 ? 'Duration: LIFETIME\nExpires: Never (lifetime license)' : 'Duration: $days days\nExpires: ${expiryDate.toIso8601String().split('T')[0]}'}
Features: ${(selectedType['features'] as List).join(", ")}

LICENSE KEY:
$licenseKey
''');

  print('\nLicense saved to: $filename\n');
}

String _readDeviceId() {
  stdout.write('Enter customer\'s Device ID: ');
  return stdin.readLineSync()?.trim() ?? '';
}

void _generateAndPrint({required String type}) {
  final selectedType = licenseTypes[type]!;
  const isTrial = true;

  const deviceFingerprint = 'UNBOUND';
  const days = 7;
  const durationName = '7 أيام';

  final now = DateTime.now();
  final expiryDate = now.add(const Duration(days: days));
  const companyName = 'Trial User';

  final licenseData = {
    'device': deviceFingerprint,
    'type': 'trial',
    'issue_date': now.toIso8601String(),
    'expiry': expiryDate.toIso8601String(),
    'features': selectedType['features'],
    'max_users': selectedType['users'],
    'company_name': companyName,
    'contact_email': 'support@company.com',
    'version': '1.0',
  };

  final jsonString = jsonEncode(licenseData);
  final encryptedData = _encrypt(jsonString);
  final signature = _generateSignature(encryptedData);
  final licenseKey = '$encryptedData.$signature';

  print('\n${'=' * 60}');
  print('TRIAL LICENSE GENERATED');
  print('=' * 60);
  print('Type: trial');
  print('Duration: $durationName');
  print('Device: UNBOUND (any device)');
  print('Max Users: ${selectedType['users']}');
  print('Expires: ${expiryDate.toIso8601String().split('T')[0]}');
  print('Features: ${(selectedType['features'] as List).join(", ")}');
  print('=' * 60);
  print('\nTRIAL LICENSE KEY:');
  print(licenseKey);
  print('=' * 60);

  // Save to file
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final filename = 'license_trial_$timestamp.txt';
  final file = File('licenses/$filename');
  file.createSync(recursive: true);
  file.writeAsStringSync('''
TRIAL LICENSE
=============
Generated: ${DateTime.now()}
Device ID: UNBOUND
Type: trial
Max Users: ${selectedType['users']}
Duration: 10 days (TRIAL)
Device: UNBOUND (any device)
Expires: ${expiryDate.toIso8601String().split('T')[0]}
Features: ${(selectedType['features'] as List).join(", ")}

TRIAL LICENSE KEY:
$licenseKey
''');

  print('\nLicense saved to: $filename\n');
  print('\n⚠️  IMPORTANT: Set this in lib/config/license_config.dart as trialLicenseKey');
  print('   Or pass via: --dart-define=TRIAL_LICENSE_KEY="$licenseKey"\n');
}
