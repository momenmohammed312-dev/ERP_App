import 'package:pos_offline_desktop/services/license_entitlement.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';

/// BUG-018 â€” declares which entitlement a test assumes.
///
/// The write guards on the manufacturing / custody / damaged-goods DAOs fail
/// CLOSED until a license has actually been read, because a licence has to be
/// proven before a write, not assumed. In the running app that read happens on
/// the splash screen before any module can be reached.
///
/// Tests exercise those modules directly and never go through the splash
/// screen, so they have to say what they are pretending to be. Calling this
/// keeps them honest: a test that exercises manufacturing is now a test that
/// asserts "a licensed install may manufacture".
///
/// Pass a feature list to test the refusal side, or omit it to grant
/// everything.
void grantLicensedModules([List<String>? features]) {
  LicenseEntitlement.instance.update(
    License(
      licenseKey: 'TEST-LICENSE',
      deviceFingerprint: 'test-machine',
      type: LicenseType.professional,
      issueDate: DateTime.now().subtract(const Duration(days: 1)),
      expiryDate: DateTime.now().add(const Duration(days: 365)),
      features: features ?? ['*'],
      maxUsers: 999,
      companyName: 'Test',
      contactEmail: '',
      hardwareId: 'test-machine',
    ),
  );
}

/// Forgets the entitlement, so a test can assert that a write is REFUSED.
void revokeLicensedModules() => LicenseEntitlement.instance.reset();