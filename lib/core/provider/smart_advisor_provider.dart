import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_features.dart';
import '../database/app_database.dart';
import '../services/settings_service.dart';
import '../services/smart_analytics/smart_advisor_service.dart';
import 'app_database_provider.dart';

class SmartAdvisorState {
  final List<SmartAlert> alerts;
  final int unreadCount;
  final bool isEnabled;
  final bool isLoading;
  final SmartAlert? pendingToastAlert;

  const SmartAdvisorState({
    this.alerts = const [],
    this.unreadCount = 0,
    this.isEnabled = true,
    this.isLoading = false,
    this.pendingToastAlert,
  });

  SmartAdvisorState copyWith({
    List<SmartAlert>? alerts,
    int? unreadCount,
    bool? isEnabled,
    bool? isLoading,
    SmartAlert? pendingToastAlert,
    bool clearToast = false,
  }) {
    return SmartAdvisorState(
      alerts: alerts ?? this.alerts,
      unreadCount: unreadCount ?? this.unreadCount,
      isEnabled: isEnabled ?? this.isEnabled,
      isLoading: isLoading ?? this.isLoading,
      pendingToastAlert:
          clearToast ? null : (pendingToastAlert ?? this.pendingToastAlert),
    );
  }
}

final smartAdvisorServiceProvider = Provider<SmartAdvisorService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SmartAdvisorService(db);
});

class SmartAdvisorNotifier extends StateNotifier<SmartAdvisorState> {
  final SmartAdvisorService _service;

  SmartAdvisorNotifier(this._service) : super(const SmartAdvisorState()) {
    init();
  }

  Future<void> init() async {
    // البوابة الزمنية للتجميع: لو الميزة متوقفة ما نقراش أي إعدادات ولا نكتب في الـDB.
    if (!AppFeatures.hasSmartAnalytics) {
      state = state.copyWith(
        isEnabled: false,
        alerts: const [],
        unreadCount: 0,
        isLoading: false,
        clearToast: true,
      );
      return;
    }
    final enabled = await SettingsService.isSmartAnalyticsEnabled();
    state = state.copyWith(isEnabled: enabled);
    if (enabled) {
      await refresh();
    }
  }

  Future<void> refresh({bool runAnalysis = false}) async {
    // الميزة متوقفة: نمنع تشغيل محرك التحليل وكتابة إشعارات smart:* في الـDB.
    if (!AppFeatures.hasSmartAnalytics) {
      state = state.copyWith(
        isEnabled: false,
        alerts: const [],
        unreadCount: 0,
        isLoading: false,
        clearToast: true,
      );
      return;
    }
    state = state.copyWith(isLoading: true);
    try {
      final enabled = await SettingsService.isSmartAnalyticsEnabled();
      if (!enabled) {
        state = state.copyWith(
          isEnabled: false,
          alerts: [],
          unreadCount: 0,
          isLoading: false,
          clearToast: true,
        );
        return;
      }

      SmartAlert? newlyDiscoveredToast;
      if (runAnalysis) {
        final newDiscovered = await _service.runAutomaticAnalysis(force: true);
        if (newDiscovered.isNotEmpty) {
          newlyDiscoveredToast = newDiscovered.first;
        }
      }

      final alerts = await _service.getActiveAlerts();
      final unreadCount = await _service.getUnreadCount();

      // If there wasn't a newly discovered toast from force run, but we have unread alerts
      // and no toast currently shown, we can show the most urgent unread alert if needed
      state = state.copyWith(
        isEnabled: true,
        alerts: alerts,
        unreadCount: unreadCount,
        isLoading: false,
        pendingToastAlert: newlyDiscoveredToast,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void dismissToast() {
    state = state.copyWith(clearToast: true);
  }

  Future<void> markAsRead(int notificationId) async {
    await _service.markAlertAsRead(notificationId);
    await refresh();
  }

  Future<void> markAllAsRead() async {
    await _service.markAllAlertsAsRead();
    await refresh();
  }

  Future<void> deleteAlert(int notificationId) async {
    await _service.deleteAlert(notificationId);
    await refresh();
  }

  Future<void> setEnabled(bool enabled) async {
    await SettingsService.setSmartAnalyticsEnabled(enabled);
    state = state.copyWith(isEnabled: enabled);
    if (enabled) {
      await refresh(runAnalysis: true);
    } else {
      state = state.copyWith(alerts: [], unreadCount: 0, clearToast: true);
    }
  }
}

final smartAdvisorProvider =
    StateNotifierProvider<SmartAdvisorNotifier, SmartAdvisorState>((ref) {
  final service = ref.watch(smartAdvisorServiceProvider);
  return SmartAdvisorNotifier(service);
});
