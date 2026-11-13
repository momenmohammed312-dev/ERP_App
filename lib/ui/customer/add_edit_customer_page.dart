import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:uuid/uuid.dart';

class AddEditCustomerPage extends ConsumerStatefulWidget {
  final Customer? customer;
  final String? initialName;

  const AddEditCustomerPage({super.key, this.customer, this.initialName});

  @override
  ConsumerState<AddEditCustomerPage> createState() =>
      _AddEditCustomerPageState();
}

class _AddEditCustomerPageState extends ConsumerState<AddEditCustomerPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _emailController;
  late TextEditingController _gstinController;
  late TextEditingController _notesController;
  late TextEditingController _openingBalanceController;
  late TextEditingController _totalDebtController;
  late TextEditingController _totalPaidController;

  bool _isActive = true;
  String _status = 'Active';
  bool _isLoading = false;
  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? widget.initialName ?? '');
    _phoneController = TextEditingController(
      text: widget.customer?.phone ?? '',
    );
    _addressController = TextEditingController(
      text: widget.customer?.address ?? '',
    );
    _emailController = TextEditingController(
      text: widget.customer?.email ?? '',
    );
    _gstinController = TextEditingController(
      text: widget.customer?.gstinNumber ?? '',
    );
    _notesController = TextEditingController(
      text: widget.customer?.notes ?? '',
    );
    _openingBalanceController = TextEditingController(
      text: widget.customer?.openingBalance.toString() ?? '0.0',
    );
    _totalDebtController = TextEditingController(
      text: widget.customer?.totalDebt.toString() ?? '0.0',
    );
    _totalPaidController = TextEditingController(
      text: widget.customer?.totalPaid.toString() ?? '0.0',
    );
    _isActive = widget.customer?.isActive ?? true;
    _status = widget.customer?.status ?? 'Active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _gstinController.dispose();
    _notesController.dispose();
    _openingBalanceController.dispose();
    _totalDebtController.dispose();
    _totalPaidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.colorScheme.surface;
    final borderColor = theme.colorScheme.outline.withValues(alpha: 0.15);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'تعديل عميل' : 'إضافة عميل جديد'),
          centerTitle: true,
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                tooltip: 'حذف العميل',
                onPressed: _deleteCustomer,
              ),
            IconButton(
              icon: const Icon(Icons.check, color: Color(0xFF238636)),
              tooltip: 'حفظ',
              onPressed: _isLoading ? null : _saveCustomer,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Basic Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_pin_rounded, color: theme.colorScheme.primary, size: 20),
                          const Gap(8),
                          const Expanded(
                            child: Text(
                              'البيانات الأساسية',
                              style: TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      // اسم العميل
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'اسم العميل *',
                          hintText: 'أدخل اسم العميل',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'الاسم مطلوب';
                          }
                          if (value.trim().length < 2) {
                            return 'الاسم قصير جداً';
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const Gap(12),
                      // رقم الهاتف
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف',
                          hintText: '01xxxxxxxxx',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            if (value.length < 10) {
                              return 'رقم الهاتف يجب أن يكون 10 أرقام على الأقل';
                            }
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const Gap(12),
                      // العنوان
                      TextFormField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          labelText: 'العنوان',
                          hintText: 'أدخل العنوان أو المنطقة',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                        ),
                        maxLines: 2,
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                  ),
                ),

                const Gap(14),

                // 2. Financial Info Card
                if (!_isEditing) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFC9A84C), size: 20),
                            Gap(8),
                            Expanded(
                              child: Text(
                                'الحساب الافتتاحي',
                                style: TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        TextFormField(
                          controller: _openingBalanceController,
                          decoration: InputDecoration(
                            labelText: 'الرصيد الافتتاحي (لنا / عليه)',
                            hintText: '0.0',
                            prefixIcon: const Icon(Icons.monetization_on_outlined),
                            suffixText: 'ج.م',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            filled: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}'),
                            ),
                          ],
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                    ),
                  ),
                  const Gap(14),
                ],

                // 3. Extra Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.7), size: 20),
                          const Gap(8),
                          const Expanded(
                            child: Text(
                              'بيانات إضافية وملاحظات',
                              style: TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      // الرقم الضريبي
                      TextFormField(
                        controller: _gstinController,
                        decoration: InputDecoration(
                          labelText: 'الرقم الضريبي (اختياري)',
                          hintText: 'أدخل الرقم الضريبي إن وجد',
                          prefixIcon: const Icon(Icons.receipt_long_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const Gap(12),
                      // البريد الإلكتروني
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'البريد الإلكتروني (اختياري)',
                          hintText: 'example@email.com',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            if (!RegExp(
                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                            ).hasMatch(value)) {
                              return 'البريد الإلكتروني غير صحيح';
                            }
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const Gap(12),
                      // الملاحظات
                      TextFormField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات',
                          hintText: 'أدخل ملاحظات خاصة بالعميل',
                          prefixIcon: const Icon(Icons.notes_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                        ),
                        maxLines: 2,
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                  ),
                ),

                const Gap(14),

                // 4. Status Switch Card
                Material(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: SwitchListTile(
                    title: const Text(
                      'حالة العميل النشطة',
                      style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      _isActive ? 'العميل نشط ويمكن إجراء فواتير له' : 'العميل غير نشط / موقوف مؤقتاً',
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    value: _isActive,
                    onChanged: (value) {
                      setState(() {
                        _isActive = value;
                        _status = value ? 'Active' : 'Inactive';
                      });
                    },
                    secondary: Icon(
                      _isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: _isActive ? const Color(0xFF238636) : const Color(0xFFF85149),
                    ),
                  ),
                  ),
                ),

                const Gap(24),

                // Save button
                FilledButton.icon(
                  onPressed: _isLoading ? null : _saveCustomer,
                  icon: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _isEditing ? 'تحديث بيانات العميل' : 'حفظ العميل الجديد',
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const Gap(16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف العميل "${widget.customer?.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final database = ref.read(appDatabaseProvider);
      await database.customerDao.deleteCustomer(widget.customer!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حذف العميل بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في حذف العميل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final database = ref.read(appDatabaseProvider);

      if (_isEditing) {
        // تحديث
        final updated = CustomersCompanion(
          id: Value(widget.customer!.id),
          name: Value(_nameController.text.trim()),
          phone: Value(_phoneController.text.trim().isEmpty ? null : _phoneController.text.trim()),
          address: Value(_addressController.text.trim().isEmpty ? null : _addressController.text.trim()),
          email: Value(_emailController.text.trim().isEmpty ? null : _emailController.text.trim()),
          gstinNumber: Value(_gstinController.text.trim().isEmpty ? null : _gstinController.text.trim()),
          notes: Value(_notesController.text.trim().isEmpty ? null : _notesController.text.trim()),
          openingBalance: Value(
            double.tryParse(_openingBalanceController.text) ?? 0.0,
          ),
          totalDebt: Value(
            double.tryParse(_totalDebtController.text) ?? 0.0,
          ),
          totalPaid: Value(
            double.tryParse(_totalPaidController.text) ?? 0.0,
          ),
          isActive: Value(_isActive),
          status: Value(_status),
          updatedAt: Value(DateTime.now()),
        );

        await database.customerDao.updateCustomer(updated);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم تحديث العميل بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // إضافة جديد
        final uuid = const Uuid().v4();
        final openingBalance =
            double.tryParse(_openingBalanceController.text) ?? 0.0;

        final newCustomer = CustomersCompanion(
          id: Value(uuid),
          name: Value(_nameController.text.trim()),
          phone: Value(_phoneController.text.trim().isEmpty ? null : _phoneController.text.trim()),
          address: Value(_addressController.text.trim().isEmpty ? null : _addressController.text.trim()),
          email: Value(_emailController.text.trim().isEmpty ? null : _emailController.text.trim()),
          gstinNumber: Value(_gstinController.text.trim().isEmpty ? null : _gstinController.text.trim()),
          notes: Value(_notesController.text.trim().isEmpty ? null : _notesController.text.trim()),
          openingBalance: Value(openingBalance),
          totalDebt: Value(
            double.tryParse(_totalDebtController.text) ?? 0.0,
          ),
          totalPaid: Value(
            double.tryParse(_totalPaidController.text) ?? 0.0,
          ),
          isActive: Value(_isActive),
          status: Value(_status),
          createdAt: Value(DateTime.now()),
        );

        await database.customerDao.insertCustomer(newCustomer);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم إضافة العميل بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, uuid);
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'حدث خطأ غير متوقع';
        if (e.toString().contains('UNIQUE constraint failed')) {
          errorMessage = 'اسم العميل موجود بالفعل';
        } else if (e.toString().contains('العميل موجود بالفعل')) {
          errorMessage = 'العميل موجود بالفعل';
        } else {
          errorMessage = '❌ خطأ: ${e.toString()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
