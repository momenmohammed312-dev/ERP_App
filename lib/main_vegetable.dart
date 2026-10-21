import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

/// Entry point for the vegetable-market (سوق الخضار) flavor.
///
/// Build examples:
/// ```bash
/// flutter run -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable
/// flutter build windows -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable
/// flutter build apk -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable
/// ```
void main() {
  runZonedGuarded<Future<void>>(() => bootstrapApp(flavor: Flavor.vegetable), (
    error,
    stack,
  ) {
    AppLogger.e('Fatal error outside the Flutter zone', error, stack);
    debugPrint('FATAL: $error\n$stack');
  });
}
