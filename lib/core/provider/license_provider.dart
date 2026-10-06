import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../config/license_config.dart';
import '../../services/license_manager.dart';

// Provider for license state
final licenseStateProvider = FutureProvider<bool>((ref) async {
  return true;
});

// Provider to trigger license refresh
final licenseRefreshProvider = StateProvider<int>((ref) => 0);

// Provider for current license
final currentLicenseProvider = FutureProvider((ref) async {
  ref.watch(licenseRefreshProvider);
  final licenseManager = LicenseManager();
  return await licenseManager.getCurrentLicense();
});

/// Reactive Provider to check if a specific module is enabled in the active license
final isFeatureEnabledProvider = Provider.family<bool, String>((ref, featureName) {
  // Free version flavor/build has all features enabled
  if (LicenseConfig.isFreeVersion) return true;

  // Fundamental core features are always unlocked
  const coreFeatures = ['pos', 'cash_sales', 'inventory', 'reports'];
  if (coreFeatures.contains(featureName)) return true;

  final licenseAsync = ref.watch(currentLicenseProvider);
  return licenseAsync.maybeWhen(
    data: (license) =>
        license != null && license.isValid && license.features.contains(featureName),
    orElse: () => false,
  );
});
