import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:uuid/uuid.dart';

class AddEditSupplierPage extends ConsumerStatefulWidget {
  final Supplier? supplier;

  const AddEditSupplierPage({super.key, this.supplier});

  @override
  ConsumerState<AddEditSupplierPage> createState() => _AddEditSupplierPageState();
}

class _AddEditSupplierPageState extends ConsumerState<AddEditSupplierPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _emailController;
  late TextEditingController _taxNumberController;
  late TextEditingController _notesController;
  late TextEditingController _openingBalanceController;
  late TextEditingController _totalPurchasesController;
  late TextEditingController _totalPaidController;

  bool _isActive = true;
  String _status = 'Active';
  bool _isLoading = false;
  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.supplier?.name ?? '');
    _phoneController = TextEditingController(
      text: widget.supplier?.phone ?? '',
    );
    _addressController = TextEditingController(
      text: widget.supplier?.address ?? '',
    );
    _emailController = TextEditingController();
    _taxNumberController = TextEditingController();
    _notesController = TextEditingController();
    _openingBalanceController = TextEditingController(
      text: widget.supplier?.openingBalance.toString() ?? '0.0',
    );
    _totalPurchasesController = TextEditingController(text: '0.0');
    _totalPaidController = TextEditingController(text: '0.0');
    _status = widget.supplier?.status ?? 'Active';
    _isActive = _status == 'Active';

    if (_isEditing) {
      _loadSupplierFinancials();
    }
  }

  Future<void> _loadSupplierFinancials() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final supplierId = widget.supplier!.id;
      final txs = await (db.select(db.ledgerTransactions)
            ..where((t) => t.entityType.equals('Supplier') & t.refId.equals(supplierId)))
          .get();

      double purchases = 0.0;
      double paid = 0.0;

      for (final tx in txs) {
        if (tx.credit > 0) purchases += tx.credit;
        if (tx.debit > 0) paid += tx.debit;
      }

      if (mounted) {
        setState(() {
          _totalPurchasesController.text = purchases.toStringAsFixed(2);
          _totalPaidController.text = paid.toStringAsFixed(2);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _taxNumberController.dispose();
    _notesController.dispose();
    _openingBalanceController.dispose();
    _totalPurchasesController.dispose();
    _totalPaidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'تعديل مورد' : 'إضافة مورد جديد'),
          centerTitle: true,
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                tooltip: 'حذف المورد',
                onPressed: _deleteSupplier,
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // اسم المورد
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'اسم المورد *',
                    hintText: 'أدخل اسم المورد أو الشركة',
                    prefixIcon: const Icon(Icons.business),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
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

                const Gap(16),

                // رقم الهاتف
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    hintText: '01xxxxxxxxx',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (value.length < 8) {
                        return 'رقم الهاتف يجب أن يكون 8 أرقام على الأقل';
                      }
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),

                const Gap(16),

                // البريد الإلكتروني
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    hintText: 'supplier@email.com',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
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

                const Gap(16),

                // الرقم الضريبي / السجل التجاري
                TextFormField(
                  controller: _taxNumberController,
                  decoration: InputDecoration(
                    labelText: 'الرقم الضريبي / السجل التجاري',
                    hintText: 'أدخل الرقم الضريبي للمورد',
                    prefixIcon: const Icon(Icons.receipt_long),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  textInputAction: TextInputAction.next,
                ),

                const Gap(16),

                // العنوان
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'العنوان',
                    hintText: 'أدخل عنوان المورد أو المخزن',
                    prefixIcon: const Icon(Icons.location_on),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                ),

                const Gap(16),

                // الرصيد الافتتاحي (فقط عند الإضافة)
                if (!_isEditing) ...[
                  TextFormField(
                    controller: _openingBalanceController,
                    decoration: InputDecoration(
                      labelText: 'الرصيد الافتتاحي',
                      hintText: '0.0',
                      prefixIcon: const Icon(Icons.account_balance_wallet),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
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
                  const Gap(16),
                ],

                // الملاحظات
                TextFormField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات',
                    hintText: 'أدخل ملاحظات إضافية عن المورد',
                    prefixIcon: const Icon(Icons.notes),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                ),

                const Gap(16),

                // إجمالي المشتريات / الدين
                TextFormField(
                  controller: _totalPurchasesController,
                  decoration: InputDecoration(
                    labelText: 'إجمالي المشتريات / الدين',
                    hintText: '0.0',
                    prefixIcon: const Icon(Icons.shopping_bag),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  readOnly: _isEditing,
                  textInputAction: TextInputAction.next,
                ),

                const Gap(16),

                // إجمالي المدفوع
                TextFormField(
                  controller: _totalPaidController,
                  decoration: InputDecoration(
                    labelText: 'إجمالي المدفوع',
                    hintText: '0.0',
                    prefixIcon: const Icon(Icons.payments),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  readOnly: _isEditing,
                  textInputAction: TextInputAction.next,
                ),

                const Gap(16),

                // الحالة
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: InputDecoration(
                    labelText: 'الحالة',
                    prefixIcon: const Icon(Icons.flag),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Active', child: Text('نشط')),
                    DropdownMenuItem(value: 'Inactive', child: Text('غير نشط')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _status = value;
                        _isActive = value == 'Active';
                      });
                    }
                  },
                ),

                const Gap(16),

                // نشط Switch
                SwitchListTile(
                  title: const Text('نشط'),
                  subtitle: Text(_isActive ? 'المورد نشط' : 'المورد غير نشط'),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                      _status = value ? 'Active' : 'Inactive';
                    });
                  },
                  secondary: Icon(
                    _isActive ? Icons.check_circle : Icons.cancel,
                    color: _isActive ? Colors.green : Colors.red,
                  ),
                ),

                const Gap(32),

                // زر الحفظ
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveSupplier,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          _isEditing ? 'تحديث المورد' : 'حفظ المورد',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSupplier() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المورد "${widget.supplier?.name}"؟'),
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
      await database.supplierDao.deleteSupplier(widget.supplier!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حذف المورد بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في حذف المورد: $e'),
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

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final database = ref.read(appDatabaseProvider);

      if (_isEditing) {
        // تحديث مورد حالي
        final updated = SuppliersCompanion(
          id: Value(widget.supplier!.id),
          name: Value(_nameController.text.trim()),
          phone: Value(
            _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          ),
          address: Value(
            _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          ),
          openingBalance: Value(
            double.tryParse(_openingBalanceController.text) ?? widget.supplier!.openingBalance,
          ),
          status: Value(_status),
        );

        await database.supplierDao.updateSupplier(updated);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم تحديث المورد بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // إضافة مورد جديد
        final uuid = const Uuid().v4();
        final openingBalance =
            double.tryParse(_openingBalanceController.text) ?? 0.0;

        final newSupplier = SuppliersCompanion.insert(
          id: uuid,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isNotEmpty
              ? Value(_phoneController.text.trim())
              : const Value.absent(),
          address: _addressController.text.trim().isNotEmpty
              ? Value(_addressController.text.trim())
              : const Value.absent(),
          openingBalance: Value(openingBalance),
          status: Value(_status),
          createdAt: Value(DateTime.now()),
        );

        await database.into(database.suppliers).insert(newSupplier);

        // إذا كان هناك رصيد افتتاحي، سجل حركة افتتاحية في دفتر الأستاذ
        if (openingBalance > 0) {
          await database.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id: '${uuid}_opening',
              entityType: 'Supplier',
              refId: uuid,
              date: DateTime.now(),
              description: 'رصيد افتتاحي للمورد ${_nameController.text.trim()}',
              debit: const Value(0.0),
              credit: Value(openingBalance),
              origin: 'opening',
            ),
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم إضافة المورد بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'حدث خطأ غير متوقع';
        if (e.toString().contains('UNIQUE constraint failed')) {
          errorMessage = 'اسم المورد موجود بالفعل';
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
