import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/ui/customer/add_edit_customer_page.dart';
import 'package:pos_offline_desktop/ui/customer/customer_statement_screen.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

class CustomerPage extends ConsumerStatefulWidget {
  const CustomerPage({super.key});

  @override
  ConsumerState<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends ConsumerState<CustomerPage> {
  String _searchQuery = '';
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final balances = await db.ledgerDao.getAllCustomerBalances();
      setState(() {
        _customers = balances;
        _isLoading = false;
      });
    } catch (e, st) {
      AppLogger.e('Error loading customers', e, st);
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);
    final borderColor = isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          foregroundColor: textColor,
          elevation: 0,
          title: const Text('إدارة العملاء'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadCustomers,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'بحث باسم العميل أو رقم الهاتف...',
                        hintStyle: TextStyle(color: subTextColor),
                        prefixIcon: Icon(Icons.search, color: goldColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        filled: true,
                        fillColor: cardBg,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                    ),
                  ),
                  const Gap(16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AddEditCustomerPage()),
                      );
                      if (result == true) _loadCustomers();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة عميل'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldColor,
                      foregroundColor: const Color(0xFF0D1117),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            _buildStatsHeader(goldColor, cardBg, textColor, subTextColor),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: goldColor))
                  : _buildCustomerList(textColor, subTextColor, goldColor, cardBg, borderColor, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsHeader(Color goldColor, Color cardBg, Color textColor, Color subTextColor) {
    double totalDebt = 0.0;
    int hasDebtCount = 0;

    for (var c in _customers) {
      final b = (c['balance'] as num?)?.toDouble() ?? 0.0;
      if (b > 0) {
        totalDebt += b;
        hasDebtCount++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildStatCard('إجمالي المديونيات', '${totalDebt.toStringAsFixed(2)} ج.م', goldColor, cardBg, textColor),
          const Gap(12),
          _buildStatCard('عملاء مديونين', hasDebtCount.toString(), Colors.redAccent, cardBg, textColor),
          const Gap(12),
          _buildStatCard('إجمالي العملاء', _customers.length.toString(), subTextColor, cardBg, textColor),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, Color cardBg, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            const Gap(4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerList(Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    final filtered = _customers.where((c) {
      final name = (c['name'] as String? ?? '').toLowerCase();
      final phone = (c['phone'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(child: Text('لا يوجد عملاء مطابقين للبحث', style: TextStyle(color: subTextColor)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final customerMap = filtered[index];
        final balance = (customerMap['balance'] as num?)?.toDouble() ?? 0.0;

        return Card(
          color: cardBg,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor.withValues(alpha: 0.3)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: goldColor.withValues(alpha: 0.15),
              child: Text(
                customerMap['name'][0],
                style: TextStyle(color: goldColor, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(customerMap['name'], style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
            subtitle: Text(customerMap['phone'] ?? 'بدون هاتف', style: TextStyle(color: subTextColor)),
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
                        color: balance > 0 ? Colors.redAccent : (balance < 0 ? Colors.green : subTextColor),
                      ),
                    ),
                    Text(
                      balance > 0 ? 'عليه (مدين)' : (balance < 0 ? 'له (دائن)' : 'متعادل'),
                      style: TextStyle(
                        fontSize: 10,
                        color: balance > 0 ? Colors.redAccent : (balance < 0 ? Colors.green : subTextColor),
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                Icon(Icons.arrow_forward_ios, size: 16, color: subTextColor),
              ],
            ),
            onTap: () => _showCustomerActions(customerMap, textColor, subTextColor, goldColor, cardBg, borderColor, isDark),
          ),
        );
      },
    );
  }

  void _showCustomerActions(Map<String, dynamic> customerMap, Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                customerMap['name'],
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
              ),
              const Gap(24),
              ListTile(
                leading: Icon(Icons.edit, color: goldColor),
                title: Text('تعديل بيانات العميل', style: TextStyle(color: textColor)),
                onTap: () async {
                  Navigator.pop(context);
                  final db = ref.read(appDatabaseProvider);
                  final customer = await db.customerDao.getCustomerById(customerMap['id']);
                  if (customer != null) {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AddEditCustomerPage(customer: customer)),
                    );
                    if (result == true) _loadCustomers();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.description, color: Colors.green),
                title: Text('كشف حساب تفصيلي', style: TextStyle(color: textColor)),
                onTap: () async {
                  Navigator.pop(context);
                  final db = ref.read(appDatabaseProvider);
                  final customer = await db.customerDao.getCustomerById(customerMap['id']);
                  if (customer != null && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CustomerStatementScreen(customer: customer)),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.payment, color: Colors.orange),
                title: Text('تسجيل دفعة (سداد)', style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: Text('حذف العميل', style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(customerMap, textColor, subTextColor, goldColor, cardBg);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> customerMap, Color textColor, Color subTextColor, Color goldColor, Color cardBg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: const Text('تأكيد الحذف'),
        content: Text(
          'هل أنت متأكد من حذف العميل "${customerMap['name']}"؟ سيتم إخفاء العميل من القائمة ولكن ستبقى سجلاته المالية موجودة.',
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: TextStyle(color: goldColor)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final db = ref.read(appDatabaseProvider);
              await db.customerDao.deleteCustomer(customerMap['id']);
              _loadCustomers();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
