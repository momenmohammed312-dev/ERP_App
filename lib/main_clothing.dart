import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

/// Entry point for the clothing (ملابس) flavor.
///
/// Build examples:
/// ```bash
/// flutter run -t lib/main_clothing.dart --dart-define=FLAVOR=clothing --dart-define=FREE_VERSION=true
/// flutter build windows -t lib/main_clothing.dart --dart-define=FLAVOR=clothing --dart-define=FREE_VERSION=true
/// flutter build apk -t lib/main_clothing.dart --dart-define=FLAVOR=clothing --dart-define=FREE_VERSION=true
/// ```
void main() {
  runZonedGuarded<Future<void>>(() => bootstrapApp(flavor: Flavor.clothing), (
    error,
    stack,
  ) {
    AppLogger.e('Fatal error outside the Flutter zone', error, stack);
    debugPrint('FATAL: $error\n$stack');
  });
}
