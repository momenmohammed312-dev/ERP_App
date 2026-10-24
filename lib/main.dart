import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

/// Entry point for the base flavor.
///
/// Build examples:
/// ```bash
/// flutter run -t lib/main.dart
/// flutter build apk --debug -t lib/main.dart
/// flutter build windows --release -t lib/main.dart
/// ```
void main() {
  // bootstrapApp() awaits eight services before it reaches runApp. Without a
  // zone guard a throw in any of them kills the process before the first frame
  // is drawn, which shows up on the device as a white screen and an immediate
  // exit with nothing readable in logcat.
  runZonedGuarded<Future<void>>(() => bootstrapApp(flavor: Flavor.base), (
    error,
    stack,
  ) {
    AppLogger.e('Fatal error outside the Flutter zone', error, stack);
    // debugPrint reaches logcat on a device; dev.log does not without a host.
    debugPrint('FATAL: $error\n$stack');
  });
}
