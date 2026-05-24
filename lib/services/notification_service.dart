import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import '../core/database/app_database.dart';
import 'license_manager.dart';

/// Notification Service for license expiry warnings with idempotency
/// خدمة الإشعارات لتحذيرات انتهاء الترخيص مع الضمان من عدم التكرار
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  late AppDatabase _db;
  Timer? _checkTimer;

  Future<void> initialize(AppDatabase db) async {
    _db = db;

    // Start periodic license check
    _startLicenseCheckTimer();
  }

  void _startLicenseCheckTimer() {
    _checkTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _checkLicensesAndNotify();
    });
  }

  Future<void> _checkLicensesAndNotify() async {
    try {
      final licenseManager = LicenseManager();
      final isValid = await licenseManager.isLicenseValid();

      if (!isValid) return; // No valid license to check

      final license = await licenseManager.getCurrentLicense();

      if (license == null) return;

      final now = DateTime.now();
      final expiry = license.expiryDate;
      final diff = expiry.difference(now);

      // Determine notification timing based on time remaining
      DateTime? notificationTime;
      String title = '';
      String body = '';

      if (diff.inDays >= 7) {
        // 7 days before expiry
        notificationTime = expiry.subtract(const Duration(days: 7));
        title = 'تنبيه: انتهاء الترخيص قريباً';
        body = 'ترخيصك سينتهي في ${diff.inDays} أيام. يرجى تجديده.';
      } else if (diff.inDays >= 3) {
        // 3 days before expiry
        notificationTime = expiry.subtract(const Duration(days: 3));
        title = 'تحذير: انتهاء الترخيص خلال أيام قليلة';
        body = 'ترخيصك سينتهي في ${diff.inDays} أيام. يرجى التجديد فوراً.';
      } else if (diff.inHours < 48 && diff.inHours >= 6) {
        // Every 6 hours when less than 48 hours
        final hoursUntilNext = diff.inHours % 6;
        if (hoursUntilNext == 0) {
          notificationTime = now;
          title = 'تحذير عاجل: انتهاء الترخيص خلال ${diff.inHours} ساعة';
          body = 'ترخيصك سينتهي قريباً. يرجى التجديد الآن.';
        }
      } else if (diff.inHours < 6 && diff.inHours >= 1) {
        // Every hour when less than 6 hours
        final minutesUntilNext = diff.inMinutes % 60;
        if (minutesUntilNext == 0) {
          notificationTime = now;
          title = 'تحذير فوري: انتهاء الترخيص خلال ${diff.inHours} ساعة';
          body = 'ترخيصك سينتهي خلال ساعات قليلة. يرجى التجديد فوراً!';
        }
      } else if (diff.inHours < 1 && diff.inMinutes > 0) {
        // Every 20 minutes when less than 1 hour
        final minutesUntilNext = diff.inMinutes % 20;
        if (minutesUntilNext == 0) {
          notificationTime = now;
          title = 'تنبيه نهائي: انتهاء الترخيص خلال ${diff.inMinutes} دقيقة';
          body = 'ترخيصك سينتهي قريباً جداً. يرجى التجديد فوراً!';
        }
      }

      // Create notification if timing matches
      if (notificationTime != null && title.isNotEmpty && body.isNotEmpty) {
        await _createNotificationIfNotExists(
          entityId: license.licenseKey,
          title: title,
          body: body,
          sendAt: notificationTime,
        );
      }

      // Send due notifications
      await _sendDueNotifications();
    } catch (e) {
      // Silently handle errors to avoid disrupting the app
      debugPrint('Error in license notification check: $e');
    }
  }

  Future<void> _createNotificationIfNotExists({
    required String entityId,
    required String title,
    required String body,
    required DateTime sendAt,
  }) async {
    // Check if similar notification already exists and is not sent
    final existing =
        await (_db.notificationsDao.select(_db.appNotifications)
              ..where((tbl) => tbl.entityId.equals(entityId))
              ..where((tbl) => tbl.title.equals(title))
              ..where((tbl) => tbl.sent.equals(0)))
            .get();

    if (existing.isEmpty) {
      await _db.notificationsDao.createNotification(
        entityId: entityId,
        title: title,
        body: body,
        sendAt: sendAt,
      );
    }
  }

  Future<void> _sendDueNotifications() async {
    final dueNotifications = await _db.notificationsDao
        .getNotificationsDueBefore(DateTime.now());

    for (final notification in dueNotifications) {
      await _sendNotification(notification);
      await _db.notificationsDao.markAsSent(notification.id);
    }
  }

  Future<void> _sendNotification(AppNotification notification) async {
    // For desktop app, log the notification (could be enhanced with system notifications)
    dev.log(
      '🔔 LICENSE NOTIFICATION: ${notification.title}\n${notification.body}',
      name: 'LicenseNotification',
    );

    // TODO: Implement desktop system notifications if needed
    // For now, notifications are logged and stored in database
  }

  Future<List<AppNotification>> getAllNotifications() =>
      _db.notificationsDao.getAllNotifications();

  Future<List<AppNotification>> getPendingNotifications() =>
      _db.notificationsDao.getPendingNotifications();

  Future<List<AppNotification>> getSentNotifications() =>
      _db.notificationsDao.getSentNotifications();

  void dispose() {
    _checkTimer?.cancel();
  }
}
