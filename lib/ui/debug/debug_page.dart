import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';

class DebugPage extends ConsumerWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('صفحة التشخيص (Debug Mode)'),
          backgroundColor: Colors.amber.shade800,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              context,
              'قاعدة البيانات',
              Icons.storage,
              Colors.blue,
              [
                _buildButton(
                  context,
                  'عرض الجداول',
                  Icons.table_chart,
                  () => _showTables(context, db),
                ),
                _buildButton(
                  context,
                  'إحصائيات السجلات',
                  Icons.numbers,
                  () => _showRecordCounts(context, db),
                ),
                _buildButton(
                  context,
                  'اختبار الاتصال',
                  Icons.compare_arrows,
                  () => _testConnection(context, db),
                ),
              ],
            ),
            _buildSection(
              context,
              'البيانات التجريبية',
              Icons.science,
              Colors.green,
              [
                _buildButton(
                  context,
                  'إضافة عملاء تجريبيين',
                  Icons.person_add,
                  () => _addDummyCustomers(context, db),
                ),
                _buildButton(
                  context,
                  'إضافة منتجات تجريبية',
                  Icons.inventory_2,
                  () => _addDummyProducts(context, db),
                ),
              ],
            ),
            _buildSection(context, 'منطقة الخطر', Icons.warning, Colors.red, [
              _buildButton(
                context,
                'حذف كل البيانات',
                Icons.delete_forever,
                () => _clearAllData(context, db),
                isDanger: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<Widget> buttons,
  ) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(spacing: 12, runSpacing: 12, children: buttons),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool isDanger = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isDanger ? Colors.red : null,
        foregroundColor: isDanger ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Future<void> _showTables(BuildContext context, AppDatabase db) async {
    try {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('الجداول المتاحة'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: tables
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '• ${t.read<String>('name')}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  Future<void> _showRecordCounts(BuildContext context, AppDatabase db) async {
    try {
      final customers = await db.customerDao.getAllCustomers();
      // Using generic counts for others if DAOs don't support simple get all or if we want raw counts
      final suppliers = await db
          .customSelect('SELECT COUNT(*) as count FROM suppliers')
          .getSingle();
      final products = await db
          .customSelect('SELECT COUNT(*) as count FROM products')
          .getSingle();
      final invoices = await db
          .customSelect('SELECT COUNT(*) as count FROM invoices')
          .getSingle();

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('إحصائيات السجلات'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCountRow('العملاء', customers.length),
                _buildCountRow('الموردين', suppliers.read<int>('count')),
                _buildCountRow('المنتجات', products.read<int>('count')),
                _buildCountRow('الفواتير', invoices.read<int>('count')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  Widget _buildCountRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(count.toString(), style: const TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }

  Future<void> _testConnection(BuildContext context, AppDatabase db) async {
    try {
      final result = await db.customSelect('SELECT 1 as test').getSingle();
      if (context.mounted && result.read<int>('test') == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ الاتصال بقاعدة البيانات سليم'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  Future<void> _addDummyCustomers(BuildContext context, AppDatabase db) async {
    try {
      for (int i = 1; i <= 5; i++) {
        await db.customerDao.insertCustomer(
          CustomersCompanion(
            name: drift.Value('عميل تجريبي $i'),
            phone: drift.Value('0100000000$i'),
            address: drift.Value('عنوان تجريبي $i'),
            // email: drift.Value('customer$i@example.com'), // Removed: Pending build_runner update
            status: const drift.Value('Active'),
            createdAt: drift.Value(DateTime.now()),
            id: drift.Value('cust_demo_$i'),
          ),
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم إضافة 5 عملاء تجريبيين'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  Future<void> _addDummyProducts(BuildContext context, AppDatabase db) async {
    try {
      for (int i = 1; i <= 5; i++) {
        await db.productDao.insertProduct(
          ProductsCompanion(
            name: drift.Value('منتج تجريبي $i'),
            price: drift.Value(100.0 * i),
            quantity: drift.Value(50),
            unit: const drift.Value('piece'),
            // supplierId: const drift.Value('N/A'), // Removed: Not in current schema/generated code
            status: const drift.Value('Active'),
          ),
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم إضافة 5 منتجات تجريبية'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  Future<void> _clearAllData(BuildContext context, AppDatabase db) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف النهائي'),
        content: const Text(
          'هل أنت متأكد من حذف **كل البيانات**؟\nهذا الإجراء لا يمكن التراجع عنه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'حذف الكل',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await db.customStatement('DELETE FROM invoice_items');
        await db.customStatement('DELETE FROM ledger_transactions');
        await db.customStatement('DELETE FROM invoices');
        await db.customStatement('DELETE FROM customers');
        await db.customStatement('DELETE FROM suppliers');
        await db.customStatement('DELETE FROM products');
        await db.customStatement('DELETE FROM expenses');

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ تم حذف جميع البيانات بنجاح'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          _showError(context, e.toString());
        }
      }
    }
  }

  void _showError(BuildContext context, String error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'نسخ',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }
}
