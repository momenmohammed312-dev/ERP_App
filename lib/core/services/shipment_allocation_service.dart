import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/empty_barnika_tracking_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/vegetable_shipment_dao.dart';

/// Result of allocating barnikas across one or more shipments.
class ShipmentAllocation {
  final int shipmentId;
  final int quantity;

  const ShipmentAllocation({required this.shipmentId, required this.quantity});
}

/// Handles FIFO (first-in, first-out) allocation of barnika sales against
/// open vegetable shipments. Also supports manual override to pick a specific
/// shipment instead of automatic FIFO.
class ShipmentAllocationService {
  final VegetableShipmentDao _shipmentDao;
  final EmptyBarnikaTrackingDao _emptyBarnikaDao;

  ShipmentAllocationService(this._shipmentDao, this._emptyBarnikaDao);

  /// Allocates [requestedQuantity] barnikas across open shipments.
  ///
  /// If [overrideShipmentId] is provided, draws from that single shipment
  /// only (manual override). Otherwise uses FIFO: oldest shipment with
  /// remaining barnikas first, then next, until the quantity is fulfilled.
  ///
  /// Throws [ArgumentError] if:
  /// - No shipments have enough remaining barnikas
  /// - [overrideShipmentId] points to a shipment with insufficient stock
  Future<List<ShipmentAllocation>> allocate({
    required int requestedQuantity,
    int? overrideShipmentId,
  }) async {
    if (requestedQuantity <= 0) {
      throw ArgumentError('requestedQuantity must be positive');
    }

    if (overrideShipmentId != null) {
      return _allocateManual(
        shipmentId: overrideShipmentId,
        quantity: requestedQuantity,
      );
    }

    return _allocateFifo(requestedQuantity);
  }

  /// Manual allocation: draw everything from a single shipment.
  Future<List<ShipmentAllocation>> _allocateManual({
    required int shipmentId,
    required int quantity,
  }) async {
    final shipment = await _shipmentDao.getById(shipmentId);
    if (shipment == null) {
      throw ArgumentError('Shipment #$shipmentId not found');
    }
    if (shipment.barnikaRemainingCount < quantity) {
      throw ArgumentError(
        'Shipment #$shipmentId has ${shipment.barnikaRemainingCount} remaining, '
        'but $quantity requested',
      );
    }

    return [ShipmentAllocation(shipmentId: shipmentId, quantity: quantity)];
  }

  /// FIFO allocation: oldest shipment first, then next, etc.
  Future<List<ShipmentAllocation>> _allocateFifo(int quantity) async {
    final openShipments = await _shipmentDao.getOpenShipmentsFifo();

    final totalAvailable = openShipments.fold<int>(
      0,
      (sum, s) => sum + s.barnikaRemainingCount,
    );
    if (totalAvailable < quantity) {
      throw ArgumentError(
        'Insufficient barnikas: requested $quantity, available $totalAvailable across ${openShipments.length} shipments',
      );
    }

    final allocations = <ShipmentAllocation>[];
    var remaining = quantity;

    for (final shipment in openShipments) {
      if (remaining <= 0) break;

      final take = remaining <= shipment.barnikaRemainingCount
          ? remaining
          : shipment.barnikaRemainingCount;

      allocations.add(ShipmentAllocation(
        shipmentId: shipment.id,
        quantity: take,
      ));
      remaining -= take;
    }

    return allocations;
  }

  /// Returns the total remaining barnikas across all open shipments.
  Future<int> totalRemaining() async {
    final open = await _shipmentDao.getOpenShipmentsFifo();
    return open.fold<int>(0, (sum, s) => sum + s.barnikaRemainingCount);
  }

  /// Records that [quantity] empty barnikas were issued to [customerId].
  /// Call this when a sale includes barnika products and the customer
  /// takes empty crates with them.
  ///
  /// Returns the ID of the created tracking record.
  Future<int> recordBarnikaOut({
    required String customerId,
    required int quantity,
    DateTime? dateOut,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('quantity must be positive');
    }
    if (customerId.isEmpty) {
      throw ArgumentError('customerId cannot be empty');
    }

    return _emptyBarnikaDao.insertRecord(
      EmptyBarnikaTrackingCompanion.insert(
        customerId: customerId,
        dateOut: dateOut ?? DateTime.now(),
        quantityOut: quantity,
      ),
    );
  }
}
