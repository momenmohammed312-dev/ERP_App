import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard for the "Smart Analytics & Smart Notifications are hidden in
/// the release build" gate.
///
/// `AppFeatures.hasSmartAnalytics` reads the compile-time define
/// `ENABLE_SMART_ANALYTICS` (default `true`, so dev/debug builds keep the
/// feature) and every release script passes
/// `--dart-define=ENABLE_SMART_ANALYTICS=false`. A release that loses the
/// define - or a smart entry point wired without consulting the gate - ships
/// the notification bell, the smart-alerts banner, the floating toast and the
/// analytics report tile to paying customers.
///
/// The gate must never be OR-ed with `enableAllFeatures`: an explicit
/// `false` has to win, otherwise `ENABLE_ALL_FEATURES=true` (used by the
/// "all" flavor) would silently re-enable the feature in a customer build.
///
/// This mirrors the static-guard convention in
/// `test/unit/services/license_build_config_test.dart` and
/// `test/unit/services/installer_license_persistence_test.dart`.
void main() {
  const gateDefine = 'ENABLE_SMART_ANALYTICS';
  const gateArg = '--dart-define=ENABLE_SMART_ANALYTICS=false';

  const appFeaturesPath = 'lib/core/config/app_features.dart';
  const modernHomePath = 'lib/ui/home/modern_home.dart';
  const reportsPagePath = 'lib/ui/reports/reports_page.dart';
  const settingsPath = 'lib/ui/setting/settings.dart';
  const advisorProviderPath = 'lib/core/provider/smart_advisor_provider.dart';

  /// Every script that produces a customer-facing artifact.
  const releaseScripts = <String>[
    'build_release.ps1',
    'build_all_targets.ps1',
    'scripts/build_release.ps1',
    'scripts/build_android_apk.ps1',
  ];

  /// A quoted `--dart-define=...` array entry - i.e. the define is really
  /// handed to `flutter build`, not merely mentioned in a log line.
  final quotedGateArg = RegExp(
    "['\"]${RegExp.escape(gateArg)}['\"]",
    multiLine: true,
  );

  final repoRoot = _resolveRepoRoot();

  String readSource(String relativePath) {
    final file = File('$repoRoot/$relativePath');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$relativePath is expected to exist but was not found under '
          '$repoRoot. If the file moved, update this guard.',
    );
    return file.readAsStringSync();
  }

  group('AppFeatures release gate', () {
    test(
      'app_features.dart reads the ENABLE_SMART_ANALYTICS compile-time define',
      () {
        final source = readSource(appFeaturesPath);

        expect(
          source.contains(gateDefine),
          isTrue,
          reason:
              '$appFeaturesPath must read the $gateDefine define - a release '
              'build has no other way to switch the smart surface off.',
        );
        expect(
          source.contains('bool.fromEnvironment'),
          isTrue,
          reason:
              'the $gateDefine flag must be read with bool.fromEnvironment; '
              'a runtime check cannot be stripped out of a release binary.',
        );
      },
    );

    test('the ENABLE_SMART_ANALYTICS define defaults to true', () {
      final source = readSource(appFeaturesPath);

      final smartCall = _fromEnvironmentCalls(
        source,
      ).firstWhere((call) => call.contains(gateDefine), orElse: () => '');

      expect(
        smartCall,
        isNotEmpty,
        reason:
            'no bool.fromEnvironment(...) call mentions $gateDefine in '
            '$appFeaturesPath.',
      );
      expect(
        smartCall.contains('defaultValue: true'),
        isTrue,
        reason:
            '$gateDefine must default to true so dev/debug builds keep '
            'Smart Analytics enabled. Found: $smartCall',
      );
      expect(
        smartCall.contains('defaultValue: false'),
        isFalse,
        reason:
            '$gateDefine must not default to false - a dev build without '
            'the define would silently lose the feature. Found: $smartCall',
      );
    });

    test(
      'the hasSmartAnalytics getter consults the hasSmartAnalyticsOverride seam',
      () {
        final source = readSource(appFeaturesPath);
        final getter = _getterSource(
          source,
          'static bool get hasSmartAnalytics',
        );

        expect(
          getter,
          isNotEmpty,
          reason:
              'the hasSmartAnalytics getter is missing from $appFeaturesPath.',
        );
        expect(
          getter.contains('hasSmartAnalyticsOverride'),
          isTrue,
          reason:
              'the hasSmartAnalytics getter must honour the '
              'hasSmartAnalyticsOverride seam - it is the only way to exercise '
              'the disabled path in a test. Getter source: $getter',
        );
      },
    );

    test(
      'the hasSmartAnalytics getter returns the env value and never ORs it with enableAllFeatures',
      () {
        final source = readSource(appFeaturesPath);
        final getter = _getterSource(
          source,
          'static bool get hasSmartAnalytics',
        );

        expect(
          getter.contains('enableAllFeatures'),
          isFalse,
          reason:
              'the hasSmartAnalytics getter must NOT be OR-ed with '
              'enableAllFeatures - ENABLE_ALL_FEATURES=true would then re-enable '
              'the smart surface in a customer build. Getter source: $getter',
        );
        expect(
          _returnsEnvValue(source, getter, gateDefine),
          isTrue,
          reason:
              'the hasSmartAnalytics getter must return the $gateDefine '
              'compile-time value. Getter source: $getter',
        );
      },
    );
  });

  group('release scripts disable the feature', () {
    releaseScripts.forEach((path) {
      test('$path passes $gateArg to flutter build', () {
        final source = readSource(path);

        expect(
          source.contains(gateArg),
          isTrue,
          reason:
              '$path must pass $gateArg, otherwise the customer build '
              'ships Smart Analytics and Smart Notifications.',
        );
        expect(
          quotedGateArg.allMatches(source).length,
          greaterThanOrEqualTo(1),
          reason:
              '$path must hand $gateArg to flutter build as a quoted '
              'argument - mentioning it in a log line does not disable '
              'anything.',
        );
      });
    });

    test('build_all_targets.ps1 disables the feature for all 4 targets', () {
      final source = readSource('build_all_targets.ps1');
      final count = quotedGateArg.allMatches(source).length;

      expect(
        count,
        greaterThanOrEqualTo(4),
        reason:
            'build_all_targets.ps1 produces 4 artifacts (Windows '
            'standard, Windows trial, Android standard, Android trial) and '
            'every one of them must carry $gateArg. Found $count occurrence(s).',
      );
    });
  });

  group('no ungated smart-surface entry points', () {
    test('modern_home.dart gates every smart-notification entry point', () {
      final source = readSource(modernHomePath);

      final gateCount = _countOccurrences(
        source,
        'AppFeatures.hasSmartAnalytics',
      );
      expect(
        gateCount,
        greaterThanOrEqualTo(4),
        reason:
            '$modernHomePath exposes 4 smart surfaces - the desktop bell, '
            'the mobile bell, the smart-alerts prompt card and the floating '
            'toast overlay - and each one must sit behind '
            'AppFeatures.hasSmartAnalytics. Found $gateCount occurrence(s).',
      );

      final codeGates = _countCodeOccurrences(
        source,
        'AppFeatures.hasSmartAnalytics',
      );
      expect(
        codeGates,
        greaterThanOrEqualTo(4),
        reason:
            '$modernHomePath needs 4 real gates (one per smart surface); '
            'the rest are comments. Found $codeGates gate(s) in code.',
      );

      final screenUsages = _countCodeOccurrences(
        source,
        'SmartNotificationsScreen',
      );
      expect(
        screenUsages,
        greaterThanOrEqualTo(1),
        reason:
            '$modernHomePath should still reference '
            'SmartNotificationsScreen (the smart notification screen).',
      );
      expect(
        codeGates,
        greaterThanOrEqualTo(screenUsages),
        reason:
            'every SmartNotificationsScreen entry point in $modernHomePath '
            'needs its own AppFeatures.hasSmartAnalytics gate - a new '
            'un-gated entry point would leak into the release build. '
            'Found $codeGates gate(s) for $screenUsages entry point(s).',
      );
      expect(
        _everyUsageIsPrecededByAGate(
          source,
          'SmartNotificationsScreen',
          'AppFeatures.hasSmartAnalytics',
        ),
        isTrue,
        reason:
            'every SmartNotificationsScreen reference in $modernHomePath '
            'must be reachable only through an AppFeatures.hasSmartAnalytics '
            'gate.',
      );

      expect(
        source.contains('app_features.dart'),
        isTrue,
        reason:
            '$modernHomePath must import app_features.dart - without the '
            'import the AppFeatures.hasSmartAnalytics gate does not compile.',
      );
    });

    test('reports_page.dart gates the smart analytics report tile', () {
      final source = readSource(reportsPagePath);

      expect(
        source.contains('AppFeatures.hasSmartAnalytics'),
        isTrue,
        reason:
            '$reportsPagePath must gate the smart analytics report tile '
            'behind AppFeatures.hasSmartAnalytics.',
      );
      expect(
        source.contains('app_features.dart'),
        isTrue,
        reason:
            '$reportsPagePath must import app_features.dart for the gate '
            'to compile.',
      );
    });

    test('settings.dart gates the smart-analytics settings card', () {
      final source = readSource(settingsPath);

      expect(
        source.contains('AppFeatures.hasSmartAnalytics'),
        isTrue,
        reason:
            '$settingsPath must gate the smart-analytics settings card '
            'behind AppFeatures.hasSmartAnalytics.',
      );
      expect(
        source.contains('app_features.dart'),
        isTrue,
        reason:
            '$settingsPath must import app_features.dart for the gate to '
            'compile.',
      );
    });

    test(
      'smart_advisor_provider.dart imports app_features.dart and checks the gate',
      () {
        final source = readSource(advisorProviderPath);

        expect(
          RegExp(
            "import\\s+['\"][^'\"]*app_features\\.dart['\"]",
            multiLine: true,
          ).hasMatch(source),
          isTrue,
          reason: '$advisorProviderPath must import app_features.dart.',
        );
        expect(
          source.contains('AppFeatures.hasSmartAnalytics'),
          isTrue,
          reason:
              '$advisorProviderPath must check AppFeatures.hasSmartAnalytics '
              'so no smart:* notification is written to the database when the '
              'feature is disabled.',
        );
      },
    );
  });
}

/// Locates the repository root so the static scans work no matter which
/// directory the test runner was started from.
String _resolveRepoRoot() {
  final candidates = <String>[
    if (Platform.script.scheme == 'file')
      File.fromUri(Platform.script).parent.path,
    Directory.current.path,
  ];

  for (final candidate in candidates) {
    var dir = Directory(candidate).absolute;
    while (true) {
      if (File('${dir.path}/pubspec.yaml').existsSync() &&
          Directory('${dir.path}/lib/core/config').existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }

  throw StateError(
    'Could not locate the repository root from $candidates. The static '
    'source-scan guards need the repo root to read lib/ and the release '
    'scripts.',
  );
}

/// Returns the source of every `bool.fromEnvironment(...)` call in [source].
List<String> _fromEnvironmentCalls(String source) {
  const marker = 'bool.fromEnvironment(';
  final calls = <String>[];
  var index = source.indexOf(marker);

  while (index != -1) {
    var depth = 0;
    var i = index + marker.length - 1; // the '(' of the call
    for (; i < source.length; i++) {
      final char = source[i];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) break;
      }
    }

    final end = i < source.length ? i + 1 : source.length;
    calls.add(source.substring(index, end));
    index = source.indexOf(marker, end);
  }

  return calls;
}

/// Returns the source of the getter declared by [marker] (for example
/// `static bool get hasSmartAnalytics`), body included. Supports both the
/// `=> expr;` and the `{ ... }` forms.
String _getterSource(String source, String marker) {
  final start = source.indexOf(marker);
  if (start < 0) return '';

  var i = start + marker.length;
  while (i < source.length && RegExp(r'\s').hasMatch(source[i])) {
    i++;
  }

  // Expression body: `static bool get x => expr;`
  if (source.startsWith('=>', i)) {
    var depth = 0;
    for (var j = i; j < source.length; j++) {
      final char = source[j];
      if (char == '(' || char == '[') depth++;
      if (char == ')' || char == ']') depth--;
      if (char == ';' && depth <= 0) return source.substring(start, j + 1);
    }
    return source.substring(start);
  }

  // Block body: `static bool get x { ... }`
  if (i < source.length && source[i] == '{') {
    var depth = 0;
    for (var j = i; j < source.length; j++) {
      final char = source[j];
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return source.substring(start, j + 1);
      }
    }
  }

  return source.substring(start);
}

/// Whether [getterSource] returns the compile-time value of [define] - either
/// directly, or through a constant that is initialised from it.
bool _returnsEnvValue(String source, String getterSource, String define) {
  if (getterSource.contains('fromEnvironment')) return true;

  final holder = RegExp(
    r'(?:static\s+)?(?:const|final)\s+(?:bool\s+)?(\w+)\s*=\s*'
    r'bool\.fromEnvironment\([^)]*${RegExp.escape(define)}',
  ).firstMatch(source);
  if (holder == null) return false;
  return getterSource.contains(holder.group(1)!);
}

/// Number of times [token] occurs in [source].
int _countOccurrences(String source, String token) =>
    RegExp(RegExp.escape(token)).allMatches(source).length;

/// Number of times [token] occurs in [source] outside of comment lines.
int _countCodeOccurrences(String source, String token) {
  var count = 0;
  for (final line in source.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    count += _countOccurrences(line, token);
  }
  return count;
}

/// Whether every [usage] in [source] has a [gate] occurrence before it.
bool _everyUsageIsPrecededByAGate(String source, String usage, String gate) {
  final usageIndexes = <int>[];
  final gateIndexes = <int>[];

  for (final match in RegExp(RegExp.escape(usage)).allMatches(source)) {
    usageIndexes.add(match.start);
  }
  for (final match in RegExp(RegExp.escape(gate)).allMatches(source)) {
    gateIndexes.add(match.start);
  }

  for (final usageIndex in usageIndexes) {
    if (!gateIndexes.any((gateIndex) => gateIndex < usageIndex)) return false;
  }
  return true;
}
