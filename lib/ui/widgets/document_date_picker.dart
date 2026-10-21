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
  bool allowFutureDates = false,
}) async {
  final now = DateTime.now();
  DateTime effectiveLastDate;
  if (lastDate != null) {
    effectiveLastDate = lastDate;
  } else if (!allowFutureDates) {
    effectiveLastDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  } else {
    effectiveLastDate = now.add(const Duration(days: 365));
  }

  // تفادي استثناء AssertionError في showDatePicker إذا كان initialDate يتجاوز lastDate
  if (initialDate.isAfter(effectiveLastDate)) {
    effectiveLastDate = initialDate;
  }

  final effectiveFirstDate = firstDate ?? DateTime(2020);
  final effectiveInitialDate = initialDate.isBefore(effectiveFirstDate)
      ? effectiveFirstDate
      : initialDate;

  final picked = await showDatePicker(
    context: context,
    initialDate: effectiveInitialDate,
    firstDate: effectiveFirstDate,
    lastDate: effectiveLastDate,
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
