import 'package:drift/drift.dart';

enum CustomerStatus {
  inactive('Inactive'),
  active('Active');

  final String value;
  const CustomerStatus(this.value);

  static CustomerStatus fromString(String? val) {
    if (val == 'Inactive') return CustomerStatus.inactive;
    return CustomerStatus.active;
  }
}

class Customers extends Table {
  TextColumn get id => text()(); // UUID primary key
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get gstinNumber => text().nullable()();
  TextColumn get email => text().nullable()(); // New
  RealColumn get openingBalance => real().withDefault(
    const Constant(0.0),
  )(); // ignore: non_constant_identifier_names
  RealColumn get totalDebt => real().withDefault(
    const Constant(0.0),
  )(); // ignore: non_constant_identifier_names
  RealColumn get totalPaid => real().withDefault(
    const Constant(0.0),
  )(); // ignore: non_constant_identifier_names
  DateTimeColumn get createdAt =>
      dateTime().nullable()(); // ignore: non_constant_identifier_names
  DateTimeColumn get updatedAt =>
      dateTime().nullable()(); // ignore: non_constant_identifier_names
  TextColumn get notes => text().nullable()(); // New
  BoolColumn get isActive => boolean().withDefault(
    const Constant(true),
  )(); // ignore: non_constant_identifier_names
  TextColumn get status => text().nullable().withDefault(
    const Constant('Active'),
  )();

  @override
  Set<Column> get primaryKey => {id};
}
