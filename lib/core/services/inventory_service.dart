import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../database/dao/product_dao.dart';
import '../database/dao/inventory_movement_dao.dart';
import '../models/user_model.dart';
import 'validation/permission_validator.dart';

/// Service for managing inventory operations
/// حدمة إدارة المخزون
class InventoryService {
  final AppDatabase _db;
  late final ProductDao _productDao;
  late final InventoryMovementDao _movementDao;

  InventoryService(this._db) {
    _productDao = ProductDao(_db);
    _movementDao = InventoryMovementDao(_db);
  }

  /// Update product stock with movement tracking
  /// تحديث مخزون المنتج مع تسجيل الحركة
  Future<void> updateStock(
    User? user, {
    required int productId,
    required int quantityChange,
    required String type, // 'purchase', 'sale', 'adjustment'
    String? reference,
    String? referenceType,
    String? performedBy,
    String? notes,
  }) async {
    PermissionValidator.requirePermission(user, Permission.adjustInventory, 'تعديل المخزون');
    try {
      final product = await _productDao.getProductById(productId);
      if (product == null) {
        throw Exception('Product not found: $productId');
      }

      final previousQuantity = product.quantity;
      int newQuantity;
      int movementQuantity;

      switch (type) {
        case 'purchase':
          // Add to inventory
          newQuantity = product.quantity + quantityChange;
          movementQuantity = quantityChange; // Positive for incoming
          break;
        case 'sale':
          // Subtract from inventory
          newQuantity = product.quantity - quantityChange;
          movementQuantity = -quantityChange; // Negative for outgoing
          if (newQuantity < 0) {
            throw Exception('Insufficient stock for product: ${product.name}');
          }
          break;
        case 'adjustment':
          // Direct adjustment
          newQuantity = quantityChange;
          movementQuantity = quantityChange - previousQuantity;
          break;
        default:
          throw Exception('Invalid inventory movement type: $type');
      }

      // Update product quantity
      await _productDao.updateProduct(
        ProductsCompanion(
          id: Value(productId),
          name: Value(product.name),
          quantity: Value(newQuantity),
          price: Value(product.price),
          unit: Value(product.unit),
          category: Value(product.category),
          barcode: Value(product.barcode),
          cartonQuantity: Value(product.cartonQuantity),
          cartonPrice: Value(product.cartonPrice),
          status: Value(product.status),
        ),
      );

      // Record inventory movement
      await _movementDao.createMovementWithTimestamp(
        productId: productId,
        movementType: type,
        quantity: movementQuantity,
        unitCost: product.price,
        totalValue: (product.price * movementQuantity.abs()).toDouble(),
        movementDate: DateTime.now(),
        reference: reference ?? 'Manual',
        referenceType: referenceType ?? 'manual_adjustment',
        previousQuantity: previousQuantity,
        newQuantity: newQuantity,
        performedBy: performedBy,
        notes: notes,
      );

      debugPrint(
        'Inventory updated: ${product.name} - Old: $previousQuantity, New: $newQuantity, Movement: $movementQuantity',
      );
    } catch (e) {
      debugPrint('Error updating stock: $e');
      rethrow;
    }
  }

  /// Get products with low stock
  /// الحصول على المنتجات ذات المخزون المنخفض
  Future<List<Product>> getLowStockProducts(int threshold) async {
    try {
      final allProducts = await _productDao.getAllProducts();
      return allProducts
          .where((product) => product.quantity <= threshold)
          .toList();
    } catch (e) {
      debugPrint('Error getting low stock products: $e');
      rethrow;
    }
  }

  /// Get inventory valuation
  /// الحصول على تقييم المخزون
  Future<Map<String, dynamic>> getInventoryValuation() async {
    try {
      final allProducts = await _productDao.getAllProducts();

      double totalValue = 0;
      int totalItems = 0;
      int uniqueProducts = allProducts.length;

      for (final product in allProducts) {
        totalValue += (product.price * product.quantity);
        totalItems += product.quantity;
      }

      return {
        'totalValue': totalValue,
        'totalItems': totalItems,
        'uniqueProducts': uniqueProducts,
        'averageValuePerProduct': uniqueProducts > 0
            ? totalValue / uniqueProducts
            : 0,
      };
    } catch (e) {
      debugPrint('Error calculating inventory valuation: $e');
      rethrow;
    }
  }

  /// Get inventory by category
  /// الحصول على المخزون حسب الفئة
  Future<Map<String, List<Product>>> getInventoryByCategory() async {
    try {
      final allProducts = await _productDao.getAllProducts();
      final Map<String, List<Product>> categoryMap = {};

      for (final product in allProducts) {
        final category = product.category ?? 'غير مصنف';
        if (!categoryMap.containsKey(category)) {
          categoryMap[category] = [];
        }
        categoryMap[category]!.add(product);
      }

      return categoryMap;
    } catch (e) {
      debugPrint('Error getting inventory by category: $e');
      rethrow;
    }
  }

  /// Check if product has sufficient stock
  /// التحقق من توفر المخزون الكافي
  Future<bool> hasInsufficientStock(int productId, int requiredQuantity) async {
    try {
      final product = await _productDao.getProductById(productId);
      if (product == null) return true;
      return product.quantity < requiredQuantity;
    } catch (e) {
      debugPrint('Error checking stock: $e');
      return true; // Assume insufficient on error for safety
    }
  }
}
