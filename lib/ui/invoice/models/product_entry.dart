import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';

class ProductEntry {
  Product? product;
  int quantity = 1;
  String unit = 'piece';
  double unitPrice = 0.0;
  double discount = 0.0;
  double tax = 0.0;
  double lineTotal = 0.0;
  double costPrice = 0.0;
  bool priceOverride = false;

  // Vegetable shipment allocation state (only populated on the vegetable flavor)
  List<ShipmentAllocation> allocations = [];
  Map<int, VegetableShipment> shipmentsById = {};
  String? allocationError;
  bool overrideMode = false;
  int? overrideShipmentId;

  ProductEntry({this.product});

  bool get isBarnikaTracked => product?.barneka ?? false;

  /// Total barnika quantity resolved across all allocations (empty crates issued).
  int get allocatedQuantity =>
      allocations.fold<int>(0, (sum, a) => sum + a.quantity);

  /// Whether any resolved shipment uses commission pricing.
  bool get hasCommissionShipment => shipmentsById.values
      .any((s) => s.pricingMode == ShipmentPricingMode.commission);

  Map<String, dynamic> toJson() {
    return {
      'productId': product?.id,
      'productName': product?.name,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'costPrice': costPrice,
      'discount': discount,
      'tax': tax,
      'lineTotal': lineTotal,
      'priceOverride': priceOverride,
      'allocations': allocations
          .map((a) => {'shipmentId': a.shipmentId, 'quantity': a.quantity})
          .toList(),
      'overrideShipmentId': overrideShipmentId,
    };
  }
}
