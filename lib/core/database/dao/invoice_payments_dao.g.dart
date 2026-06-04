// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_payments_dao.dart';

// ignore_for_file: type=lint
mixin _$InvoicePaymentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $InvoicePaymentsTable get invoicePayments => attachedDatabase.invoicePayments;
  InvoicePaymentsDaoManager get managers => InvoicePaymentsDaoManager(this);
}

class InvoicePaymentsDaoManager {
  final _$InvoicePaymentsDaoMixin _db;
  InvoicePaymentsDaoManager(this._db);
  $$InvoicesTableTableManager get invoices =>
      $$InvoicesTableTableManager(_db.attachedDatabase, _db.invoices);
  $$InvoicePaymentsTableTableManager get invoicePayments =>
      $$InvoicePaymentsTableTableManager(
        _db.attachedDatabase,
        _db.invoicePayments,
      );
}
