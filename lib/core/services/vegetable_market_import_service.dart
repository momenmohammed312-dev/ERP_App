import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/tables/empty_barnika_tracking_table.dart';
import '../database/tables/supplier_table.dart';
import '../utils/arabic_name_normalizer.dart';

class ImportResult {
  final int suppliers;
  final int customers;
  final int shipments;
  final int sales;
  final int expenses;
  final int collections;
  final int emptyBarnika;
  final List<String> errors;
  final int skippedDuplicates;
  final List<String> duplicateDetails;
  final List<String> warnings;

  ImportResult({
    required this.suppliers,
    required this.customers,
    required this.shipments,
    required this.sales,
    required this.expenses,
    required this.collections,
    required this.emptyBarnika,
    required this.errors,
    this.skippedDuplicates = 0,
    this.duplicateDetails = const [],
    this.warnings = const [],
  });

  int get total =>
      suppliers + customers + shipments + sales + expenses + collections + emptyBarnika;
}

class OpeningBalanceCustomerRow {
  final int rowNumber;
  final String name;
  final String? phone;
  final String? address;
  final double openingDebt;
  final int openingBarnikas;
  final String? notes;

  const OpeningBalanceCustomerRow({
    required this.rowNumber,
    required this.name,
    this.phone,
    this.address,
    this.openingDebt = 0.0,
    this.openingBarnikas = 0,
    this.notes,
  });
}

class OpeningBalanceSupplierRow {
  final int rowNumber;
  final String name;
  final String? phone;
  final String? address;
  final double openingCredit;
  final String? notes;

  const OpeningBalanceSupplierRow({
    required this.rowNumber,
    required this.name,
    this.phone,
    this.address,
    this.openingCredit = 0.0,
    this.notes,
  });
}

class VegetableExcelPreview {
  final List<OpeningBalanceCustomerRow> customers;
  final List<OpeningBalanceSupplierRow> suppliers;
  final int shipmentsCount;
  final int salesCount;
  final int expensesCount;
  final int collectionsCount;
  final int emptyBarnikaRecordsCount;
  final List<String> duplicateWarnings;
  final List<String> detectedSheets;

  const VegetableExcelPreview({
    required this.customers,
    required this.suppliers,
    this.shipmentsCount = 0,
    this.salesCount = 0,
    this.expensesCount = 0,
    this.collectionsCount = 0,
    this.emptyBarnikaRecordsCount = 0,
    this.duplicateWarnings = const [],
    this.detectedSheets = const [],
  });

  double get customersOpeningDebtTotal =>
      customers.fold(0.0, (sum, r) => sum + r.openingDebt);

  int get openingBarnikaTotal =>
      customers.fold(0, (sum, r) => sum + r.openingBarnikas);

  double get suppliersOpeningCreditTotal =>
      suppliers.fold(0.0, (sum, r) => sum + r.openingCredit);

  int get totalRows =>
      customers.length +
      suppliers.length +
      shipmentsCount +
      salesCount +
      expensesCount +
      collectionsCount +
      emptyBarnikaRecordsCount;
}

class VegetableMarketImportService {
  final AppDatabase _db;
  static const _productName = 'بارنيكة خضار';
  int? _defaultProductId;
  final _uuid = const Uuid();
  final _existingSupplierNames = <String>{};
  final _existingCustomerNames = <String>{};
  final _existingShipmentNumbers = <String>{};

  VegetableMarketImportService(this._db);

  static bool _isExcelPayload(String filePath, Uint8List bytes) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) return true;
    // PK\x03\x04 zip magic header for .xlsx
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  /// Generates a ready-to-fill Arabic `.xlsx` opening-balance template with
  /// `العملاء` and `الموردين` sheets.
  static Uint8List generateOpeningBalanceTemplateBytes() {
    final excel = Excel.createExcel();

    final customersSheet = excel['العملاء'];
    customersSheet.appendRow([
      TextCellValue('الاسم'),
      TextCellValue('الهاتف'),
      TextCellValue('العنوان'),
      TextCellValue('رصيد الآجل الافتتاحي'),
      TextCellValue('رصيد البرانيك الفارغة'),
      TextCellValue('ملاحظات'),
    ]);
    customersSheet.appendRow([
      TextCellValue('الحاج إبراهيم (مثال)'),
      TextCellValue('01001234567'),
      TextCellValue('سوق العبور'),
      DoubleCellValue(1500.0),
      IntCellValue(10),
      TextCellValue('عميل جملة'),
    ]);

    final suppliersSheet = excel['الموردين'];
    suppliersSheet.appendRow([
      TextCellValue('الاسم'),
      TextCellValue('الهاتف'),
      TextCellValue('العنوان'),
      TextCellValue('الرصيد الافتتاحي'),
      TextCellValue('ملاحظات'),
    ]);
    suppliersSheet.appendRow([
      TextCellValue('مزارع النور (مثال)'),
      TextCellValue('01112345678'),
      TextCellValue('بنها'),
      DoubleCellValue(5000.0),
      TextCellValue('مورد طماطم'),
    ]);

    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    excel.setDefaultSheet('العملاء');

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('تعذر إنشاء ملف القالب');
    }
    return Uint8List.fromList(encoded);
  }

  Future<VegetableExcelPreview> previewExcelBytes(Uint8List bytes) async {
    final parsed = _parseExcelWorkbook(bytes);
    final duplicateWarnings = await _detectDuplicates(
      parsed.customers,
      parsed.suppliers,
    );
    return VegetableExcelPreview(
      customers: parsed.customers,
      suppliers: parsed.suppliers,
      shipmentsCount: parsed.legacyShipments.length,
      salesCount: parsed.legacySales.length,
      expensesCount: parsed.legacyExpenses.length,
      collectionsCount: parsed.legacyCollections.length,
      emptyBarnikaRecordsCount: parsed.legacyEmptyBarnika.length,
      duplicateWarnings: duplicateWarnings,
      detectedSheets: parsed.detectedSheets,
    );
  }

  Future<ImportResult> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Import file not found', filePath);
    }
    final bytes = await file.readAsBytes();
    if (_isExcelPayload(filePath, bytes)) {
      return importFromExcelBytes(bytes);
    }
    final contents = utf8.decode(bytes);
    return _importData(json.decode(contents) as Map<String, dynamic>);
  }

  Future<ImportResult> importFromExcelBytes(
    Uint8List bytes, {
    bool importCustomers = true,
    bool importSuppliers = true,
  }) async {
    final parsed = _parseExcelWorkbook(bytes);
    final errors = <String>[];
    final duplicateDetails = <String>[];
    final warnings = <String>[];

    var cCount = 0;
    var sCount = 0;
    var ebCount = 0;
    var skippedDuplicates = 0;

    final existingCustomers = await _db.customerDao.getAllCustomers();
    final existingSuppliers = (await _db.supplierDao.getAllSuppliers())
        .where((s) => s.id != DefaultSupplier.unknownId)
        .toList();

    final knownCustomers = existingCustomers
        .map((c) => (name: c.name, phone: c.phone))
        .toList();
    final knownSuppliers = existingSuppliers
        .map((s) => (name: s.name, phone: s.phone))
        .toList();

    final now = DateTime.now();

    await _db.transaction(() async {
      if (importSuppliers) {
        for (final row in parsed.suppliers) {
          try {
            final match = _findMatchingEntry(
              name: row.name,
              phone: row.phone,
              existing: knownSuppliers,
            );
            if (match != null) {
              skippedDuplicates++;
              final msg =
                  'مورد (صف ${row.rowNumber}): "${row.name}" مطابق للموجود "$match" — تم التخطي';
              duplicateDetails.add(msg);
              warnings.add(msg);
              continue;
            }
            final id = _uuid.v4();
            await _db.into(_db.suppliers).insert(
                  SuppliersCompanion.insert(
                    id: id,
                    name: row.name,
                    phone: Value(row.phone),
                    address: Value(row.address),
                    openingBalance: Value(row.openingCredit),
                  ),
                );
            knownSuppliers.add((name: row.name, phone: row.phone));
            sCount++;
          } catch (e) {
            errors.add('مورد صف ${row.rowNumber} "${row.name}": $e');
          }
        }
      }

      if (importCustomers) {
        for (final row in parsed.customers) {
          try {
            final match = _findMatchingEntry(
              name: row.name,
              phone: row.phone,
              existing: knownCustomers,
            );
            if (match != null) {
              skippedDuplicates++;
              final msg =
                  'عميل (صف ${row.rowNumber}): "${row.name}" مطابق للموجود "$match" — تم التخطي';
              duplicateDetails.add(msg);
              warnings.add(msg);
              continue;
            }
            final id = _uuid.v4();
            await _db.into(_db.customers).insert(
                  CustomersCompanion.insert(
                    id: id,
                    name: row.name,
                    phone: Value(row.phone),
                    address: Value(row.address),
                    openingBalance: Value(row.openingDebt),
                    notes: Value(row.notes),
                  ),
                );
            if (row.openingBarnikas > 0) {
              await _db.into(_db.emptyBarnikaTracking).insert(
                    EmptyBarnikaTrackingCompanion.insert(
                      customerId: id,
                      dateOut: now,
                      quantityOut: row.openingBarnikas,
                      quantityReturned: const Value(0),
                      status: const Value(EmptyBarnikaStatus.outstanding),
                    ),
                  );
              ebCount++;
            }
            knownCustomers.add((name: row.name, phone: row.phone));
            cCount++;
          } catch (e) {
            errors.add('عميل صف ${row.rowNumber} "${row.name}": $e');
          }
        }
      }
    });

    // If legacy multi-sheet workbook also contains shipments/sales/expenses/collections,
    // import them through the existing pipeline for full backward compatibility.
    var shCount = 0;
    var saCount = 0;
    var eCount = 0;
    var colCount = 0;
    if (parsed.hasLegacyOperationalData) {
      final legacyResult = await _importData({
        'suppliers': const <Map<String, dynamic>>[],
        'customers': const <Map<String, dynamic>>[],
        'shipments': parsed.legacyShipments,
        'sales': parsed.legacySales,
        'expenses': parsed.legacyExpenses,
        'collections': parsed.legacyCollections,
        'emptyBarnikaRecords': parsed.legacyEmptyBarnika,
      });
      shCount = legacyResult.shipments;
      saCount = legacyResult.sales;
      eCount = legacyResult.expenses;
      colCount = legacyResult.collections;
      ebCount += legacyResult.emptyBarnika;
      errors.addAll(legacyResult.errors);
    }

    return ImportResult(
      suppliers: sCount,
      customers: cCount,
      shipments: shCount,
      sales: saCount,
      expenses: eCount,
      collections: colCount,
      emptyBarnika: ebCount,
      errors: errors,
      skippedDuplicates: skippedDuplicates,
      duplicateDetails: duplicateDetails,
      warnings: warnings,
    );
  }

  Future<List<String>> _detectDuplicates(
    List<OpeningBalanceCustomerRow> customers,
    List<OpeningBalanceSupplierRow> suppliers,
  ) async {
    final warnings = <String>[];
    final existingCustomers = (await _db.customerDao.getAllCustomers())
        .map((c) => (name: c.name, phone: c.phone))
        .toList();
    final existingSuppliers = (await _db.supplierDao.getAllSuppliers())
        .where((s) => s.id != DefaultSupplier.unknownId)
        .map((s) => (name: s.name, phone: s.phone))
        .toList();

    for (final c in customers) {
      final match = _findMatchingEntry(
        name: c.name,
        phone: c.phone,
        existing: existingCustomers,
      );
      if (match != null) {
        warnings.add('عميل صف ${c.rowNumber}: "${c.name}" مشابه/مطابق لـ "$match"');
      } else {
        existingCustomers.add((name: c.name, phone: c.phone));
      }
    }

    for (final s in suppliers) {
      final match = _findMatchingEntry(
        name: s.name,
        phone: s.phone,
        existing: existingSuppliers,
      );
      if (match != null) {
        warnings.add('مورد صف ${s.rowNumber}: "${s.name}" مشابه/مطابق لـ "$match"');
      } else {
        existingSuppliers.add((name: s.name, phone: s.phone));
      }
    }
    return warnings;
  }

  static String? _findMatchingEntry({
    required String name,
    required String? phone,
    required List<({String name, String? phone})> existing,
  }) {
    final normPhone = _normalizePhoneDigits(phone);
    for (final item in existing) {
      if (ArabicNameNormalizer.areEquivalent(name, item.name)) {
        return item.name;
      }
      if (normPhone.isNotEmpty) {
        final itemPhone = _normalizePhoneDigits(item.phone);
        if (itemPhone.isNotEmpty && itemPhone == normPhone) {
          return '${item.name} ($itemPhone)';
        }
      }
    }
    return null;
  }

  static String _normalizePhoneDigits(String? phone) {
    if (phone == null) return '';
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  _ParsedExcelWorkbook _parseExcelWorkbook(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final customers = <OpeningBalanceCustomerRow>[];
    final consolidatedCustomers = <String, OpeningBalanceCustomerRow>{};
    final transactionalCustomerKeys = <String>{};
    final suppliers = <OpeningBalanceSupplierRow>[];
    final consolidatedSuppliers = <String, OpeningBalanceSupplierRow>{};
    final collectionsByNormCustomer = <String, double>{};
    final legacyShipments = <Map<String, dynamic>>[];
    final legacySales = <Map<String, dynamic>>[];
    final legacyExpenses = <Map<String, dynamic>>[];
    final legacyCollections = <Map<String, dynamic>>[];
    final legacyEmptyBarnika = <Map<String, dynamic>>[];
    final detectedSheets = excel.tables.keys.toList();

    for (final entry in excel.tables.entries) {
      final sheetKey = _normalizeSheetKey(entry.key);
      final sheet = entry.value;
      if (sheet.rows.length <= 1) continue;

      final headerRowIndex = _findHeaderRowIndex(sheet);
      if (headerRowIndex + 1 >= sheet.rows.length) continue;

      final headerRow = sheet.rows[headerRowIndex];
      final headerKeys = <int, String>{};
      for (var i = 0; i < headerRow.length; i++) {
        final raw = _cellToString(headerRow[i]);
        if (raw.isNotEmpty) {
          headerKeys[i] = _normalizeHeaderKey(raw);
        }
      }
      if (headerKeys.isEmpty) continue;

      if (_isCustomerSheet(sheetKey)) {
        final isTransactionalCustomer = _hasAnyHeader(headerKeys, const [
          'عدد البرانيك',
          'سعر بيع البرنيكة',
          'سعر البرنيكة',
          'إجمالي المستحق',
          'البرانيك المستلمه',
          'البرانيك المستلمة',
        ]);

        for (var r = headerRowIndex + 1; r < sheet.rows.length; r++) {
          final row = sheet.rows[r];
          final map = _rowToHeaderMap(row, headerKeys);
          final name = _pickString(map, const [
            'name',
            'الاسم',
            'اسم العميل',
            'اسم الزبون',
            'العميل',
            'الزبون',
          ]);
          if (name == null || name.isEmpty) continue;
          final normName = ArabicNameNormalizer.normalize(name);
          if (_isSummaryRowName(normName)) continue;
          if (const {'نقديه', 'نقدي', 'كاش', 'عميل نقدي'}.contains(normName)) {
            continue;
          }

          final phone = _pickString(map, const [
            'phone',
            'الهاتف',
            'التليفون',
            'الموبايل',
            'رقم الهاتف',
          ]);
          final address = _pickString(map, const ['address', 'العنوان']);

          double? openingDebt = _pickDouble(map, const [
            'openingbalance',
            'opening_balance',
            'openingdebt',
            'balance',
            'رصيد الاجل الافتتاحي',
            'الرصيد الافتتاحي',
            'رصيد افتتاحي',
            'الاجل',
            'المديونية',
            'الباقي (اجل)',
            'الباقي',
          ]);
          if (openingDebt == null) {
            final qty = _pickDouble(map, const [
              'عدد البرانيك',
              'الكمية',
              'quantity',
            ]);
            final unitPrice = _pickDouble(map, const [
              'سعر بيع البرنيكة',
              'سعر البرنيكة',
              'السعر',
              'unitprice',
              'price',
            ]);
            final paid =
                _pickDouble(map, const ['المدفوع', 'مدفوع', 'paid']) ?? 0.0;
            final discount =
                _pickDouble(map, const ['خصومات', 'الخصم', 'خصم', 'discount']) ??
                    0.0;
            if (qty != null && unitPrice != null) {
              openingDebt = math.max(0.0, (qty * unitPrice) - paid - discount);
            } else {
              openingDebt = 0.0;
            }
          }

          int? openingBarnikas = _pickInt(map, const [
            'openingbarnika',
            'opening_barnika',
            'openingbarnikas',
            'barnika',
            'barnikas',
            'رصيد البرانيك الفارغة',
            'البرانيك الفارغة',
            'عهدة البرانيك',
            'البرانيك المتبقيه',
            'البرانيك المتبقية',
            'البرانيك',
            'برانيك',
          ]);
          if (openingBarnikas == null) {
            final qty = _pickInt(map, const [
              'عدد البرانيك',
              'الكمية',
              'quantity',
            ]);
            final received = _pickInt(map, const [
                  'البرانيك المستلمه',
                  'البرانيك المستلمة',
                  'المستلم',
                ]) ??
                0;
            if (qty != null) {
              openingBarnikas = math.max(0, qty - received);
            } else {
              openingBarnikas = 0;
            }
          }

          final notes = _pickString(map, const [
            'notes',
            'note',
            'ملاحظات',
            'ملاحظة',
            'type',
            'نوع الزبون',
          ]);
          final rowObj = OpeningBalanceCustomerRow(
            rowNumber: r + 1,
            name: name.trim(),
            phone: phone?.isNotEmpty == true ? phone : null,
            address: address?.isNotEmpty == true ? address : null,
            openingDebt: openingDebt < 0 ? 0.0 : openingDebt,
            openingBarnikas: openingBarnikas < 0 ? 0 : openingBarnikas,
            notes: notes?.isNotEmpty == true ? notes : null,
          );

          if (isTransactionalCustomer) {
            transactionalCustomerKeys.add(normName);
            final prev = consolidatedCustomers[normName];
            if (prev == null) {
              consolidatedCustomers[normName] = rowObj;
            } else {
              consolidatedCustomers[normName] = OpeningBalanceCustomerRow(
                rowNumber: prev.rowNumber,
                name: prev.name,
                phone: prev.phone ?? rowObj.phone,
                address: prev.address ?? rowObj.address,
                openingDebt: prev.openingDebt + rowObj.openingDebt,
                openingBarnikas: prev.openingBarnikas + rowObj.openingBarnikas,
                notes: prev.notes ?? rowObj.notes,
              );
            }
          } else {
            // Keep individual rows on opening-balance templates so duplicate
            // Arabic names are surfaced to the user instead of silently merged.
            customers.add(rowObj);
          }
        }
      } else if (_isSupplierSheet(sheetKey)) {
        final isTransactionalSupplier = _hasAnyHeader(headerKeys, const [
          'رقم الشحنة',
          'عدد البرانيك',
          'سعر الطماطم للبرنيكة',
          'إجمالي التكلفة',
        ]);

        for (var r = headerRowIndex + 1; r < sheet.rows.length; r++) {
          final row = sheet.rows[r];
          final map = _rowToHeaderMap(row, headerKeys);
          final name = _pickString(map, const [
            'name',
            'الاسم',
            'اسم المورد',
            'المورد',
          ]);
          if (name == null || name.isEmpty) continue;
          final normName = ArabicNameNormalizer.normalize(name);
          if (_isSummaryRowName(normName)) continue;

          final phone = _pickString(map, const [
            'phone',
            'الهاتف',
            'التليفون',
            'الموبايل',
            'رقم الهاتف',
          ]);
          final address = _pickString(map, const ['address', 'العنوان']);
          final openingCredit = _pickDouble(map, const [
                'openingbalance',
                'opening_balance',
                'openingcredit',
                'balance',
                'الرصيد الافتتاحي',
                'رصيد المورد الافتتاحي',
                'رصيد افتتاحي',
                'الرصيد',
                'المستحق',
              ]) ??
              0.0;
          final notes =
              _pickString(map, const ['notes', 'note', 'ملاحظات', 'ملاحظة']);
          final rowObj = OpeningBalanceSupplierRow(
            rowNumber: r + 1,
            name: name.trim(),
            phone: phone?.isNotEmpty == true ? phone : null,
            address: address?.isNotEmpty == true ? address : null,
            openingCredit: openingCredit < 0 ? 0.0 : openingCredit,
            notes: notes?.isNotEmpty == true ? notes : null,
          );

          if (isTransactionalSupplier) {
            final prev = consolidatedSuppliers[normName];
            if (prev == null) {
              consolidatedSuppliers[normName] = rowObj;
            } else {
              consolidatedSuppliers[normName] = OpeningBalanceSupplierRow(
                rowNumber: prev.rowNumber,
                name: prev.name,
                phone: prev.phone ?? rowObj.phone,
                address: prev.address ?? rowObj.address,
                openingCredit: prev.openingCredit + rowObj.openingCredit,
                notes: prev.notes ?? rowObj.notes,
              );
            }
          } else {
            suppliers.add(rowObj);
          }
        }
      } else if (_isCollectionSheet(sheetKey)) {
        for (var r = headerRowIndex + 1; r < sheet.rows.length; r++) {
          final row = sheet.rows[r];
          final map = _rowToHeaderMap(row, headerKeys);
          final name = _pickString(map, const [
            'customername',
            'name',
            'اسم الزبون',
            'اسم العميل',
            'الاسم',
            'العميل',
            'الزبون',
          ]);
          final amount = _pickDouble(map, const [
            'amount',
            'المبلغ المحصل',
            'المحصل',
            'المبلغ',
            'paid',
          ]);
          if (name != null &&
              name.isNotEmpty &&
              amount != null &&
              amount > 0) {
            final normName = ArabicNameNormalizer.normalize(name);
            collectionsByNormCustomer[normName] =
                (collectionsByNormCustomer[normName] ?? 0.0) + amount;
          }
        }

        // Only expose canonical English-keyed legacy rows when no Arabic
        // opening/transactional structure is present.
        final rawRows = _rowsToRawMaps(sheet, headerRowIndex);
        if (rawRows.isNotEmpty && rawRows.first.containsKey('customerName')) {
          legacyCollections.addAll(rawRows);
        }
      } else if (sheetKey == 'shipments' || sheetKey == 'الشحنات') {
        final rawRows = _rowsToRawMaps(sheet, headerRowIndex);
        if (rawRows.isNotEmpty && rawRows.first.containsKey('shipmentNumber')) {
          legacyShipments.addAll(rawRows);
        }
      } else if (sheetKey == 'sales' || sheetKey == 'المبيعات') {
        final rawRows = _rowsToRawMaps(sheet, headerRowIndex);
        if (rawRows.isNotEmpty && rawRows.first.containsKey('totalAmount')) {
          legacySales.addAll(rawRows);
        }
      } else if (sheetKey == 'expenses' ||
          sheetKey == 'المصروفات' ||
          sheetKey == 'مصروفات') {
        final rawRows = _rowsToRawMaps(sheet, headerRowIndex);
        if (rawRows.isNotEmpty && rawRows.first.containsKey('description')) {
          legacyExpenses.addAll(rawRows);
        }
      } else if (sheetKey == 'emptybarnikarecords' ||
          sheetKey == 'البرانيكالفاضية' ||
          sheetKey == 'البرانيك') {
        final rawRows = _rowsToRawMaps(sheet, headerRowIndex);
        if (rawRows.isNotEmpty && rawRows.first.containsKey('quantityOut')) {
          legacyEmptyBarnika.addAll(rawRows);
        }
      }
    }

    if (consolidatedCustomers.isNotEmpty) {
      for (final entry in consolidatedCustomers.entries) {
        final collected = transactionalCustomerKeys.contains(entry.key)
            ? (collectionsByNormCustomer[entry.key] ?? 0.0)
            : 0.0;
        final netDebt = math.max(0.0, entry.value.openingDebt - collected);
        customers.add(
          OpeningBalanceCustomerRow(
            rowNumber: entry.value.rowNumber,
            name: entry.value.name,
            phone: entry.value.phone,
            address: entry.value.address,
            openingDebt: netDebt,
            openingBarnikas: entry.value.openingBarnikas,
            notes: entry.value.notes,
          ),
        );
      }
    }

    if (consolidatedSuppliers.isNotEmpty) {
      suppliers.addAll(consolidatedSuppliers.values);
    }

    return _ParsedExcelWorkbook(
      customers: customers,
      suppliers: suppliers,
      legacyShipments: legacyShipments,
      legacySales: legacySales,
      legacyExpenses: legacyExpenses,
      legacyCollections: legacyCollections,
      legacyEmptyBarnika: legacyEmptyBarnika,
      detectedSheets: detectedSheets,
    );
  }

  static int _findHeaderRowIndex(Sheet sheet) {
    const keywords = [
      'الاسم',
      'اسم الزبون',
      'اسم العميل',
      'اسم المورد',
      'المورد',
      'رقم الشحنة',
      'عدد البرانيك',
      'البند',
      'المبلغ',
      'المبلغ المحصل',
      'name',
      'phone',
      'الرصيد الافتتاحي',
      'رصيد الآجل الافتتاحي',
    ];
    final normKeywords = keywords.map(_normalizeHeaderKey).toSet();
    final limit = math.min(10, sheet.rows.length);
    for (var r = 0; r < limit; r++) {
      final row = sheet.rows[r];
      var nonEmpty = 0;
      var hasMatch = false;
      for (final cell in row) {
        final raw = _cellToString(cell);
        if (raw.isEmpty) continue;
        nonEmpty++;
        final norm = _normalizeHeaderKey(raw);
        if (normKeywords.contains(norm) ||
            normKeywords.any((k) => norm.contains(k))) {
          hasMatch = true;
        }
      }
      if (nonEmpty >= 2 && hasMatch) {
        return r;
      }
    }
    return 0;
  }

  static bool _hasAnyHeader(Map<int, String> headerKeys, List<String> candidates) {
    final values = headerKeys.values.toList();
    for (final c in candidates) {
      final norm = _normalizeHeaderKey(c);
      final compact = norm.replaceAll(' ', '');
      for (final v in values) {
        if (v == norm || v.replaceAll(' ', '') == compact) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isSummaryRowName(String normName) =>
      normName.isEmpty ||
      normName == 'اجمالي' ||
      normName == 'مجموع' ||
      normName.startsWith('اجمالي ') ||
      normName.startsWith('مجموع ');

  static bool _isCollectionSheet(String key) =>
      key == 'collections' ||
      key == 'التحصيلات' ||
      key == 'تحصيلات' ||
      key.contains('تحصيل');

  static String _normalizeSheetKey(String raw) =>
      ArabicNameNormalizer.normalize(raw).replaceAll(' ', '');

  static bool _isCustomerSheet(String key) => const {
        'customers',
        'customer',
        'العملاء',
        'عملاء',
        'الزباين',
        'زباين',
        'عملا',
      }.contains(key) ||
      key.contains('عميل') ||
      key.contains('زبون') ||
      key.contains('عملا') ||
      key.contains('زباين');

  static bool _isSupplierSheet(String key) => const {
        'suppliers',
        'supplier',
        'الموردين',
        'الموردون',
        'موردين',
        'موردون',
      }.contains(key) ||
      key.contains('مورد');

  static String _normalizeHeaderKey(String raw) {
    final normAr = ArabicNameNormalizer.normalize(raw);
    if (normAr.isNotEmpty) return normAr;
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Map<String, String> _rowToHeaderMap(
    List<Data?> row,
    Map<int, String> headerKeys,
  ) {
    final out = <String, String>{};
    for (final entry in headerKeys.entries) {
      if (entry.key < row.length) {
        final v = _cellToString(row[entry.key]);
        if (v.isNotEmpty) {
          out[entry.value] = v;
        }
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _rowsToRawMaps(
    Sheet sheet,
    int headerRowIndex,
  ) {
    final headerRow = sheet.rows[headerRowIndex];
    final cols = <int, String>{};
    for (var i = 0; i < headerRow.length; i++) {
      final h = _cellToString(headerRow[i]);
      if (h.isNotEmpty) cols[i] = h;
    }
    final rows = <Map<String, dynamic>>[];
    for (var r = headerRowIndex + 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final map = <String, dynamic>{};
      var hasVal = false;
      for (final c in cols.entries) {
        if (c.key < row.length) {
          final v = row[c.key]?.value;
          if (v != null && v is! FormulaCellValue) {
            final s = _cellToString(row[c.key]);
            if (s.isNotEmpty) {
              map[c.value] = v is IntCellValue
                  ? v.value
                  : (v is DoubleCellValue ? v.value : s);
              hasVal = true;
            }
          }
        }
      }
      if (hasVal) rows.add(map);
    }
    return rows;
  }

  static String? _pickString(Map<String, String> map, List<String> aliases) {
    for (final alias in aliases) {
      final normAlias = _normalizeHeaderKey(alias);
      final compactAlias = normAlias.replaceAll(' ', '');
      if (map.containsKey(normAlias)) return map[normAlias];
      for (final entry in map.entries) {
        final kCompact = entry.key.replaceAll(' ', '');
        if (kCompact == compactAlias || entry.key == alias.toLowerCase()) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static double? _pickDouble(Map<String, String> map, List<String> aliases) {
    final raw = _pickString(map, aliases);
    if (raw == null || raw.isEmpty) return null;
    final cleaned = raw.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  static int? _pickInt(Map<String, String> map, List<String> aliases) {
    final d = _pickDouble(map, aliases);
    return d?.round();
  }

  static String _cellToString(Data? cell) {
    final val = cell?.value;
    if (val == null || val is FormulaCellValue) return '';
    if (val is TextCellValue) return val.value.text?.trim() ?? val.value.toString().trim();
    if (val is IntCellValue) return val.value.toString();
    if (val is DoubleCellValue) {
      final d = val.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (val is BoolCellValue) return val.value ? 'true' : 'false';
    return val.toString().trim();
  }

  Future<ImportResult> importFromJsonString(String jsonString) async {
    return _importData(json.decode(jsonString) as Map<String, dynamic>);
  }

  Future<ImportResult> _importData(Map<String, dynamic> data) async {
    final errors = <String>[];
    var sCount = 0;
    var cCount = 0;
    var shCount = 0;
    var saCount = 0;
    var eCount = 0;
    var colCount = 0;
    var ebCount = 0;

    final allSuppliers = (data['suppliers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allCustomers = (data['customers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allShipments = (data['shipments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allSales = (data['sales'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allExpenses = (data['expenses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allCollections = (data['collections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allEmptyBarnika =
        (data['emptyBarnikaRecords'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final names = await Future.wait([
      _existingSupplierNamesFromDb(),
      _existingCustomerNamesFromDb(),
      _existingShipmentNumbersFromDb(),
    ]);
    _existingSupplierNames.addAll(names[0]);
    _existingCustomerNames.addAll(names[1]);
    _existingShipmentNumbers.addAll(names[2]);

    _defaultProductId = await _findOrCreateProduct();

    final shipmentUuidToId = <String, int>{};
    final customerNameToId = <String, String>{};

    for (final c in allCustomers) {
      final id = c['id'] as String;
      final name = c['name'] as String;
      customerNameToId[name] = id;
    }

    await _db.transaction(() async {
      for (final s in allSuppliers) {
        try {
          await _importSupplier(s);
          sCount++;
        } catch (e) {
          errors.add('Supplier "${s['name']}": $e');
        }
      }

      for (final c in allCustomers) {
        try {
          await _importCustomer(c);
          cCount++;
        } catch (e) {
          errors.add('Customer "${c['name']}": $e');
        }
      }

      for (final s in allShipments) {
        try {
          final newId = await _importShipment(s);
          final uuid = s['id'] as String;
          shipmentUuidToId[uuid] = newId;
          shCount++;
        } catch (e) {
          errors.add('Shipment "${s['shipmentNumber']}": $e');
        }
      }

      for (final sale in allSales) {
        try {
          await _importSale(sale, shipmentUuidToId);
          saCount++;
        } catch (e) {
          errors.add('Sale "${sale['customerName']}" ${sale['date']}: $e');
        }
      }

      for (final exp in allExpenses) {
        try {
          await _importExpense(exp);
          eCount++;
        } catch (e) {
          errors.add('Expense ${exp['description']}: $e');
        }
      }

      for (final col in allCollections) {
        try {
          await _importCollection(col, customerNameToId);
          colCount++;
        } catch (e) {
          errors.add('Collection ${col['customerName']} ${col['amount']}: $e');
        }
      }

      for (final eb in allEmptyBarnika) {
        try {
          await _importEmptyBarnika(eb);
          ebCount++;
        } catch (e) {
          errors.add('EmptyBarnika ${eb['customerName']}: $e');
        }
      }
    });

    return ImportResult(
      suppliers: sCount,
      customers: cCount,
      shipments: shCount,
      sales: saCount,
      expenses: eCount,
      collections: colCount,
      emptyBarnika: ebCount,
      errors: errors,
    );
  }

  Future<Set<String>> _existingSupplierNamesFromDb() async {
    final suppliers = await _db.supplierDao.getAllSuppliers();
    return suppliers.map((s) => s.name).toSet();
  }

  Future<Set<String>> _existingCustomerNamesFromDb() async {
    final customers = await _db.customerDao.getAllCustomers();
    return customers.map((c) => c.name).toSet();
  }

  Future<Set<String>> _existingShipmentNumbersFromDb() async {
    final shipments = await _db.vegetableShipmentDao.getAll();
    return shipments.map((s) => s.shipmentNumber).toSet();
  }

  Future<int> _findOrCreateProduct() async {
    final existing = await (_db.select(_db.products)
          ..where((p) => p.name.equals(_productName)))
        .get();
    if (existing.isNotEmpty) {
      return existing.first.id;
    }
    return _db.into(_db.products).insert(ProductsCompanion.insert(
          name: _productName,
          quantity: 0,
          price: 0,
          unit: Value('بارنيكة'),
          category: Value('خضار'),
          barneka: Value(true),
        ));
  }

  Future<void> _importSupplier(Map<String, dynamic> s) async {
    final name = s['name'] as String;
    if (_existingSupplierNames.contains(name)) return;
    // Reconcile against the DB by stable id first, then by normalized
    // identity. Never auto-merge: ambiguous matches are skipped and logged,
    // and a locally deactivated supplier is never resurrected by import
    // (its status is preserved).
    final incomingId = s['id'] as String?;
    if (incomingId != null) {
      final byId = await _db.supplierDao.getSupplierById(incomingId);
      if (byId != null) {
        _existingSupplierNames.add(name);
        return;
      }
    }
    final conflicts = await _db.supplierDao.findDuplicateSuppliers(
      name: name,
      phone: (s['phone'] as String?)?.isNotEmpty == true
          ? s['phone'] as String
          : null,
    );
    if (conflicts.length == 1) {
      final local = conflicts.first;
      await _db.supplierDao.updateSupplier(
        SuppliersCompanion(
          id: Value(local.id),
          name: Value(name),
          phone: (s['phone'] as String?)?.isNotEmpty == true
              ? Value(s['phone'] as String)
              : Value(local.phone),
          address: (s['address'] as String?)?.isNotEmpty == true
              ? Value(s['address'] as String)
              : Value(local.address),
          status: Value(local.status),
        ),
      );
      _existingSupplierNames.add(name);
      return;
    }
    if (conflicts.length > 1) {
      debugPrint(
        '[Import] ambiguous supplier "$name" matches ${conflicts.length} rows — skipped, no auto-merge',
      );
      _existingSupplierNames.add(name);
      return;
    }
    await _db.into(_db.suppliers).insert(SuppliersCompanion.insert(
          id: s['id'] as String,
          name: name,
          phone: Value((s['phone'] as String?)?.isNotEmpty == true ? s['phone'] as String : null),
          address:
              Value((s['address'] as String?)?.isNotEmpty == true ? s['address'] as String : null),
          status: Value(s['status'] as String? ?? 'Active'),
        ));
    _existingSupplierNames.add(name);
  }

  Future<void> _importCustomer(Map<String, dynamic> c) async {
    final name = c['name'] as String;
    if (_existingCustomerNames.contains(name)) return;
    final status = c['status'] as String? ?? 'Active';
    final notes = c['type'] as String?;
    await _db.into(_db.customers).insert(CustomersCompanion.insert(
          id: c['id'] as String,
          name: name,
          phone: Value((c['phone'] as String?)?.isNotEmpty == true ? c['phone'] as String : null),
          address:
              Value((c['address'] as String?)?.isNotEmpty == true ? c['address'] as String : null),
          status: Value(status),
          notes: Value(notes?.isNotEmpty == true ? notes : null),
        ));
    _existingCustomerNames.add(name);
  }

  Future<int> _importShipment(Map<String, dynamic> s) async {
    final shipmentNumber = s['shipmentNumber'] as String;
    if (_existingShipmentNumbers.contains(shipmentNumber)) {
      final existing = await (_db.select(_db.vegetableShipments)
            ..where((t) => t.shipmentNumber.equals(shipmentNumber)))
          .get();
      if (existing.isNotEmpty) return existing.first.id;
    }
    final pricingMode = s['pricingMode'] as String;
    final totalBarnikaCount = s['totalBarnikaCount'] as int;
    final totalCost = (s['totalCost'] as num).toDouble();
    final barnikaRemainingCount = s['barnikaRemainingCount'] as int;
    final barnikaSoldCount = s['barnikaSoldCount'] as int? ?? 0;
    final date = DateTime.parse(s['date'] as String);

    return _db.into(_db.vegetableShipments).insert(VegetableShipmentsCompanion.insert(
          supplierId: s['supplierId'] as String,
          shipmentNumber: shipmentNumber,
          pricingMode: pricingMode,
          totalBarnikaCount: totalBarnikaCount,
          totalCost: totalCost,
          barnikaRemainingCount: barnikaRemainingCount,
          date: Value(date),
          barnikaSoldCount: Value(barnikaSoldCount),
          costPricePerBarnika: Value(
              s['costPricePerBarnika'] != null ? (s['costPricePerBarnika'] as num).toDouble() : null),
          lumpSumCost: Value(
              s['lumpSumCost'] != null ? (s['lumpSumCost'] as num).toDouble() : null),
          commissionPercentage: Value(
              s['commissionPercentage'] != null ? (s['commissionPercentage'] as num).toDouble() : null),
          containerPrice: Value(
              s['containerPrice'] != null ? (s['containerPrice'] as num).toDouble() : null),
          notes: Value((s['notes'] as String?)?.isNotEmpty == true ? s['notes'] as String : null),
        ));
  }

  Future<void> _importSale(Map<String, dynamic> sale, Map<String, int> shipmentUuidToId) async {
    final productId = _defaultProductId;
    if (productId == null) throw Exception('Default product not found');

    final customerId = sale['customerId'] as String?;
    final customerName = sale['customerName'] as String;
    final date = DateTime.parse(sale['date'] as String);
    final quantity = sale['quantity'] as int;
    final pricePerUnit = (sale['pricePerUnit'] as num).toDouble();
    final totalAmount = (sale['totalAmount'] as num).toDouble();
    final paidAmount = (sale['paidAmount'] as num).toDouble();
    final cashAmount = (sale['cashAmount'] as num).toDouble();
    final creditAmount = (sale['creditAmount'] as num).toDouble();
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0;
    final status = sale['status'] as String? ?? 'pending';
    final paymentMethod = sale['paymentMethod'] as String? ?? 'cash';
    final notes = sale['notes'] as String? ?? '';
    final shipmentId = sale['shipmentId'] as String?;
    final shipmentNumber = sale['shipmentNumber'] as String?;

    final shipmentIntId = shipmentId != null ? shipmentUuidToId[shipmentId] : null;
    final pricingMode = sale['pricingMode'] as String?;
    final isCommission = pricingMode == 'commission';

    final invNumber = 'IMP-${date.toIso8601String().substring(0, 10).replaceAll('-', '')}-${_uuid.v4().substring(0, 8)}';

    final invoiceId = await _db.into(_db.invoices).insert(InvoicesCompanion(
          invoiceNumber: Value(invNumber),
          customerId: Value(customerId),
          customerName: Value(customerName),
          paymentMethod: Value(paymentMethod),
          totalAmount: Value(totalAmount),
          paidAmount: Value(paidAmount),
          date: Value(date),
          status: Value(status == 'paid' ? 'paid' : 'pending'),
          cashAmount: Value(cashAmount),
          creditAmount: Value(creditAmount),
          shipmentId: Value(shipmentIntId),
        ));

    final unitCost = shipmentIntId != null && !isCommission
        ? await _unitCostForShipment(shipmentIntId)
        : null;

    await _db.into(_db.invoiceItems).insert(InvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          price: (totalAmount - discount) / (quantity > 0 ? quantity : 1),
          quantity: Value(quantity),
          discount: Value(discount),
          commission: Value(0.0),
          unitCostAtTime: Value(unitCost),
          shipmentId: Value(shipmentIntId),
        ));

    if (status == 'paid' && paidAmount > 0) {
      await _db.into(_db.invoicePayments).insert(InvoicePaymentsCompanion.insert(
            invoiceId: invoiceId,
            paymentMethod: paymentMethod,
            amount: paidAmount,
            paidAt: Value(date),
            notes: Value(notes.isNotEmpty ? notes : null),
          ));
    }

    if (isCommission && shipmentIntId != null) {
      final shipment = await _db.vegetableShipmentDao.getById(shipmentIntId);
      if (shipment != null) {
        final commPct = shipment.commissionPercentage;
        if (commPct != null && commPct > 0) {
          final commissionAmount = totalAmount * commPct / 100;
          await _db.into(_db.ledgerTransactions).insert(LedgerTransactionsCompanion.insert(
                id: _uuid.v4(),
                entityType: 'Supplier',
                refId: shipment.supplierId,
                date: date,
                description: 'عمولة بيع شحنة $shipmentNumber',
                credit: Value(commissionAmount),
                origin: 'import',
              ));
        }
      }
    }
  }

  Future<double?> _unitCostForShipment(int shipmentId) async {
    final shipment = await _db.vegetableShipmentDao.getById(shipmentId);
    return shipment?.costPricePerBarnika;
  }

  Future<void> _importExpense(Map<String, dynamic> exp) async {
    await _db.into(_db.expenses).insert(ExpensesCompanion.insert(
          id: _uuid.v4(),
          description: exp['description'] as String,
          amount: (exp['amount'] as num).toDouble(),
          category: exp['category'] as String,
          date: Value(DateTime.parse(exp['date'] as String)),
          notes: Value((exp['notes'] as String?)?.isNotEmpty == true ? exp['notes'] as String : null),
        ));
  }

  Future<void> _importCollection(
      Map<String, dynamic> col, Map<String, String> customerNameToId) async {
    final customerName = col['customerName'] as String;
    final totalAmount = (col['amount'] as num).toDouble();
    final date = DateTime.parse(col['date'] as String);
    final notes = col['notes'] as String? ?? '';

    final customerId = customerNameToId[customerName];
    if (customerId == null) {
      return;
    }

    final pendingInvoices = await (_db.select(_db.invoices)
          ..where((t) => (t.customerId.equals(customerId)) & (t.status.equals('pending')))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    var remainingCollection = totalAmount;
    for (final inv in pendingInvoices) {
      if (remainingCollection <= 0) break;
      final invRemaining = inv.totalAmount - inv.paidAmount;
      if (invRemaining <= 0) continue;

      final paymentAmount = remainingCollection >= invRemaining ? invRemaining : remainingCollection;

      await _db.into(_db.invoicePayments).insert(InvoicePaymentsCompanion.insert(
            invoiceId: inv.id,
            paymentMethod: 'cash',
            amount: paymentAmount,
            paidAt: Value(date),
            notes: Value(notes.isNotEmpty ? notes : null),
          ));

      final newPaid = inv.paidAmount + paymentAmount;
      final newStatus = newPaid >= inv.totalAmount ? 'paid' : 'pending';

      await (_db.update(_db.invoices)..where((t) => t.id.equals(inv.id))).write(InvoicesCompanion(
            paidAmount: Value(newPaid),
            status: Value(newStatus),
          ));

      remainingCollection -= paymentAmount;
    }

    if (remainingCollection > 0.001) {
      await _db.into(_db.ledgerTransactions).insert(LedgerTransactionsCompanion.insert(
            id: _uuid.v4(),
            entityType: 'Customer',
            refId: customerId,
            date: date,
            description: 'تحصيل $notes',
            credit: Value(remainingCollection),
            origin: 'import',
          ));
    }
  }

  Future<void> _importEmptyBarnika(Map<String, dynamic> eb) async {
    final customerId = eb['customerId'] as String;
    final dateOut = DateTime.parse(eb['dateOut'] as String);
    final quantityOut = eb['quantityOut'] as int;
    final quantityReturned = eb['quantityReturned'] as int? ?? 0;
    final status = eb['status'] as String? ?? 'out';
    final dateReturned = eb['dateReturned'] != null ? DateTime.parse(eb['dateReturned'] as String) : null;

    await _db.into(_db.emptyBarnikaTracking).insert(EmptyBarnikaTrackingCompanion.insert(
          customerId: customerId,
          dateOut: dateOut,
          quantityOut: quantityOut,
          quantityReturned: Value(quantityReturned),
          dateReturned: Value(dateReturned),
          status: Value(status),
        ));
  }
}

class _ParsedExcelWorkbook {
  final List<OpeningBalanceCustomerRow> customers;
  final List<OpeningBalanceSupplierRow> suppliers;
  final List<Map<String, dynamic>> legacyShipments;
  final List<Map<String, dynamic>> legacySales;
  final List<Map<String, dynamic>> legacyExpenses;
  final List<Map<String, dynamic>> legacyCollections;
  final List<Map<String, dynamic>> legacyEmptyBarnika;
  final List<String> detectedSheets;

  const _ParsedExcelWorkbook({
    required this.customers,
    required this.suppliers,
    required this.legacyShipments,
    required this.legacySales,
    required this.legacyExpenses,
    required this.legacyCollections,
    required this.legacyEmptyBarnika,
    required this.detectedSheets,
  });

  bool get hasLegacyOperationalData =>
      legacyShipments.isNotEmpty ||
      legacySales.isNotEmpty ||
      legacyExpenses.isNotEmpty ||
      legacyCollections.isNotEmpty ||
      legacyEmptyBarnika.isNotEmpty;
}

