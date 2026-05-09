import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'reorder_level_service.dart';

class InventoryNotificationService {
  final AppDatabase _database;
  final ReorderLevelService _reorderService;

  InventoryNotificationService(this._database)
    : _reorderService = ReorderLevelService(_database);

  /// Calculate urgency level for reordering
  String _calculateUrgency(int currentQuantity, int reorderLevel) {
    if (currentQuantity <= 0) return 'حرج';
    if (currentQuantity < reorderLevel * 0.25) return 'عاجل';
    if (currentQuantity < reorderLevel * 0.5) return 'متوسط';
    return 'منخفض';
  }

  /// Calculate suggested order quantity
  int _calculateSuggestedOrderQuantity(int currentQuantity, int reorderLevel) {
    // Order enough to reach 3x the reorder level
    final targetQuantity = reorderLevel * 3;
    return (targetQuantity - currentQuantity).clamp(1, 1000);
  }

  /// Check for inventory alerts and return notifications
  Future<List<InventoryNotification>> checkInventoryAlerts() async {
    try {
      final notifications = <InventoryNotification>[];

      // Check for out of stock items
      final outOfStockNotifications = await _checkOutOfStock();
      notifications.addAll(outOfStockNotifications);

      // Check for low stock items
      final lowStockNotifications = await _checkLowStock();
      notifications.addAll(lowStockNotifications);

      // Check for expired items (if applicable)
      final expiredNotifications = await _checkExpiredItems();
      notifications.addAll(expiredNotifications);

      // Sort by priority
      notifications.sort((a, b) => b.priority.compareTo(a.priority));

      return notifications;
    } catch (e) {
      debugPrint('Error checking inventory alerts: $e');
      return [];
    }
  }

  /// Check for out of stock items
  Future<List<InventoryNotification>> _checkOutOfStock() async {
    try {
      final products = await (_database.select(
        _database.products,
      )..where((p) => p.quantity.equals(0) & p.status.equals('Active'))).get();

      return products
          .map(
            (product) => InventoryNotification(
              id: 'out_of_stock_${product.id}',
              type: NotificationType.outOfStock,
              title: 'نفد المخزون',
              message: '${product.name} - نفد المخزون تماماً',
              productId: product.id,
              productName: product.name,
              currentQuantity: 0,
              priority: 5, // Critical
              timestamp: DateTime.now(),
              severity: NotificationSeverity.critical,
              actionRequired: true,
              suggestedAction: 'إعادة طلب فورية للمنتج',
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Error checking out of stock: $e');
      return [];
    }
  }

  /// Check for low stock items
  Future<List<InventoryNotification>> _checkLowStock() async {
    try {
      final products =
          await (_database.select(_database.products)..where(
                (p) =>
                    (p.quantity.isBiggerThan(const Constant(0)) &
                        p.quantity.isSmallerThan(const Constant(10))) &
                    p.status.equals('Active'),
              ))
              .get();

      return products.map((product) {
        final urgency = _calculateUrgency(product.quantity, 10);
        final priority = urgency == 'عاجل'
            ? 4
            : urgency == 'متوسط'
            ? 3
            : 2;

        return InventoryNotification(
          id: 'low_stock_${product.id}',
          type: NotificationType.lowStock,
          title: 'المخزون منخفض',
          message:
              '${product.name} - الكمية المتبقية: ${product.quantity} ${product.unit ?? 'قطعة'}',
          productId: product.id,
          productName: product.name,
          currentQuantity: product.quantity,
          priority: priority,
          timestamp: DateTime.now(),
          severity: priority >= 4
              ? NotificationSeverity.high
              : NotificationSeverity.medium,
          actionRequired: priority >= 3,
          suggestedAction:
              'إعادة طلب ${10 - product.quantity} ${product.unit ?? 'قطعة'} على الأقل',
        );
      }).toList();
    } catch (e) {
      debugPrint('Error checking low stock: $e');
      return [];
    }
  }

  /// Check for expired items (if products have expiry dates)
  Future<List<InventoryNotification>> _checkExpiredItems() async {
    try {
      // This would require adding expiry_date field to products table
      // For now, return empty list
      final now = DateTime.now();
      final thirtyDaysFromNow = now.add(const Duration(days: 30));

      // Simulate check for items expiring in 30 days
      // In real implementation, you'd query products with expiry dates
      return [];
    } catch (e) {
      debugPrint('Error checking expired items: $e');
      return [];
    }
  }

  /// Get inventory summary for dashboard
  Future<InventorySummary> getInventorySummary() async {
    try {
      final totalProducts = await (_database.select(
        _database.products,
      )..where((p) => p.status.equals('Active'))).get();

      final outOfStock = totalProducts.where((p) => p.quantity == 0).length;
      final lowStock = totalProducts
          .where((p) => p.quantity > 0 && p.quantity < 10)
          .length;
      final adequateStock = totalProducts.where((p) => p.quantity >= 10).length;

      final totalValue = totalProducts.fold<double>(
        0.0,
        (sum, product) => sum + (product.quantity * product.price),
      );

      return InventorySummary(
        totalProducts: totalProducts.length,
        outOfStock: outOfStock,
        lowStock: lowStock,
        adequateStock: adequateStock,
        totalInventoryValue: totalValue,
        alertsCount: outOfStock + lowStock,
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Error getting inventory summary: $e');
      return InventorySummary(
        totalProducts: 0,
        outOfStock: 0,
        lowStock: 0,
        adequateStock: 0,
        totalInventoryValue: 0.0,
        alertsCount: 0,
        lastChecked: DateTime.now(),
      );
    }
  }

  /// Generate reorder recommendations
  Future<List<ReorderRecommendation>> generateReorderRecommendations() async {
    try {
      final productsNeedingReorder = await _reorderService
          .getProductsNeedingReorder();

      return productsNeedingReorder.map((product) {
        final suggestedQuantity = _calculateSuggestedOrderQuantity(
          product['current_quantity'] as int,
          product['reorder_level'] as int,
        );

        return ReorderRecommendation(
          productId: product['id'] as int,
          productName: product['name'] as String,
          currentQuantity: product['current_quantity'] as int,
          reorderLevel: product['reorder_level'] as int,
          suggestedQuantity: suggestedQuantity,
          urgency: product['urgency'] as String,
          estimatedCost: suggestedQuantity * (product['price'] as double),
          unit: product['unit'] as String? ?? 'قطعة',
          unitPrice: product['price'] as double,
          priority: _getPriorityFromUrgency(product['urgency'] as String),
          lastUpdated: DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error generating reorder recommendations: $e');
      return [];
    }
  }

  /// Get priority from urgency level
  int _getPriorityFromUrgency(String urgency) {
    switch (urgency) {
      case 'حرج':
        return 5;
      case 'عاجل':
        return 4;
      case 'متوسط':
        return 3;
      default:
        return 2;
    }
  }

  /// Create purchase order from recommendations
  Future<Map<String, dynamic>> createPurchaseOrderFromRecommendations(
    List<ReorderRecommendation> recommendations,
  ) async {
    try {
      if (recommendations.isEmpty) {
        return {
          'success': false,
          'message': 'لا توجد توصيات لإعادة الطلب',
          'order_id': null,
        };
      }

      // Sort by priority
      recommendations.sort((a, b) => b.priority.compareTo(a.priority));

      final totalItems = recommendations.length;
      final totalCost = recommendations.fold<double>(
        0.0,
        (sum, rec) => sum + rec.estimatedCost,
      );

      // Create purchase order record (simplified)
      final orderId = 'PO-${DateTime.now().millisecondsSinceEpoch}';

      return {
        'success': true,
        'message': 'تم إنشاء أمر شراء بنجاح',
        'order_id': orderId,
        'total_items': totalItems,
        'total_cost': totalCost,
        'items': recommendations
            .map(
              (rec) => {
                'product_id': rec.productId,
                'product_name': rec.productName,
                'quantity': rec.suggestedQuantity,
                'unit_price': rec.unitPrice,
                'total_cost': rec.estimatedCost,
                'urgency': rec.urgency,
              },
            )
            .toList(),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'خطأ في إنشاء أمر الشراء: $e',
        'order_id': null,
      };
    }
  }

  /// Schedule periodic inventory checks
  void schedulePeriodicChecks() {
    // This would set up a timer to check inventory periodically
    // For now, just log that it's scheduled
    debugPrint('Inventory checks scheduled');
  }

  /// Send notification (placeholder for actual notification system)
  Future<void> sendNotification(InventoryNotification notification) async {
    // This would integrate with a notification system
    // For now, just log the notification
    debugPrint(
      'Notification sent: ${notification.title} - ${notification.message}',
    );
  }

  /// Batch send notifications
  Future<void> sendBatchNotifications(
    List<InventoryNotification> notifications,
  ) async {
    for (final notification in notifications) {
      await sendNotification(notification);
    }
  }
}

/// Inventory notification model
class InventoryNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final int productId;
  final String productName;
  final int currentQuantity;
  final int priority;
  final DateTime timestamp;
  final NotificationSeverity severity;
  final bool actionRequired;
  final String suggestedAction;
  final bool isRead;

  InventoryNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.productId,
    required this.productName,
    required this.currentQuantity,
    required this.priority,
    required this.timestamp,
    required this.severity,
    required this.actionRequired,
    required this.suggestedAction,
    this.isRead = false,
  });

  InventoryNotification markAsRead() {
    return InventoryNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      productId: productId,
      productName: productName,
      currentQuantity: currentQuantity,
      priority: priority,
      timestamp: timestamp,
      severity: severity,
      actionRequired: actionRequired,
      suggestedAction: suggestedAction,
      isRead: true,
    );
  }
}

/// Inventory summary model
class InventorySummary {
  final int totalProducts;
  final int outOfStock;
  final int lowStock;
  final int adequateStock;
  final double totalInventoryValue;
  final int alertsCount;
  final DateTime lastChecked;

  InventorySummary({
    required this.totalProducts,
    required this.outOfStock,
    required this.lowStock,
    required this.adequateStock,
    required this.totalInventoryValue,
    required this.alertsCount,
    required this.lastChecked,
  });

  double get healthScore {
    if (totalProducts == 0) return 0.0;
    return (adequateStock / totalProducts) * 100;
  }

  String get healthStatus {
    final score = healthScore;
    if (score >= 80) return 'ممتاز';
    if (score >= 60) return 'جيد';
    if (score >= 40) return 'متوسط';
    return 'سيء';
  }
}

/// Reorder recommendation model
class ReorderRecommendation {
  final int productId;
  final String productName;
  final int currentQuantity;
  final int reorderLevel;
  final int suggestedQuantity;
  final String urgency;
  final double estimatedCost;
  final String unit;
  final double unitPrice;
  final int priority;
  final DateTime lastUpdated;

  ReorderRecommendation({
    required this.productId,
    required this.productName,
    required this.currentQuantity,
    required this.reorderLevel,
    required this.suggestedQuantity,
    required this.urgency,
    required this.estimatedCost,
    required this.unit,
    required this.unitPrice,
    required this.priority,
    required this.lastUpdated,
  });
}

/// Notification types enum
enum NotificationType {
  outOfStock,
  lowStock,
  expired,
  reorderLevel,
  systemAlert,
}

/// Notification severity enum
enum NotificationSeverity { low, medium, high, critical }
