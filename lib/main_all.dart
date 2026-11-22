import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

/// Entry point with all features enabled (النسخة الشاملة / تجربة كافة الشاشات والموظفين).
///
/// Build examples:
/// ```bash
/// flutter run -d 10JG2B044E0003C -t lib/main_all.dart --dart-define=FLAVOR=all --dart-define=FREE_VERSION=true --dart-define=ENABLE_ALL_FEATURES=true
/// flutter build apk -t lib/main_all.dart --dart-define=FLAVOR=all --dart-define=FREE_VERSION=true --dart-define=ENABLE_ALL_FEATURES=true
/// ```
void main() {
  runZonedGuarded<Future<void>>(() => bootstrapApp(flavor: Flavor.all), (
    error,
    stack,
  ) {
    AppLogger.e('Fatal error outside the Flutter zone', error, stack);
    debugPrint('FATAL: $error\n$stack');
  });
}
