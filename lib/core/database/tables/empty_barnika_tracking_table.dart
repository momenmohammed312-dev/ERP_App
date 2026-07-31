import 'package:drift/drift.dart';

import 'customer_table.dart';

abstract final class EmptyBarnikaStatus {
  static const outstanding = 'outstanding';
  static const partial = 'partial';
  static const returned = 'returned';
}

class EmptyBarnikaTracking extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get customerId => text().references(Customers, #id)();

  DateTimeColumn get dateOut => dateTime()();

  IntColumn get quantityOut => integer()();

  DateTimeColumn get dateReturned => dateTime().nullable()();

  IntColumn get quantityReturned =>
      integer().withDefault(const Constant(0))();

  /// [EmptyBarnikaStatus.outstanding] | [EmptyBarnikaStatus.partial] |
  /// [EmptyBarnikaStatus.returned]
  TextColumn get status =>
      text().withDefault(const Constant(EmptyBarnikaStatus.outstanding))();
}
