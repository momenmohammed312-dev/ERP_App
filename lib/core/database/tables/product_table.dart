import 'package:drift/drift.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  IntColumn get quantity => integer()();
  RealColumn get price => real()();
  TextColumn get status => text().nullable().withDefault(
    const Constant('Active'),
  )(); // Active/Inactive
  TextColumn get unit => text().nullable()(); // Piece, Kg, etc.
  TextColumn get category => text().nullable()(); // Product category
  TextColumn get barcode => text().nullable()(); // Product barcode
  IntColumn get cartonQuantity => integer().nullable()(); // Quantity per carton
  RealColumn get cartonPrice => real().nullable()(); // Price per carton
  RealColumn get costPrice => real().nullable()(); // Purchase cost price (for profit calculation)
  IntColumn get minStockLevel => integer().withDefault(const Constant(0))();
  BoolColumn get barneka => boolean().withDefault(const Constant(false))(); // Returnable container (برنيكه)

  /// Sync identity used only for multi-device sync (local int `id` stays for FKs).
  TextColumn get syncId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
