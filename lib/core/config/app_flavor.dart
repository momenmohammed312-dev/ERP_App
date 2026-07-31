/// Application build flavor — selects DB, feature flags, and optional entry point.
enum Flavor {
  base,
  vegetable,
  clothing,
}

/// Global flavor configuration. Call [initialize] once at startup before using
/// [current] or [databaseName].
class AppFlavor {
  AppFlavor._();

  static Flavor? _current;

  static Flavor get current {
    assert(
      _current != null,
      'AppFlavor.initialize() must be called before accessing current',
    );
    return _current!;
  }

  static bool get isInitialized => _current != null;

  /// Reads `--dart-define=FLAVOR=vegetable` (defaults to [Flavor.base]).
  static Flavor fromEnvironment() {
    const raw = String.fromEnvironment('FLAVOR', defaultValue: 'base');
    return parse(raw);
  }

  static Flavor parse(String raw) {
    switch (raw.toLowerCase()) {
      case 'vegetable':
      case 'veg':
        return Flavor.vegetable;
      case 'clothing':
        return Flavor.clothing;
      default:
        return Flavor.base;
    }
  }

  static void initialize(Flavor flavor) {
    _current = flavor;
  }

  /// Drift database file name (extension added by drift_flutter).
  static String get databaseName {
    switch (current) {
      case Flavor.vegetable:
        return 'pos_vegetable';
      case Flavor.clothing:
        return 'pos_clothing';
      case Flavor.base:
        return 'pos_offline_desktop_database';
    }
  }

  static String get appTitle {
    switch (current) {
      case Flavor.vegetable:
        return 'سوق الخضار - ERP';
      case Flavor.clothing:
        return 'POS - ملابس';
      case Flavor.base:
        return 'POS System - Developed by MO2';
    }
  }
}
