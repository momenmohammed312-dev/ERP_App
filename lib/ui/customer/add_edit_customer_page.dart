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

  const AddEditCustomerPage({super.key, this.customer});

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

  bool _isLoading = false;
  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'تعديل عميل' : 'إضافة عميل جديد'),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // اسم العميل
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'اسم العميل *',
                    hintText: 'أدخل اسم العميل',
                    prefixIcon: const Icon(Icons.person),
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
                      if (value.length < 10) {
                        return 'رقم الهاتف يجب أن يكون 10 أرقام على الأقل';
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
                    hintText: 'example@email.com',
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

                // الرقم الضريبي
                TextFormField(
                  controller: _gstinController,
                  decoration: InputDecoration(
                    labelText: 'الرقم الضريبي',
                    hintText: 'أدخل الرقم الضريبي',
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
                    hintText: 'أدخل العنوان',
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
                    hintText: 'أدخل ملاحظات إضافية',
                    prefixIcon: const Icon(Icons.notes),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                ),

                const Gap(32),

                // زر الحفظ
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveCustomer,
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
                          _isEditing ? 'تحديث العميل' : 'حفظ العميل',
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
          isActive: const Value(true),
          status: const Value('Active'),
          createdAt: Value(DateTime.now()),
        );

        await database.customerDao.insertCustomer(newCustomer);

        if (openingBalance != 0.0) {
          await database.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id: '${DateTime.now().millisecondsSinceEpoch}_opening',
              entityType: 'Customer',
              refId: uuid,
              date: DateTime.now(),
              description: 'رصيد افتتاحي للعميل ${_nameController.text.trim()}',
              debit: Value(openingBalance > 0 ? openingBalance : 0.0),
              credit: Value(openingBalance < 0 ? -openingBalance : 0.0),
              origin: 'opening',
              paymentMethod: const Value('cash'),
            ),
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم إضافة العميل بنجاح'),
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
