import '../app_database.dart';

class TransactionValidationError implements Exception {
  final String message;
  TransactionValidationError(this.message);

  @override
  String toString() => 'TransactionValidationError: $message';
}

class TransactionValidator {
  static void validateTransaction(LedgerTransactionsCompanion transaction) {
    // Validate entity type
    if (!['Customer', 'Supplier'].contains(transaction.entityType.value)) {
      throw TransactionValidationError(
        'Invalid entity type. Must be Customer or Supplier',
      );
    }

    // Validate reference ID
    final refId = transaction.refId.value;
    if (refId.isEmpty) {
      throw TransactionValidationError('Reference ID is required');
    }

    // Validate date
    final date = transaction.date.value;

    // Prevent future dates (unless admin override)
    final now = DateTime.now();
    if (date.isAfter(now) && !transaction.lockBatch.present) {
      throw TransactionValidationError(
        'Transaction date cannot be in the future',
      );
    }

    // Validate description
    final description = transaction.description.value;
    if (description.trim().isEmpty) {
      throw TransactionValidationError('Description is required');
    }

    // Validate origin
    final origin = transaction.origin.value;
    if (![
      'sale',
      'purchase',
      'payment',
      'opening',
      'reversal',
    ].contains(origin)) {
      throw TransactionValidationError('Invalid origin type');
    }

    // Validate debit/credit - exactly one must be > 0
    final debit = transaction.debit.value;
    final credit = transaction.credit.value;

    if (debit <= 0 && credit <= 0) {
      throw TransactionValidationError(
        'Either debit or credit must be greater than 0',
      );
    }

    if (debit > 0 && credit > 0) {
      throw TransactionValidationError('Cannot have both debit and credit > 0');
    }

    // Validate payment method for certain origins
    if (['sale', 'purchase', 'payment'].contains(origin)) {
      final paymentMethod = transaction.paymentMethod.value;
      if (paymentMethod == null || paymentMethod.isEmpty) {
        throw TransactionValidationError(
          'Payment method is required for $origin transactions',
        );
      }

      if (!['cash', 'instapay', 'bank', 'wallet'].contains(paymentMethod)) {
        throw TransactionValidationError('Invalid payment method');
      }
    }

    // Validate receipt number for sales
    if (origin == 'sale') {
      final receiptNumber = transaction.receiptNumber.value;
      if (receiptNumber == null || receiptNumber.trim().isEmpty) {
        throw TransactionValidationError(
          'Receipt number is required for sales',
        );
      }
    }
  }

  static void validateCustomerOrSupplier({
    required String name,
    String? phone,
    double? openingBalance,
  }) {
    // Validate name
    if (name.trim().isEmpty) {
      throw TransactionValidationError('Name is required');
    }

    if (name.length > 255) {
      throw TransactionValidationError('Name cannot exceed 255 characters');
    }

    // Validate phone format (basic validation)
    if (phone != null && phone.isNotEmpty) {
      if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(phone)) {
        throw TransactionValidationError('Invalid phone number format');
      }
    }

    // Validate opening balance
    // السالب مسموح: عميل موجود قبل البرنامج ممكن يبقى عنده رصيد دائن
  }

  static void validateReversalTransaction(
    LedgerTransactionsCompanion reversal,
    LedgerTransaction originalTransaction,
  ) {
    // Validate that reversal has opposite debit/credit
    final reversalDebit = reversal.debit.value;
    final reversalCredit = reversal.credit.value;
    final originalDebit = originalTransaction.debit;
    final originalCredit = originalTransaction.credit;

    if (reversalDebit != originalCredit || reversalCredit != originalDebit) {
      throw TransactionValidationError(
        'Reversal must have opposite debit/credit amounts',
      );
    }

    // Validate that reversal references original transaction in description
    final description = reversal.description.value;
    if (!description.contains(originalTransaction.id)) {
      throw TransactionValidationError(
        'Reversal description must reference original transaction',
      );
    }

    // Validate reversal origin
    if (reversal.origin.value != 'reversal') {
      throw TransactionValidationError(
        'Reversal transaction must have origin="reversal"',
      );
    }
  }

  static void validateDayLock(DateTime date) {
    final now = DateTime.now();

    // Cannot lock future dates
    if (date.isAfter(now)) {
      throw TransactionValidationError('Cannot lock future dates');
    }

    // Cannot lock today until end of day (optional business rule)
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
      if (now.isBefore(endOfDay)) {
        throw TransactionValidationError(
          'Cannot lock current day until end of day',
        );
      }
    }
  }
}
