import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../../core/database/app_database.dart';
import '../../core/services/inventory_notification_service.dart';

class InventoryAlertsWidget extends StatefulWidget {
  final AppDatabase db;

  const InventoryAlertsWidget({super.key, required this.db});

  @override
  State<InventoryAlertsWidget> createState() => _InventoryAlertsWidgetState();
}

class _InventoryAlertsWidgetState extends State<InventoryAlertsWidget> {
  late InventoryNotificationService _notificationService;
  List<InventoryNotification> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _notificationService = InventoryNotificationService(widget.db);
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);

    try {
      final alerts = await _notificationService.checkInventoryAlerts();
      setState(() {
        _alerts = alerts.take(5).toList(); // Show top 5 alerts
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading inventory alerts: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'تنبيهات المخزون',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _alerts.isNotEmpty
                            ? Colors.red.shade100
                            : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_alerts.length}',
                        style: TextStyle(
                          color: _alerts.isNotEmpty
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Gap(8),
                    IconButton(
                      onPressed: _loadAlerts,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'تحديث التنبيهات',
                    ),
                  ],
                ),
              ],
            ),
            const Gap(16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_alerts.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 24),
                    const Gap(12),
                    Expanded(
                      child: Text(
                        'جميع المنتجات في مستويات مخزون مناسبة',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._alerts.map((alert) => _buildAlertItem(alert)),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertItem(InventoryNotification alert) {
    Color alertColor;
    IconData alertIcon;

    switch (alert.severity) {
      case NotificationSeverity.critical:
        alertColor = Colors.red;
        alertIcon = Icons.error;
        break;
      case NotificationSeverity.high:
        alertColor = Colors.orange;
        alertIcon = Icons.warning;
        break;
      case NotificationSeverity.medium:
        alertColor = Colors.yellow.shade700;
        alertIcon = Icons.info;
        break;
      default:
        alertColor = Colors.blue;
        alertIcon = Icons.info_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alertColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alertColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(alertIcon, color: alertColor, size: 24),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: alertColor,
                    fontSize: 14,
                  ),
                ),
                const Gap(2),
                Text(
                  alert.message,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
                if (alert.suggestedAction.isNotEmpty) ...[
                  const Gap(4),
                  Text(
                    alert.suggestedAction,
                    style: TextStyle(
                      color: alertColor.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
