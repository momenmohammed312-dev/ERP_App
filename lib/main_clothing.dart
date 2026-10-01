import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Entry point for the clothing (ملابس) flavor.
///
/// Build examples:
/// ```bash
/// flutter run -t lib/main_clothing.dart --dart-define=FLAVOR=clothing --dart-define=FREE_VERSION=true
/// flutter build windows -t lib/main_clothing.dart --dart-define=FLAVOR=clothing --dart-define=FREE_VERSION=true
/// flutter build apk -t lib/main_clothing.dart --dart-define=FLAVOR=clothing --dart-define=FREE_VERSION=true
/// ```
void main() => bootstrapApp(flavor: Flavor.clothing);
