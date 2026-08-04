import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../services/license_manager.dart';

// Provider for license state
final licenseStateProvider = FutureProvider<bool>((ref) async {
  return true;
});

// Provider to trigger license refresh
final licenseRefreshProvider = StateProvider<int>((ref) => 0);

// Provider for current license
final currentLicenseProvider = FutureProvider((ref) async {
  final licenseManager = LicenseManager();
  return await licenseManager.getCurrentLicense();
});
