import 'dart:developer' as developer;

/// Simple in-app notification service for offline desktop POS
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<NotificationMessage> _notifications = [];

  /// Add a new notification
  void addNotification({
    required String title,
    required String message,
    required NotificationType type,
    DateTime? timestamp,
  }) {
    final notification = NotificationMessage(
      title: title,
      message: message,
      type: type,
      timestamp: timestamp ?? DateTime.now(),
    );

    _notifications.add(notification);
    developer.log('Notification: ${notification.toString()}');
  }

  /// Get all notifications
  List<NotificationMessage> getAllNotifications() =>
      List.unmodifiable(_notifications);

  /// Get notifications by type
  List<NotificationMessage> getNotificationsByType(NotificationType type) =>
      _notifications.where((n) => n.type == type).toList();

  /// Clear all notifications
  void clearAllNotifications() => _notifications.clear();

  /// Clear notifications by type
  void clearNotificationsByType(NotificationType type) {
    _notifications.removeWhere((n) => n.type == type);
  }

  /// Get unread notifications count
  int get unreadCount => _notifications.length;
}

enum NotificationType { budget, supplier, inventory, purchase, system }

class NotificationMessage {
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;

  NotificationMessage({
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
  });

  @override
  String toString() {
    return '[${timestamp.toIso8601String()}] ${type.name.toUpperCase()}: $title - $message';
  }
}
