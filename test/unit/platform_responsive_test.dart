import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:pos_offline_desktop/core/platform/responsive.dart';

void main() {
  group('Responsive helpers and breakpoints', () {
    testWidgets('dialogWidth returns desired on wide desktop viewports', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1280, 800)),
            child: Builder(
              builder: (context) {
                final width = dialogWidth(context, 400);
                expect(width, equals(400.0));
                final maxH = dialogMaxHeight(context);
                expect(maxH, equals(640.0));
                expect(context.isDesktopWidth, isTrue);
                expect(context.isMobileWidth, isFalse);
                expect(context.isTabletWidth, isFalse);
                return const Placeholder();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('dialogWidth constrains to 90% on narrow mobile viewports', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 640)),
            child: Builder(
              builder: (context) {
                // 360 * 0.9 = 324 < 400
                final width = dialogWidth(context, 400);
                expect(width, equals(324.0));
                // Desired width smaller than 90% maxWidth stays untouched
                final smallerWidth = dialogWidth(context, 200);
                expect(smallerWidth, equals(200.0));
                final maxH = dialogMaxHeight(context);
                expect(maxH, equals(512.0));
                expect(context.isDesktopWidth, isFalse);
                expect(context.isMobileWidth, isTrue);
                expect(context.isTabletWidth, isFalse);
                return const Placeholder();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('Breakpoints boundary edge cases are exact', (tester) async {
      // Test exact mobile threshold (599.9 vs 600.0)
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(599.9, 800)),
            child: Builder(
              builder: (context) {
                expect(context.isMobileWidth, isTrue);
                expect(context.isTabletWidth, isFalse);
                expect(context.isDesktopWidth, isFalse);
                return const Placeholder();
              },
            ),
          ),
        ),
      );

      // Test 600.0 (tablet lower boundary)
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600.0, 800)),
            child: Builder(
              builder: (context) {
                expect(context.isMobileWidth, isFalse);
                expect(context.isTabletWidth, isTrue);
                expect(context.isDesktopWidth, isFalse);
                return const Placeholder();
              },
            ),
          ),
        ),
      );

      // Test 999.9 (tablet upper boundary)
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(999.9, 800)),
            child: Builder(
              builder: (context) {
                expect(context.isMobileWidth, isFalse);
                expect(context.isTabletWidth, isTrue);
                expect(context.isDesktopWidth, isFalse);
                return const Placeholder();
              },
            ),
          ),
        ),
      );

      // Test 1000.0 (desktop lower boundary)
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1000.0, 800)),
            child: Builder(
              builder: (context) {
                expect(context.isMobileWidth, isFalse);
                expect(context.isTabletWidth, isFalse);
                expect(context.isDesktopWidth, isTrue);
                return const Placeholder();
              },
            ),
          ),
        ),
      );
    });

    test('PlatformUtils.hidesStaffFeaturesOnMobile matches isMobile', () {
      expect(
        PlatformUtils.hidesStaffFeaturesOnMobile,
        equals(PlatformUtils.isMobile),
      );
    });
  });
}
