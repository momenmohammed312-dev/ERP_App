import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/services/document_date_service.dart';

/// يعرض تنبيه تأكيد إذا كان التاريخ المختار يقع في يوم تم إغلاقه سابقاً دون منع المستخدم
Future<bool> showClosedDayWarningDialog(
  BuildContext context,
  DateTime selectedDate,
) async {
  final dateFormatted = DateFormat('yyyy/MM/dd').format(selectedDate);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
          Gap(10),
          Text(
            'تنبيه: يوم مغلق',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: Text(
        'التاريخ المختار ($dateFormatted) يقع في يوم تم إغلاقه مسبقاً.\n\nهل تود المتابعة وتحديث السجلات بهذا التاريخ؟',
        style: const TextStyle(fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء والتراجع'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
          ),
          child: const Text('تأكيد ومتابعة'),
        ),
      ],
    ),
  );
  return result == true;
}

/// دالة موحدة لاختيار تاريخ مستند مع التحقق التلقائي من اليوم المغلق والحفاظ على الوقت
Future<DateTime?> pickDocumentDate({
  required BuildContext context,
  required AppDatabase db,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate ?? DateTime(2020),
    lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
  );

  if (picked == null) return null;

  final docService = DocumentDateService(db);
  final isClosed = await docService.isDateInClosedDay(picked);

  if (isClosed && context.mounted) {
    final proceed = await showClosedDayWarningDialog(context, picked);
    if (!proceed) return null;
  }

  // الحفاظ على وقت اللحظة الحالية أو وقت التاريخ الحالي
  return DocumentDateService.mergeWithCurrentTime(picked, initialDate);
}
