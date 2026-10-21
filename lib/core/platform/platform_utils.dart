import 'dart:io';

import 'package:flutter/foundation.dart';

/// Central platform checks for the mobile/desktop split.
///
/// Use this instead of scattering `Platform.isX` across the codebase so the
/// platform boundary stays in one auditable place. The `kIsWeb` guard is
/// required because `dart:io` is unavailable on web.
class PlatformUtils {
  PlatformUtils._();

  /// Override flag for unit and widget testing.
  @visibleForTesting
  static bool? debugOverrideIsMobile;

  /// True on Android and iOS.
  static bool get isMobile =>
      debugOverrideIsMobile ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// True on Windows, macOS and Linux.
  static bool get isDesktop =>
      !(debugOverrideIsMobile ?? false) &&
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Whether staff/admin management features should be hidden on mobile platforms.
  static bool get hidesStaffFeaturesOnMobile => isMobile;
}
