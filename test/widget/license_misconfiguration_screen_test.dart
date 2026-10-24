import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/screens/license/license_misconfiguration_screen.dart';

void main() {
  testWidgets('LicenseMisconfigurationApp renders cleanly with Arabic warning', (tester) async {
    await tester.pumpWidget(const LicenseMisconfigurationApp());

    expect(find.text('خطأ في إعدادات الترخيص'), findsOneWidget);
    expect(find.textContaining('LICENSE_SECRET_KEY'), findsOneWidget);
    expect(find.text('إغلاق التطبيق'), findsOneWidget);
  });
}
