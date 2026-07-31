import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Entry point for the vegetable-market (سوق الخضار) flavor.
///
/// Build examples:
/// ```bash
/// flutter run -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable
/// flutter build windows -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable
/// flutter build apk -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable
/// ```
void main() => bootstrapApp(flavor: Flavor.vegetable);
