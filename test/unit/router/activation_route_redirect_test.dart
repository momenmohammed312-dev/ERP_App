import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/router/go_router.dart';

/// BUG-023 — after an offline import the license providers flip and AppBootstrap
/// swaps the activation router for the main one while the location is still
/// `/activation-success`. That path only exists on the activation router, so the
/// main router used to throw `GoException: no routes for location`.
void main() {
  group('BUG-023 — activation-only locations after the router swap', () {
    test('/activation-success is mapped into the main router', () {
      expect(staleActivationLocation('/activation-success'), '/splash');
    });

    test('/license-info is mapped into the main router', () {
      expect(staleActivationLocation('/license-info'), '/splash');
    });

    test('real app locations keep their normal flow', () {
      for (final path in ['/', '/splash', '/activation', '/login', '/sales']) {
        expect(staleActivationLocation(path), isNull, reason: path);
      }
    });
  });
}
