import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

Future<bool> showAdminPasswordGate(BuildContext context, AppDatabase db) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(children: [
          Icon(Icons.admin_panel_settings, color: Colors.orange),
          SizedBox(width: 8),
          Text('صلاحية المدير مطلوبة'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('هذه العملية تتطلب إذن المدير. أدخل كلمة مرور المدير:'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'كلمة مرور المدير',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final ok = await db.userDao.authenticate('admin', controller.text);
              Navigator.pop(ctx, ok != null);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
