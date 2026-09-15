import 'package:pos_offline_desktop/app_bootstrap.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';

/// Entry point for the clothing distribution (توزيع ملابس) flavor.
///
/// Build examples:
/// ```bash
/// flutter run -t lib/main_clothing.dart --dart-define=FLAVOR=clothing
/// flutter build windows -t lib/main_clothing.dart --dart-define=FLAVOR=clothing
/// flutter build apk -t lib/main_clothing.dart --dart-define=FLAVOR=clothing
/// ```
void main() => bootstrapApp(flavor: Flavor.clothing);
