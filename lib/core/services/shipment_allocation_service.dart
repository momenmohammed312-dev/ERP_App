import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/empty_barnika_tracking_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/vegetable_shipment_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';

/// Result of allocating barnikas across one or more shipments.
class ShipmentAllocation {
  final int shipmentId;
  final int quantity;

  const ShipmentAllocation({required this.shipmentId, required this.quantity});
}

/// Handles FIFO (first-in, first-out) allocation of barnika sales against
/// open vegetable shipments, topping-up crate adjustments, and empty barnika
/// custody tracking.
class ShipmentAllocationService {
  final VegetableShipmentDao _shipmentDao;
  final EmptyBarnikaTrackingDao _emptyBarnikaDao;

  ShipmentAllocationService(this._shipmentDao, this._emptyBarnikaDao);

  /// Computes true sellable remaining crates on [shipment]:
  /// `totalBarnikaCount - barnikaSoldCount - toppingCount`
  /// (bounded by [VegetableShipment.barnikaRemainingCount] and zero when closed).
  static int effectiveRemaining(VegetableShipment shipment) {
    if (shipment.status != VegetableShipmentStatus.open) return 0;
    final formulaRemaining = shipment.totalBarnikaCount -
        shipment.barnikaSoldCount -
        shipment.toppingCount;
    return math
        .min(shipment.barnikaRemainingCount, formulaRemaining)
        .clamp(0, 1 << 30);
  }

  /// Allocates [requestedQuantity] barnikas across open shipments.
  ///
  /// If [overrideShipmentId] is provided, draws from that single open shipment
  /// only (manual override). Otherwise uses FIFO: oldest open shipment with
  /// remaining barnikas first, then next, until the quantity is fulfilled.
  ///
  /// Throws [ArgumentError] if:
  /// - [requestedQuantity] <= 0
  /// - No open shipments have enough remaining barnikas (forbids overselling)
  /// - [overrideShipmentId] points to a closed/missing/insufficient shipment
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

  /// Manual allocation: draw everything from a single open shipment.
  Future<List<ShipmentAllocation>> _allocateManual({
    required int shipmentId,
    required int quantity,
  }) async {
    final shipment = await _shipmentDao.getById(shipmentId);
    if (shipment == null) {
      throw ArgumentError('Shipment #$shipmentId not found');
    }
    if (shipment.status != VegetableShipmentStatus.open) {
      throw ArgumentError('Shipment #$shipmentId is closed');
    }
    final available = effectiveRemaining(shipment);
    if (available < quantity) {
      throw ArgumentError(
        'Shipment #$shipmentId has $available remaining, '
        'but $quantity requested',
      );
    }

    return [ShipmentAllocation(shipmentId: shipmentId, quantity: quantity)];
  }

  /// FIFO allocation: oldest open shipment first, then next, etc.
  Future<List<ShipmentAllocation>> _allocateFifo(int quantity) async {
    final openShipments = await _shipmentDao.getOpenShipmentsFifo();

    final totalAvailable = openShipments.fold<int>(
      0,
      (sum, s) => sum + effectiveRemaining(s),
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

      final available = effectiveRemaining(shipment);
      if (available <= 0) continue;

      final take = remaining <= available ? remaining : available;

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
    return open.fold<int>(0, (sum, s) => sum + effectiveRemaining(s));
  }

  /// Atomically adds [additionalToppingCount] crates used to top up the weight
  /// of other crates in [shipmentId] (with supplier's knowledge).
  ///
  /// Updates `toppingCount`, `toppingReason` (if provided), and recomputes
  /// `barnikaRemainingCount = totalBarnikaCount - barnikaSoldCount - toppingCount`.
  Future<VegetableShipment> recordTopping({
    required int shipmentId,
    required int additionalToppingCount,
    String? reason,
  }) async {
    if (additionalToppingCount <= 0) {
      throw ArgumentError('عدد برانيك التكميل يجب أن يكون أكبر من صفر');
    }

    return _shipmentDao.db.transaction(() async {
      final shipment = await _shipmentDao.getById(shipmentId);
      if (shipment == null) {
        throw ArgumentError('الشحنة #$shipmentId غير موجودة');
      }
      if (shipment.status != VegetableShipmentStatus.open) {
        throw StateError('لا يمكن تسجيل تكميل على شحنة مقفولة');
      }

      final available = effectiveRemaining(shipment);
      if (additionalToppingCount > available) {
        throw ArgumentError(
          'عدد برانيك التكميل ($additionalToppingCount) يتجاوز المتبقي المتاح ($available)',
        );
      }

      final newTopping = shipment.toppingCount + additionalToppingCount;
      final newRemaining = available - additionalToppingCount;
      final trimmedReason = reason?.trim();

      final updated = shipment.copyWith(
        toppingCount: newTopping,
        barnikaRemainingCount: newRemaining,
        toppingReason: Value(
          (trimmedReason != null && trimmedReason.isNotEmpty)
              ? trimmedReason
              : shipment.toppingReason,
        ),
      );
      await _shipmentDao.updateShipment(updated);
      return updated;
    });
  }

  /// Atomically sets the total [toppingCount] on an open shipment and updates
  /// `barnikaRemainingCount = totalBarnikaCount - barnikaSoldCount - toppingCount`.
  Future<VegetableShipment> updateToppingCount({
    required int shipmentId,
    required int toppingCount,
    String? reason,
  }) async {
    if (toppingCount < 0) {
      throw ArgumentError('عدد برانيك التكميل لا يمكن أن يكون سالباً');
    }

    return _shipmentDao.db.transaction(() async {
      final shipment = await _shipmentDao.getById(shipmentId);
      if (shipment == null) {
        throw ArgumentError('الشحنة #$shipmentId غير موجودة');
      }
      if (shipment.status != VegetableShipmentStatus.open) {
        throw StateError('لا يمكن تعديل التكميل بعد قفل الشحنة');
      }

      final newRemaining =
          shipment.totalBarnikaCount - shipment.barnikaSoldCount - toppingCount;
      if (newRemaining < 0) {
        throw ArgumentError(
          'إجمالي المباع (${shipment.barnikaSoldCount}) + التكميل ($toppingCount) '
          'يتجاوز المستلم (${shipment.totalBarnikaCount})',
        );
      }

      final updatedReason = reason == null
          ? shipment.toppingReason
          : (reason.trim().isEmpty ? null : reason.trim());

      final updated = shipment.copyWith(
        toppingCount: toppingCount,
        barnikaRemainingCount: newRemaining,
        toppingReason: Value(updatedReason),
      );
      await _shipmentDao.updateShipment(updated);
      return updated;
    });
  }

  /// Records that [quantity] empty barnikas were issued to [customerId].
  /// Optionally links the custody record to [invoiceId].
  ///
  /// Returns the ID of the created tracking record.
  Future<int> recordBarnikaOut({
    required String customerId,
    required int quantity,
    DateTime? dateOut,
    int? invoiceId,
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
        invoiceId: Value(invoiceId),
      ),
    );
  }

  /// Atomically records returned empty barnikas from [customerId] using FIFO
  /// across their outstanding custody records.
  Future<void> recordCustomerBarnikaReturn({
    required String customerId,
    required int quantityReturned,
    DateTime? dateReturned,
  }) async {
    if (customerId.isEmpty) {
      throw ArgumentError('customerId cannot be empty');
    }
    await _emptyBarnikaDao.db.transaction(() async {
      await _emptyBarnikaDao.recordCustomerReturnFifo(
        customerId: customerId,
        quantityReturned: quantityReturned,
        dateReturned: dateReturned,
      );
    });
  }
}
