// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_payments_dao.dart';

// ignore_for_file: type=lint
mixin _$CreditPaymentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CreditPaymentsTable get creditPayments => attachedDatabase.creditPayments;
  CreditPaymentsDaoManager get managers => CreditPaymentsDaoManager(this);
}

class CreditPaymentsDaoManager {
  final _$CreditPaymentsDaoMixin _db;
  CreditPaymentsDaoManager(this._db);
  $$CreditPaymentsTableTableManager get creditPayments =>
      $$CreditPaymentsTableTableManager(
        _db.attachedDatabase,
        _db.creditPayments,
      );
}
