import 'dart:async';
import 'update_service.dart';
import '../core/utils/logger.dart';

class AutoUpdateChecker {
  static Timer? _timer;
  static const _checkInterval = Duration(hours: 6); // Check every 6 hours

  /// Start periodic update checks
  static void start(Function(UpdateInfo) onUpdateFound) {
    _timer?.cancel();

    // Check immediately
    _checkNow(onUpdateFound);

    // Check periodically
    _timer = Timer.periodic(_checkInterval, (_) {
      _checkNow(onUpdateFound);
    });
  }

  static void stop() {
    _timer?.cancel();
  }

  static Future<void> _checkNow(Function(UpdateInfo) onUpdateFound) async {
    try {
      final updateService = UpdateService();
      final update = await updateService.checkForUpdate();

      if (update != null) {
        AppLogger.i('Update found: ${update.version}');
        onUpdateFound(update);
      }
    } catch (e) {
      AppLogger.e('Auto update check error', e);
    }
  }
}
