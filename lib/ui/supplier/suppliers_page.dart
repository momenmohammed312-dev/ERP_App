import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/ui/supplier/widgets/supplier_form_dialog.dart';
import 'package:pos_offline_desktop/ui/supplier/supplier_statement_screen.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  String _searchQuery = '';
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final balances = await db.ledgerDao.getAllSupplierBalances();
      setState(() {
        _suppliers = balances;
        _isLoading = false;
      });
    } catch (e, st) {
      AppLogger.e('Error loading suppliers', e, st);
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الموردين'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadSuppliers,
            ),
          ],
        ),
        body: Column(
          children: [
            // Search and Add Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث باسم المورد أو رقم الهاتف...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                    ),
                  ),
                  const Gap(16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await showDialog<bool>(
                        context: context,
                        builder: (context) => SupplierFormDialog(database: ref.read(appDatabaseProvider)),
                      );
                      if (result == true) _loadSuppliers();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة مورد'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Stats Row
            _buildStatsHeader(),

            // List
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _buildSupplierList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsHeader() {
    double totalDues = 0.0;
    int hasBalanceCount = 0;

    for (var s in _suppliers) {
      final b = (s['balance'] as num?)?.toDouble() ?? 0.0;
      if (b > 0) {
        totalDues += b;
        hasBalanceCount++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildStatCard('إجمالي مستحقات الموردين', '${totalDues.toStringAsFixed(2)} ج.م', Colors.red),
          const Gap(12),
          _buildStatCard('موردين لهم أرصدة', hasBalanceCount.toString(), Colors.purple),
          const Gap(12),
          _buildStatCard('إجمالي الموردين', _suppliers.length.toString(), Colors.grey),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            const Gap(4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierList() {
    final filtered = _suppliers.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final phone = (s['phone'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('لا يوجد موردين مطابقين للبحث'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final supplierMap = filtered[index];
        final balance = (supplierMap['balance'] as num?)?.toDouble() ?? 0.0;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.green.withValues(alpha: 0.1),
              child: Text(supplierMap['name'][0], style: const TextStyle(color: Colors.green)),
            ),
            title: Text(supplierMap['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(supplierMap['phone'] ?? 'بدون هاتف'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${balance.abs().toStringAsFixed(2)} ج.م',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: balance > 0 ? Colors.red : (balance < 0 ? Colors.green : Colors.grey),
                      ),
                    ),
                    Text(
                      balance > 0 ? 'له (دائن)' : (balance < 0 ? 'عليه (مدين)' : 'متعادل'),
                      style: TextStyle(
                        fontSize: 10,
                        color: balance > 0 ? Colors.red : (balance < 0 ? Colors.green : Colors.grey),
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
            onTap: () => _showSupplierActions(supplierMap),
          ),
        );
      },
    );
  }

  void _showSupplierActions(Map<String, dynamic> supplierMap) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(supplierMap['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Gap(24),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('تعديل بيانات المورد'),
                onTap: () async {
                  Navigator.pop(context);
                  final db = ref.read(appDatabaseProvider);
                  final supplier = await db.supplierDao.getSupplierById(supplierMap['id']);
                  if (supplier != null) {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (context) => SupplierFormDialog(database: db, supplier: supplier),
                    );
                    if (result == true) _loadSuppliers();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.description, color: Colors.green),
                title: const Text('كشف حساب المورد'),
                onTap: () async {
                  Navigator.pop(context);
                  final db = ref.read(appDatabaseProvider);
                  final supplier = await db.supplierDao.getSupplierById(supplierMap['id']);
                  if (supplier != null && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SupplierStatementScreen(supplier: supplier)),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.payment, color: Colors.orange),
                title: const Text('تسجيل دفعة للمورد'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to Supplier Payment Screen
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف المورد'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(supplierMap);
                },
              ),
              const Gap(20),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> supplierMap) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المورد "${supplierMap['name']}"؟ سيتم إخفاء المورد من القائمة ولكن ستبقى سجلاته المالية موجودة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final db = ref.read(appDatabaseProvider);
              await db.supplierDao.deleteSupplier(supplierMap['id']);
              _loadSuppliers();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
