import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class ExportService {
  static Future<void> exportToCSV({
    required List<Map<String, dynamic>> data,
    required String reportType,
    required String fileName,
  }) async {
    if (kIsWeb) {
      throw Exception('Export not supported on web platform');
    }
    try {
      if (data.isEmpty) {
        throw Exception('لا توجد بيانات للتصدير');
      }

      final csvData = _convertToCSV(data, reportType);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName.csv');
      await file.writeAsString(csvData);

      debugPrint('تم تصدير البيانات بنجاح: ${file.path}');
    } catch (e) {
      throw Exception('فشل في تصدير CSV: $e');
    }
  }

  static Future<String?> pickSaveLocation({
    required String defaultName,
    required String extension,
  }) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان الحفظ',
        fileName: '$defaultName.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      return result;
    } catch (e) {
      debugPrint('Error picking save location: $e');
      return null;
    }
  }

  static String _convertToCSV(
    List<Map<String, dynamic>> data,
    String reportType,
  ) {
    final headers = _getHeaders(reportType);
    final csvRows = <String>[];

    // Add header row
    csvRows.add(headers.map((h) => '"$h"').join(','));

    // Add data rows
    for (final item in data) {
      final row = headers
          .map((header) {
            final value = _getCellValue(header, item, reportType);
            return '"${value.toString().replaceAll('"', '""')}"';
          })
          .join(',');
      csvRows.add(row);
    }

    return csvRows.join('\n');
  }

  static List<String> _getHeaders(String reportType) {
    switch (reportType) {
      case 'sales':
        return [
          'رقم الفاتورة',
          'العميل',
          'التاريخ',
          'الإجمالي',
          'المدفوع',
          'الحالة',
        ];
      case 'customers':
        return ['اسم العميل', 'رقم الاتصال', 'الرصيد', 'عدد الفواتير'];
      case 'suppliers':
        return ['اسم المورد', 'رقم الاتصال', 'الرصيد', 'عدد المشتريات'];
      case 'products':
        return ['اسم المنتج', 'التصنيف', 'الكمية', 'السعر', 'المباع'];
      case 'financial':
        return ['التاريخ', 'النوع', 'الوصف', 'المبلغ'];
      default:
        return ['البيان'];
    }
  }

  static dynamic _getCellValue(
    String header,
    Map<String, dynamic> item,
    String reportType,
  ) {
    switch (header) {
      case 'رقم الفاتورة':
        return item['invoiceNumber'] ?? '-';
      case 'العميل':
      case 'اسم العميل':
      case 'اسم المورد':
      case 'اسم المنتج':
        return item['name'] ?? item['customerName'] ?? '-';
      case 'التاريخ':
        return item['date'] ?? '-';
      case 'الإجمالي':
        return (item['totalAmount'] as double?)?.toStringAsFixed(2) ?? '0.00';
      case 'المدفوع':
        return (item['paidAmount'] as double?)?.toStringAsFixed(2) ?? '0.00';
      case 'الحالة':
        return item['status'] ?? '-';
      case 'رقم الاتصال':
        return item['contact'] ?? '-';
      case 'الرصيد':
        return (item['balance'] as double?)?.toStringAsFixed(2) ?? '0.00';
      case 'عدد الفواتير':
        return item['totalInvoices'] ?? 0;
      case 'عدد المشتريات':
        return item['totalPurchases'] ?? 0;
      case 'التصنيف':
        return item['category'] ?? '-';
      case 'الكمية':
        return item['quantity'] ?? 0;
      case 'السعر':
        return (item['price'] as double?)?.toStringAsFixed(2) ?? '0.00';
      case 'المباع':
        return item['totalSold'] ?? 0;
      case 'النوع':
        return item['type'] ?? '-';
      case 'الوصف':
        return item['description'] ?? '-';
      case 'المبلغ':
        return (item['amount'] as double?)?.toStringAsFixed(2) ?? '0.00';
      default:
        return item[header] ?? '-';
    }
  }
}
