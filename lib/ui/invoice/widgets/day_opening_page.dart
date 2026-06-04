import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/validation/permission_validator.dart';

class DayOpeningPage extends ConsumerStatefulWidget {
  final AppDatabase db;

  const DayOpeningPage({super.key, required this.db});

  @override
  ConsumerState<DayOpeningPage> createState() => _DayOpeningPageState();
}

class _DayOpeningPageState extends ConsumerState<DayOpeningPage> {
  final _openingBalanceController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _openDay() async {
    if (_openingBalanceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال الرصيد الافتتاحي'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = ref.read(authProvider);
      PermissionValidator.requirePermission(currentUser, Permission.openDay, 'فتح اليوم');

      final openingBalance =
          double.tryParse(_openingBalanceController.text) ?? 0.0;
      final openedBy = currentUser?.username ?? '';
      await widget.db.dayDao.openDay(openingBalance: openingBalance, openedBy: openedBy);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فتح اليوم بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        // Close both the day opening page and go back to invoice
        Navigator.of(context).pop();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فتح اليوم: $e'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فتح اليوم'),
        backgroundColor: Colors.black54,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.store, size: 64, color: Colors.blue),
              const Gap(16),
              const Text(
                'فتح يوم جديد',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Gap(32),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _openingBalanceController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'الرصيد الافتتاحي',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                    prefixText: 'ج.م ',
                  ),
                ),
              ),
              const Gap(24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _openDay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                      child: const Text(
                        'فتح اليوم',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
