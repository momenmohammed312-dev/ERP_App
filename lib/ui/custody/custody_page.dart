import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/custody_service.dart';

class CustodyPage extends StatefulWidget {
  final AppDatabase db;

  const CustodyPage({super.key, required this.db});

  @override
  State<CustodyPage> createState() => _CustodyPageState();
}

class _CustodyPageState extends State<CustodyPage> {
  late final CustodyService _custodyService;
  List<CashCustody> _custodies = [];
  CashCustody? _selectedCustody;
  List<CustodyExpense> _selectedExpenses = [];
  bool _isLoading = false;
  String _statusFilter = 'all'; // 'all', 'open', 'settled', 'cancelled'

  final _currencyFormat = NumberFormat('#,##0.00', 'ar');
  final _dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

  @override
  void initState() {
    super.initState();
    _custodyService = CustodyService(widget.db);
    _loadCustodies();
  }

  Future<void> _loadCustodies() async {
    setState(() => _isLoading = true);
    try {
      final list = await widget.db.custodyDao.getAllCustodies();
      setState(() {
        _custodies = list;
        // تحديث العهدة المحددة إن وجدت
        if (_selectedCustody != null) {
          final updated = list.where((c) => c.id == _selectedCustody!.id).firstOrNull;
          _selectedCustody = updated;
        }
      });
      if (_selectedCustody != null) {
        await _loadExpensesForSelected();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل العهد: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExpensesForSelected() async {
    if (_selectedCustody == null) return;
    try {
      final expenses = await widget.db.custodyDao.getExpensesByCustody(_selectedCustody!.id);
      setState(() {
        _selectedExpenses = expenses;
      });
    } catch (e) {
      debugPrint('Error loading expenses: $e');
    }
  }

  List<CashCustody> get _filteredCustodies {
    if (_statusFilter == 'all') return _custodies;
    return _custodies.where((c) => c.status == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 28),
            Gap(12),
            Text(
              'إدارة العهد المالية للموظفين',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustodies,
          ),
          const Gap(8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.add_card, size: 20),
            label: const Text('صرف عهدة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _showCreateCustodyDialog(context),
          ),
          const Gap(16),
        ],
      ),
      body: _isLoading && _custodies.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── القائمة اليمنى: قائمة العهد والفلترة ──
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildFilterBar(colorScheme),
                        _buildSummaryHeader(),
                        const Divider(height: 1),
                        Expanded(child: _buildCustodyList(colorScheme)),
                      ],
                    ),
                  ),
                ),

                // ── القسم الأيسر: تفاصيل العهدة المختارة ومصروفاتها ──
                Expanded(
                  flex: 7,
                  child: _selectedCustody == null
                      ? _buildEmptyDetailsPlaceholder(colorScheme)
                      : _buildCustodyDetailsPanel(colorScheme),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'all', label: Text('الكل')),
          ButtonSegment(value: 'open', label: Text('مفتوحة')),
          ButtonSegment(value: 'settled', label: Text('مسواة')),
          ButtonSegment(value: 'cancelled', label: Text('ملغاة')),
        ],
        selected: {_statusFilter},
        onSelectionChanged: (val) {
          setState(() => _statusFilter = val.first);
        },
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final openList = _custodies.where((c) => c.status == 'open');
    final totalOpenAmount = openList.fold<double>(0.0, (sum, c) => sum + c.amount);
    final totalRemaining = openList.fold<double>(0.0, (sum, c) => sum + c.remainingAmount);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              const Text('عهدة مفتوحة', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Gap(4),
              Text(
                '${openList.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          Container(width: 1, height: 30, color: Colors.grey.withValues(alpha: 0.3)),
          Column(
            children: [
              const Text('إجمالي المصروف كعهدة', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Gap(4),
              Text(
                '${_currencyFormat.format(totalOpenAmount)} ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue),
              ),
            ],
          ),
          Container(width: 1, height: 30, color: Colors.grey.withValues(alpha: 0.3)),
          Column(
            children: [
              const Text('المتبقي بالخارج', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Gap(4),
              Text(
                '${_currencyFormat.format(totalRemaining)} ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustodyList(ColorScheme colorScheme) {
    final list = _filteredCustodies;
    if (list.isEmpty) {
      return const Center(
        child: Text('لا توجد عهد مالية مطابقة', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Gap(8),
      itemBuilder: (context, index) {
        final item = list[index];
        final isSelected = _selectedCustody?.id == item.id;

        return InkWell(
          onTap: () {
            setState(() => _selectedCustody = item);
            _loadExpensesForSelected();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.15),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.custodyNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    _buildStatusChip(item.status),
                  ],
                ),
                const Gap(6),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const Gap(6),
                    Text(
                      item.staffName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('yyyy/MM/dd').format(item.date),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const Gap(8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'المبلغ: ${_currencyFormat.format(item.amount)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      'المتبقي: ${_currencyFormat.format(item.remainingAmount)} ج.م',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: item.remainingAmount > 0 ? Colors.green.shade700 : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const Gap(6),
                // شريط تقدم نسبة الصرف
                LinearProgressIndicator(
                  value: item.amount > 0
                      ? (item.totalExpenses / item.amount).clamp(0.0, 1.0)
                      : 0.0,
                  backgroundColor: Colors.grey.shade300,
                  color: item.totalExpenses >= item.amount ? Colors.red : Colors.teal,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case 'open':
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade800;
        text = 'مفتوحة';
        break;
      case 'settled':
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue.shade800;
        text = 'تمت التسوية';
        break;
      case 'cancelled':
        bg = Colors.red.withValues(alpha: 0.15);
        fg = Colors.red.shade800;
        text = 'ملغاة';
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey.shade800;
        text = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyDetailsPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 64, color: colorScheme.outline.withValues(alpha: 0.5)),
          const Gap(16),
          const Text(
            'اختر عهدة من القائمة لعرض تفاصيلها وتسجيل المصروفات',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCustodyDetailsPanel(ColorScheme colorScheme) {
    final custody = _selectedCustody!;
    final isOpen = custody.status == 'open';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── كرت رأس العهدة الرئيسي ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          custody.custodyNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                        const Gap(12),
                        _buildStatusChip(custody.status),
                      ],
                    ),
                    if (isOpen)
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('إلغاء العهدة'),
                            onPressed: () => _confirmCancelCustody(custody),
                          ),
                          const Gap(8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade800,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: const Text('تسوية وإغلاق العهدة'),
                            onPressed: () => _confirmSettleCustody(custody),
                          ),
                        ],
                      ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem('المسؤول / الموظف:', custody.staffName),
                    ),
                    Expanded(
                      child: _buildInfoItem('تاريخ الاستلام:', _dateFormat.format(custody.date)),
                    ),
                    if (custody.description != null && custody.description!.isNotEmpty)
                      Expanded(
                        child: _buildInfoItem('الغرض / البيان:', custody.description!),
                      ),
                  ],
                ),
                if (custody.notes != null && custody.notes!.isNotEmpty) ...[
                  const Gap(8),
                  Text('ملاحظات: ${custody.notes!}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ],
            ),
          ),

          const Gap(16),

          // ── كروت المبالغ الملخصة ──
          Row(
            children: [
              Expanded(
                child: _buildAmountCard(
                  title: 'مبلغ العهدة الأصلي',
                  amount: custody.amount,
                  color: Colors.blue,
                  icon: Icons.account_balance_wallet,
                ),
              ),
              const Gap(12),
              Expanded(
                child: _buildAmountCard(
                  title: 'إجمالي المصروفات',
                  amount: custody.totalExpenses,
                  color: Colors.redAccent,
                  icon: Icons.receipt_long,
                ),
              ),
              const Gap(12),
              Expanded(
                child: _buildAmountCard(
                  title: 'المبلغ المتبقي',
                  amount: custody.remainingAmount,
                  color: Colors.green,
                  icon: Icons.savings_outlined,
                ),
              ),
            ],
          ),

          const Gap(16),

          // ── رأس جدول المصروفات وزر إضافة مصروف ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'سجل مصروفات العهدة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              if (isOpen)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة مصروف'),
                  onPressed: () => _showAddExpenseDialog(context, custody),
                ),
            ],
          ),

          const Gap(8),

          // ── قائمة المصروفات المسجلة ──
          Expanded(
            child: _selectedExpenses.isEmpty
                ? Center(
                    child: Text(
                      isOpen ? 'لم يتم تسجيل أي مصروفات على هذه العهدة حتى الآن' : 'لا توجد مصروفات مسجلة',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _selectedExpenses.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final expense = _selectedExpenses[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.withValues(alpha: 0.15),
                            child: const Icon(Icons.receipt, color: Colors.teal, size: 20),
                          ),
                          title: Text(
                            expense.description,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            _dateFormat.format(expense.date),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_currencyFormat.format(expense.amount)} ج.م',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.redAccent,
                                ),
                              ),
                              if (isOpen) ...[
                                const Gap(12),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  tooltip: 'حذف المصروف',
                                  onPressed: () => _confirmDeleteExpense(expense),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const Gap(2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  Widget _buildAmountCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 22),
          ),
          const Gap(12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Gap(2),
              Text(
                '${_currencyFormat.format(amount)} ج.م',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── الحوارات: صرف عهدة جديدة ──
  Future<void> _showCreateCustodyDialog(BuildContext context) async {
    final staffList = await widget.db.staffManagementDao.getActiveStaff();
    if (staffList.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد موظفون نشطون مسجلون! قم بإضافة موظفين أولاً من تبويب الموظفين.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final notesController = TextEditingController();
    Staff? selectedStaff = staffList.first;
    DateTime selectedDate = DateTime.now();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_card, color: Colors.teal),
                  Gap(10),
                  Text('صرف عهدة مالية جديدة'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // اختيار الموظف
                        DropdownButtonFormField<Staff>(
                          initialValue: selectedStaff,
                          decoration: const InputDecoration(
                            labelText: 'الموظف المسؤول *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          items: staffList.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text('${s.name} (${s.position})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() => selectedStaff = val);
                          },
                        ),
                        const Gap(14),

                        // مبلغ العهدة
                        TextFormField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'قيمة العهدة (ج.م) *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'مطلوب إدخال المبلغ';
                            final num = double.tryParse(val.trim());
                            if (num == null || num <= 0) return 'أدخل مبلغاً صحيحاً أكبر من صفر';
                            return null;
                          },
                        ),
                        const Gap(14),

                        // الغرض / الوصف
                        TextFormField(
                          controller: descController,
                          decoration: const InputDecoration(
                            labelText: 'الغرض من العهدة / البيان',
                            hintText: 'مثال: عهدة مصاريف صيانة ونثريات',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.description),
                          ),
                        ),
                        const Gap(14),

                        // الملاحظات
                        TextFormField(
                          controller: notesController,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات إضافية',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.note_alt_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final amount = double.parse(amountController.text.trim());

                    try {
                      await _custodyService.createCustody(
                        staffId: selectedStaff!.staffId,
                        staffName: selectedStaff!.name,
                        amount: amount,
                        date: selectedDate,
                        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                      );

                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      await _loadCustodies();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم صرف العهدة النقدية بنجاح')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('حفظ وصرف'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── إضافة مصروف على العهدة ──
  Future<void> _showAddExpenseDialog(BuildContext context, CashCustody custody) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.add_shopping_cart, color: Colors.teal),
              const Gap(10),
              Text('إضافة مصروف على عهدة: ${custody.custodyNumber}'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المتبقي المتاح في العهدة:'),
                        Text(
                          '${_currencyFormat.format(custody.remainingAmount)} ج.م',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                      ],
                    ),
                  ),
                  const Gap(14),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'بيان المصروف *',
                      hintText: 'مثال: شراء أدوات نظافة أو وقود',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'مطلوب إدخال البيان';
                      return null;
                    },
                  ),
                  const Gap(14),
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'قيمة المصروف (ج.م) *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'مطلوب إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'أدخل قيمة صحيحة';
                      if (num > custody.remainingAmount) {
                        return 'القيمة تتجاوز المتبقي من العهدة (${custody.remainingAmount})';
                      }
                      return null;
                    },
                  ),
                  const Gap(14),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amount = double.parse(amountController.text.trim());

                try {
                  await _custodyService.addExpense(
                    custodyId: custody.id,
                    description: descController.text.trim(),
                    amount: amount,
                    notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                  );

                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  await _loadCustodies();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تسجيل المصروف بنجاح')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        );
      },
    );
  }

  // ── حذف مصروف ──
  Future<void> _confirmDeleteExpense(CustodyExpense expense) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف المصروف'),
        content: Text('هل أنت متأكد من حذف مصروف "${expense.description}" بقيمة ${_currencyFormat.format(expense.amount)} ج.م؟ سيتم رد المبلغ لرصيد العهدة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _custodyService.deleteExpense(expense.id);
        await _loadCustodies();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في حذف المصروف: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ── تسوية وإغلاق العهدة ──
  Future<void> _confirmSettleCustody(CashCustody custody) async {
    final remaining = custody.remainingAmount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد تسوية العهدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيتم تسوية وإغلاق العهدة رقم: ${custody.custodyNumber} الخاصة بالمسؤول ${custody.staffName}.'),
            const Gap(10),
            Text('• إجمالي ما تم صرفه: ${_currencyFormat.format(custody.totalExpenses)} ج.م'),
            Text(
              '• المبلغ المتبقي المسترد للخزينة: ${_currencyFormat.format(remaining)} ج.م',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const Gap(10),
            const Text('ملاحظة: لن يمكن إضافة أي مصروفات جديدة على هذه العهدة بعد الإغلاق.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد التسوية والإغلاق'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _custodyService.settleCustody(custodyId: custody.id);
        await _loadCustodies();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت تسوية وإغلاق العهدة بنجاح')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ── إلغاء العهدة ──
  Future<void> _confirmCancelCustody(CashCustody custody) async {
    if (custody.totalExpenses > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن إلغاء عهدة تم تسجيل مصروفات عليها، يمكنك استخدام زر التسوية بدلاً من ذلك.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إلغاء العهدة'),
        content: Text('هل أنت متأكد من إلغاء العهدة رقم ${custody.custodyNumber} بالكامل؟ سيتم رد كامل المبلغ (${_currencyFormat.format(custody.amount)} ج.م) للخزينة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _custodyService.cancelCustody(custody.id);
        await _loadCustodies();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إلغاء العهدة واسترداد المبلغ للخزينة')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
