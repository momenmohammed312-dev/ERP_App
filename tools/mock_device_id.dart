// Simple device fingerprint generator for testing
import 'dart:math';

void main() {
  print('=================================');
  print('   DEVICE FINGERPRINT GENERATOR');
  print('=================================\n');

  // Generate a mock device fingerprint for testing
  final random = Random();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final mockId = 'DEVICE_${timestamp}_${random.nextInt(10000)}';

  print('Generated Device ID: $mockId');
  print('\nUse this Device ID to generate test licenses.');
  print('Run: dart run tools/quick_license_generator.dart');
}
