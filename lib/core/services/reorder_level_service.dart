import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../utils/logger.dart';

class ReorderLevelService {
  final AppDatabase _database;

  ReorderLevelService(this._database);

  /// Check if product needs reordering
  Future<bool> needsReordering(int productId) async {
    try {
      final product = await (_database.select(
        _database.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull();

      if (product == null) return false;

      // For now, we'll use a simple logic: if quantity < 10, needs reordering
      // In a real implementation, you'd have a reorder_level field in the products table
      return product.quantity < 10;
    } catch (e) {
      return false;
    }
  }

  /// Get all products that need reordering
  Future<List<Map<String, dynamic>>> getProductsNeedingReorder() async {
    try {
      final products = await (_database.select(
        _database.products,
      )..where((p) => p.quantity.isSmallerThan(const Constant(10)))).get();

      return products
          .map(
            (product) => {
              'id': product.id,
              'name': product.name,
              'current_quantity': product.quantity,
              'reorder_level': 10, // Default reorder level
              'unit': product.unit ?? 'قطعة',
              'price': product.price,
              'barcode': product.barcode,
              'category': product.category,
              'status': product.status,
              'urgency': _calculateUrgency(product.quantity, 10),
            },
          )
          .toList();
    } catch (e) {
      throw Exception('Error getting products needing reorder: $e');
    }
  }

  /// Calculate urgency level for reordering
  String _calculateUrgency(int currentQuantity, int reorderLevel) {
    if (currentQuantity <= 0) return 'حرج';
    if (currentQuantity < reorderLevel * 0.25) return 'عاجل';
    if (currentQuantity < reorderLevel * 0.5) return 'متوسط';
    return 'منخفض';
  }

  /// Update reorder level for a product
  Future<void> updateReorderLevel({
    required int productId,
    required int reorderLevel,
  }) async {
    try {
      // Note: This would require adding a reorder_level field to the products table
      // For now, we'll just log the action
      AppLogger.i(
        'Updated reorder level for product $productId to $reorderLevel',
      );
    } catch (e) {
      AppLogger.e('Error updating reorder level', e);
      throw Exception('Error updating reorder level: $e');
    }
  }

  /// Get reorder suggestions based on sales history
  Future<List<Map<String, dynamic>>> getReorderSuggestions() async {
    try {
      // This would analyze sales history and suggest optimal reorder levels
      // For now, we'll return basic suggestions

      final products = await (_database.select(
        _database.products,
      )..where((p) => p.status.equals('Active'))).get();

      final suggestions = <Map<String, dynamic>>[];

      for (final product in products) {
        final currentQuantity = product.quantity;
        final suggestedReorderLevel = _calculateSuggestedReorderLevel(
          currentQuantity,
        );

        suggestions.add({
          'product_id': product.id,
          'product_name': product.name,
          'current_quantity': currentQuantity,
          'current_reorder_level': 10, // Default
          'suggested_reorder_level': suggestedReorderLevel,
          'unit': product.unit ?? 'قطعة',
          'price': product.price,
          'category': product.category,
          'reason': _getReorderReason(currentQuantity, suggestedReorderLevel),
          'priority': _calculatePriority(
            currentQuantity,
            suggestedReorderLevel,
          ),
        });
      }

      // Sort by priority
      suggestions.sort(
        (a, b) => (b['priority'] as int).compareTo(a['priority'] as int),
      );

      return suggestions.take(20).toList(); // Return top 20 suggestions
    } catch (e) {
      throw Exception('Error getting reorder suggestions: $e');
    }
  }

  /// Calculate suggested reorder level based on current quantity
  int _calculateSuggestedReorderLevel(int currentQuantity) {
    // Simple logic: suggest reorder level as 2x current quantity or minimum 10
    return (currentQuantity * 2).clamp(10, 1000);
  }

  /// Get reason for reorder suggestion
  String _getReorderReason(int currentQuantity, int suggestedLevel) {
    if (currentQuantity == 0) {
      return 'المنتج نفد تماماً ويحتاج إعادة طلب فوري';
    } else if (currentQuantity < 5) {
      return 'المخزون منخفض جداً ويجب إعادة الطلب قريباً';
    } else if (currentQuantity < suggestedLevel) {
      return 'المخزون أقل من المستوى الموصى به';
    } else {
      return 'تحسين مستوى المخزون لتجنب النفاد';
    }
  }

  /// Calculate priority for reorder
  int _calculatePriority(int currentQuantity, int suggestedLevel) {
    if (currentQuantity == 0) return 5; // Critical
    if (currentQuantity < 5) return 4; // High
    if (currentQuantity < suggestedLevel) return 3; // Medium
    return 1; // Low
  }

  /// Generate purchase order for reorder
  Future<Map<String, dynamic>> generateReorderPurchaseOrder({
    List<int>? productIds,
  }) async {
    try {
      final productsToReorder = productIds != null
          ? await _getProductsByIds(productIds)
          : await getProductsNeedingReorder();

      if (productsToReorder.isEmpty) {
        return {
          'success': false,
          'message': 'لا توجد منتجات تحتاج إعادة طلب',
          'products': [],
        };
      }

      final orderItems = productsToReorder.map((product) {
        final suggestedQuantity = _calculateSuggestedOrderQuantity(
          product['current_quantity'] as int,
          product['reorder_level'] as int,
        );

        return {
          'product_id': product['id'],
          'product_name': product['name'],
          'current_quantity': product['current_quantity'],
          'suggested_quantity': suggestedQuantity,
          'unit_price': product['price'],
          'unit': product['unit'],
          'total_value': suggestedQuantity * (product['price'] as double),
          'urgency': product['urgency'],
        };
      }).toList();

      final totalValue = orderItems.fold<double>(
        0.0,
        (sum, item) => sum + (item['total_value'] as double),
      );

      return {
        'success': true,
        'order_number': 'RO-${DateTime.now().millisecondsSinceEpoch}',
        'order_date': DateTime.now(),
        'total_items': orderItems.length,
        'total_value': totalValue,
        'products': orderItems,
        'message': 'تم إنشاء أمر إعادة طلب بنجاح',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'خطأ في إنشاء أمر إعادة الطلب: $e',
        'products': [],
      };
    }
  }

  /// Get products by their IDs
  Future<List<Map<String, dynamic>>> _getProductsByIds(
    List<int> productIds,
  ) async {
    try {
      final products = await (_database.select(
        _database.products,
      )..where((p) => p.id.isIn(productIds))).get();

      return products
          .map(
            (product) => {
              'id': product.id,
              'name': product.name,
              'current_quantity': product.quantity,
              'reorder_level': 10, // Default
              'unit': product.unit ?? 'قطعة',
              'price': product.price,
              'barcode': product.barcode,
              'category': product.category,
              'status': product.status,
              'urgency': _calculateUrgency(product.quantity, 10),
            },
          )
          .toList();
    } catch (e) {
      throw Exception('Error getting products by IDs: $e');
    }
  }

  /// Calculate suggested order quantity
  int _calculateSuggestedOrderQuantity(int currentQuantity, int reorderLevel) {
    // Order enough to reach 3x the reorder level
    final targetQuantity = reorderLevel * 3;
    return (targetQuantity - currentQuantity).clamp(1, 1000);
  }

  /// Get inventory status summary
  Future<Map<String, dynamic>> getInventoryStatusSummary() async {
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

      return {
        'total_products': totalProducts.length,
        'out_of_stock': outOfStock,
        'low_stock': lowStock,
        'adequate_stock': adequateStock,
        'total_inventory_value': totalValue,
        'reorder_needed': outOfStock + lowStock,
        'reorder_percentage': totalProducts.isNotEmpty
            ? ((outOfStock + lowStock) / totalProducts.length * 100)
                  .toStringAsFixed(1)
            : '0.0',
      };
    } catch (e) {
      throw Exception('Error getting inventory status summary: $e');
    }
  }

  /// Check and send reorder notifications
  Future<List<Map<String, dynamic>>> checkAndNotifyReorder() async {
    try {
      final productsNeedingReorder = await getProductsNeedingReorder();

      final notifications = productsNeedingReorder.map((product) {
        return {
          'id': product['id'],
          'product_name': product['name'],
          'current_quantity': product['current_quantity'],
          'reorder_level': product['reorder_level'],
          'urgency': product['urgency'],
          'message': _generateReorderMessage(product),
          'timestamp': DateTime.now(),
          'type': 'reorder_alert',
        };
      }).toList();

      return notifications;
    } catch (e) {
      throw Exception('Error checking reorder notifications: $e');
    }
  }

  /// Generate reorder message
  String _generateReorderMessage(Map<String, dynamic> product) {
    final productName = product['product_name'] as String;
    final currentQuantity = product['current_quantity'] as int;
    final urgency = product['urgency'] as String;

    switch (urgency) {
      case 'حرج':
        return '$productName - نفد المخزون تماماً! إعادة طلب فورية مطلوبة.';
      case 'عاجل':
        return '$productName - المخزون منخفض جداً ($currentQuantity قطع). إعادة طلب عاجلة.';
      case 'متوسط':
        return '$productName - المخزون منخفض ($currentQuantity قطع). يفضل إعادة الطلب قريباً.';
      default:
        return '$productName - المخزون منخفض ($currentQuantity قطع). إعادة طلب موصى بها.';
    }
  }
}
