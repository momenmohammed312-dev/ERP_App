import 'package:pos_offline_desktop/core/database/app_database.dart';

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

  ProductEntry({this.product});

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
    };
  }
}
