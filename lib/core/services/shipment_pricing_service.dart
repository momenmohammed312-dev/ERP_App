import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';

/// Calculates costs and commissions for vegetable shipments based on
/// the shipment's [ShipmentPricingMode].
class ShipmentPricingService {
  /// Returns the cost for selling [quantity] barnikas from [shipment].
  ///
  /// - `per_unit`: `costPricePerBarnika × quantity`
  /// - `lump_sum`: `lumpSumCost / totalBarnikaCount × quantity` (approximate, for internal reports)
  /// - `commission`: `0` (shop doesn't own the goods)
  static double calculateCost(VegetableShipment shipment, int quantity) {
    switch (shipment.pricingMode) {
      case ShipmentPricingMode.perUnit:
        return (shipment.costPricePerBarnika ?? 0) * quantity;
      case ShipmentPricingMode.lumpSum:
        if (shipment.totalBarnikaCount == 0) return 0;
        return (shipment.lumpSumCost ?? 0) /
            shipment.totalBarnikaCount *
            quantity;
      case ShipmentPricingMode.commission:
        return 0;
      default:
        return 0;
    }
  }

  /// Returns the commission amount the supplier is due from a sale.
  ///
  /// `commissionAmount = sellAmount × commissionPercentage / 100`
  /// The shop keeps `sellAmount - commissionAmount`.
  static double calculateCommission(double sellAmount, double commissionPercentage) {
    return sellAmount * commissionPercentage / 100;
  }

  /// Returns the supplier due amount for a commission-based sale.
  ///
  /// `supplierDue = sellAmount - commission`
  static double calculateSupplierDue(double sellAmount, double commissionPercentage) {
    final commission = calculateCommission(sellAmount, commissionPercentage);
    return sellAmount - commission;
  }
}
