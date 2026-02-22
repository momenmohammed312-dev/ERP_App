// ignore_for_file: file_names

import 'dart:developer';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';

Future<void> exportProductsToExcel(AppDatabase db, BuildContext context) async {
  try {
    final products = await db.productDao.getAllProducts();
    final exportService = ExportService();

    // Debug: Check if the products list has data
    log('Products fetched: ${products.length}');
    log(
      'Product details: ${products.map((p) => "${p.id}: ${p.name}").join(", ")}',
    );

    if (products.isEmpty) {
      // ignore: use_build_context_synchronously
      showSnack(context, 'لا توجد منتجات للتصدير.');
      return;
    }

    // Ask user to pick a directory
    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد التصدير',
    );
    if (outputDir == null) {
      // ignore: use_build_context_synchronously
      showSnack(context, 'تم إلغاء التصدير.');
      return;
    }

    // Ask user for a filename
    // ignore: use_build_context_synchronously
    final fileName = await askForFileName(context);
    if (fileName == null || fileName.trim().isEmpty) {
      // ignore: use_build_context_synchronously
      showSnack(context, 'اسم ملف غير صالح.');
      return;
    }

    final fullPath = '$outputDir/${fileName.trim()}.xlsx';

    // Prepare data for export using ExportService
    final data = products.map((product) {
      return {
        'اسم المنتج': product.name.isNotEmpty ? product.name : 'منتج غير محدد',
        'الكمية': product.quantity.isNaN ? 0 : product.quantity,
        'السعر': product.price.isNaN ? 0.0 : product.price,
        'الوحدة': product.unit?.isNotEmpty == true ? product.unit : 'قطعة',
        'الحالة': product.status?.isNotEmpty == true ? product.status : 'نشط',
      };
    }).toList();

    await exportService.exportToExcel(
      title: 'قائمة المنتجات',
      data: data,
      headers: ['اسم المنتج', 'الكمية', 'السعر', 'الوحدة', 'الحالة'],
      columns: ['اسم المنتج', 'الكمية', 'السعر', 'الوحدة', 'الحالة'],
      fileName: fileName,
    );

    log('Products exported to: $fullPath');
    // ignore: use_build_context_synchronously
    showSnack(context, 'تم تصدير المنتجات بنجاح');
  } catch (e, stackTrace) {
    log('Export Error: $e');
    log('Stack trace: $stackTrace');
    // ignore: use_build_context_synchronously
    showSnack(context, 'فشل التصدير: $e');
  }
}

Future<String?> askForFileName(BuildContext context) async {
  final controller = TextEditingController(text: 'قائمة_المنتجات_');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('أدخل اسم الملف'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'اسم الملف (بدون امتداد)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
