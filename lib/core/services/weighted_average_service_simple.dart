import 'package:drift/drift.dart' as drift;
import '../database/app_database.dart';

class WeightedAverageService {
  final AppDatabase _database;

  WeightedAverageService(this._database);

  /// Calculate weighted average cost for a product
  /// Formula: (OldQuantity × OldCost + NewQuantity × NewCost) / (OldQuantity + NewQuantity)
  Future<double> calculateWeightedAverageCost({
    required int productId,
    required double oldQuantity,
    required double oldCost,
    required double newQuantity,
    required double newCost,
  }) async {
    if (oldQuantity + newQuantity == 0) return 0.0;

    final totalCost = (oldQuantity * oldCost) + (newQuantity * newCost);
    final totalQuantity = oldQuantity + newQuantity;

    return totalCost / totalQuantity;
  }

  /// Update product cost when adding new purchase
  Future<void> updateProductCostOnPurchase({
    required int productId,
    required double newQuantity,
    required double newUnitCost,
  }) async {
    try {
      // Get current product data
      final product = await (_database.select(
        _database.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull();

      if (product == null) {
        throw Exception('Product not found: $productId');
      }

      final oldQuantity = product.quantity.toDouble();
      final oldCost = product.price; // Using price as cost for now

      // Calculate new weighted average cost
      final newAverageCost = await calculateWeightedAverageCost(
        productId: productId,
        oldQuantity: oldQuantity,
        oldCost: oldCost,
        newQuantity: newQuantity,
        newCost: newUnitCost,
      );

      // Update product with new cost and quantity
      await (_database.update(
        _database.products,
      )..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          price: drift.Value(newAverageCost),
          quantity: drift.Value((oldQuantity + newQuantity).toInt()),
        ),
      );

      // Record inventory movement
      await recordInventoryMovement(
        productId: productId,
        movementType: 'purchase',
        quantity: newQuantity,
        unitCost: newAverageCost,
        reference: 'فاتورة شراء',
        referenceType: 'purchase_invoice',
        previousQuantity: oldQuantity.toDouble(),
        newQuantity: (oldQuantity + newQuantity).toDouble(),
        notes: 'تحديث متوسط التكلفة: $newAverageCost',
      );
    } catch (e) {
      throw Exception('Error updating product cost: $e');
    }
  }

  /// Update product cost when adjusting inventory
  Future<void> updateProductCostOnAdjustment({
    required int productId,
    required double adjustmentQuantity,
    required double adjustmentCost,
    String? notes,
  }) async {
    try {
      // Get current product data
      final product = await (_database.select(
        _database.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull();

      if (product == null) {
        throw Exception('Product not found: $productId');
      }

      final oldQuantity = product.quantity.toDouble();
      final oldCost = product.price;

      // Calculate new weighted average cost
      final newAverageCost = await calculateWeightedAverageCost(
        productId: productId,
        oldQuantity: oldQuantity,
        oldCost: oldCost,
        newQuantity: adjustmentQuantity,
        newCost: adjustmentCost,
      );

      // Update product with new cost and quantity
      await (_database.update(
        _database.products,
      )..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          price: drift.Value(newAverageCost),
          quantity: drift.Value((oldQuantity + adjustmentQuantity).toInt()),
        ),
      );

      // Record inventory movement
      await recordInventoryMovement(
        productId: productId,
        movementType: 'adjustment',
        quantity: adjustmentQuantity,
        unitCost: newAverageCost,
        reference: 'تعديل يدوي',
        referenceType: 'manual_adjustment',
        previousQuantity: oldQuantity.toDouble(),
        newQuantity: (oldQuantity + adjustmentQuantity).toDouble(),
        notes: notes,
      );
    } catch (e) {
      throw Exception('Error updating product cost: $e');
    }
  }

  /// Get product cost history
  Future<List<Map<String, dynamic>>> getProductCostHistory(
    int productId,
  ) async {
    try {
      final result = await _database
          .customSelect(
            '''
        SELECT 
          im.movement_date,
          im.movement_type,
          im.quantity,
          im.previous_quantity,
          im.new_quantity,
          im.unit_cost,
          im.notes,
          im.reference
        FROM inventory_movements im
        WHERE im.product_id = ?
        ORDER BY im.movement_date DESC
        LIMIT 50
      ''',
            variables: [drift.Variable.withInt(productId)],
          )
          .get();

      return result
          .map(
            (row) => {
              'movement_date': row.read<DateTime>('movement_date'),
              'movement_type': row.readNullable<String>('movement_type') ?? '',
              'quantity': row.readNullable<int>('quantity') ?? 0,
              'previous_quantity': row.readNullable<int>('previous_quantity') ?? 0,
              'new_quantity': row.readNullable<int>('new_quantity') ?? 0,
              'unit_cost': row.readNullable<double>('unit_cost') ?? 0.0,
              'notes': row.read<String?>('notes'),
              'reference': row.read<String?>('reference'),
            },
          )
          .toList();
    } catch (e) {
      throw Exception('Error getting product cost history: $e');
    }
  }

  /// Recalculate all products' average costs
  Future<void> recalculateAllAverageCosts() async {
    try {
      // Get all products
      final products = await (_database.select(
        _database.products,
      )..where((p) => p.status.equals('Active'))).get();

      for (final product in products) {
        await _recalculateProductAverageCost(product.id);
      }
    } catch (e) {
      throw Exception('Error recalculating average costs: $e');
    }
  }

  /// Recalculate average cost for a specific product
  Future<void> _recalculateProductAverageCost(int productId) async {
    try {
      // Get all inventory movements for this product
      final movements = await _database
          .customSelect(
            '''
        SELECT 
          quantity,
          unit_cost,
          movement_date
        FROM inventory_movements
        WHERE product_id = ? AND movement_type = 'purchase'
        ORDER BY movement_date ASC
      ''',
            variables: [drift.Variable.withInt(productId)],
          )
          .get();

      if (movements.isEmpty) return;

      double totalQuantity = 0.0;
      double totalCost = 0.0;

      // Calculate weighted average from all purchases
      for (final movement in movements) {
        final quantity =
            (movement.readNullable<int>('quantity') ?? 0).toDouble();
        final unitCost = movement.readNullable<double>('unit_cost') ?? 0.0;

        if (totalQuantity == 0) {
          // First purchase
          totalQuantity = quantity;
          totalCost = quantity * unitCost;
        } else {
          // Weighted average calculation
          final newTotalQuantity = totalQuantity + quantity;
          final newTotalCost = totalCost + (quantity * unitCost);
          totalQuantity = newTotalQuantity;
          totalCost = newTotalCost;
        }
      }

      final averageCost = totalQuantity > 0 ? totalCost / totalQuantity : 0.0;

      // Update product with calculated average cost
      await (_database.update(_database.products)
            ..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(price: drift.Value(averageCost)));
    } catch (e) {
      throw Exception('Error recalculating product average cost: $e');
    }
  }

  /// Record inventory movement
  Future<void> recordInventoryMovement({
    required int productId,
    required String movementType,
    required double quantity,
    required double unitCost,
    required String reference,
    required String referenceType,
    required double previousQuantity,
    required double newQuantity,
    String? notes,
    String? performedBy,
  }) async {
    try {
      final movement = InventoryMovementsCompanion.insert(
        productId: productId,
        movementType: movementType,
        quantity: quantity.toInt(),
        unitCost: unitCost,
        totalValue: quantity * unitCost,
        movementDate: DateTime.now(),
        reference: reference,
        referenceType: referenceType,
        previousQuantity: previousQuantity.toInt(),
        newQuantity: newQuantity.toInt(),
        performedBy: drift.Value(performedBy),
        notes: drift.Value(notes),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _database.into(_database.inventoryMovements).insert(movement);
    } catch (e) {
      throw Exception('Error recording inventory movement: $e');
    }
  }

  /// Get cost analysis report
  Future<Map<String, dynamic>> getCostAnalysisReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      // Get cost changes summary
      final costChangesResult = await _database
          .customSelect(
            '''
        SELECT 
          COUNT(*) as total_adjustments,
          COUNT(CASE WHEN movement_type = 'purchase' THEN 1 END) as purchases_count,
          COUNT(CASE WHEN movement_type = 'adjustment' THEN 1 END) as adjustments_count,
          AVG(unit_cost) as avg_cost_price,
          MIN(unit_cost) as min_cost_price,
          MAX(unit_cost) as max_cost_price
        FROM inventory_movements 
        WHERE movement_date >= ? AND movement_date <= ?
      ''',
            variables: [
              drift.Variable.withDateTime(start),
              drift.Variable.withDateTime(end),
            ],
          )
          .getSingle();

      // Get top products by cost changes
      final topProductsResult = await _database
          .customSelect(
            '''
        SELECT 
          p.name as product_name,
          COUNT(im.id) as cost_changes,
          AVG(im.unit_cost) as avg_cost,
          MAX(im.unit_cost) as max_cost,
          MIN(im.unit_cost) as min_cost
        FROM inventory_movements im
        JOIN products p ON im.product_id = p.id
        WHERE im.movement_date >= ? AND im.movement_date <= ?
        GROUP BY im.product_id, p.name
        ORDER BY cost_changes DESC
        LIMIT 10
      ''',
            variables: [
              drift.Variable.withDateTime(start),
              drift.Variable.withDateTime(end),
            ],
          )
          .get();

      return {
        'period': {'start': start, 'end': end},
        'summary': {
          'total_adjustments':
              costChangesResult.readNullable<int>('total_adjustments') ?? 0,
          'purchases_count':
              costChangesResult.readNullable<int>('purchases_count') ?? 0,
          'adjustments_count':
              costChangesResult.readNullable<int>('adjustments_count') ?? 0,
          'avg_cost_price':
              costChangesResult.readNullable<double>('avg_cost_price') ?? 0.0,
          'min_cost_price':
              costChangesResult.readNullable<double>('min_cost_price') ?? 0.0,
          'max_cost_price':
              costChangesResult.readNullable<double>('max_cost_price') ?? 0.0,
        },
        'top_products': topProductsResult
            .map(
              (row) => {
                'product_name': row.readNullable<String>('product_name') ?? '',
                'cost_changes': row.readNullable<int>('cost_changes') ?? 0,
                'avg_cost': row.readNullable<double>('avg_cost') ?? 0.0,
                'max_cost': row.readNullable<double>('max_cost') ?? 0.0,
                'min_cost': row.readNullable<double>('min_cost') ?? 0.0,
              },
            )
            .toList(),
      };
    } catch (e) {
      throw Exception('Error generating cost analysis report: $e');
    }
  }
}
