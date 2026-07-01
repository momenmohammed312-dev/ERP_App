import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class BiometricEnrollmentPage extends ConsumerStatefulWidget {
  final Staff staff;

  const BiometricEnrollmentPage({super.key, required this.staff});

  @override
  ConsumerState<BiometricEnrollmentPage> createState() => _BiometricEnrollmentPageState();
}

class _BiometricEnrollmentPageState extends ConsumerState<BiometricEnrollmentPage> {
  List<StaffBiometricMapping> _mappings = [];
  List<BiometricDevice> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final dao = ref.read(attendanceDeviceDaoProvider);
    final mappings = await dao.getMappingsForStaff(widget.staff.staffId);
    final devices = await dao.getAllDevices();
    
    if (mounted) {
      setState(() {
        _mappings = mappings;
        _devices = devices;
        _isLoading = false;
      });
    }
  }

  void _showAddMappingDialog() {
    if (_devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد أجهزة مسجلة')));
      return;
    }
    
    BiometricDevice? selectedDevice = _devices.first;
    final externalIdController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('إضافة بصمة للموظف'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<BiometricDevice>(
                      value: selectedDevice,
                      items: _devices.map((d) => DropdownMenuItem(value: d, child: Text(d.name))).toList(),
                      onChanged: (v) => setState(() => selectedDevice = v),
                      decoration: const InputDecoration(labelText: 'الجهاز'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: externalIdController,
                      decoration: const InputDecoration(
                        labelText: 'الرقم التعريفي في الجهاز (External ID)',
                        hintText: 'مثال: 1001',
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                        LengthLimitingTextInputFormatter(50),
                      ],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'الرقم التعريفي مطلوب';
                        }
                        if (value.length > 50) {
                          return 'الرقم التعريفي طويل جداً (حد أقصى 50 حرف)';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedDevice == null) return;
                    
                    final dao = ref.read(attendanceDeviceDaoProvider);
                    
                    // Check for existing mapping on this device
                    final existing = await dao.getMappingByExternalId(
                      selectedDevice!.id,
                      externalIdController.text.trim(),
                    );
                    
                    if (existing != null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('هذا الرقم التعريفي مسجل بالفعل على هذا الجهاز'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }
                    
                    try {
                      await dao.addMapping(StaffBiometricMappingsCompanion.insert(
                        staffId: widget.staff.staffId,
                        deviceId: selectedDevice!.id,
                        externalUserId: externalIdController.text.trim(),
                        enrollmentStatus: 'enrolled',
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ));
                      
                      if (mounted) {
                        Navigator.pop(context);
                        _loadData();
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('فشل في حفظ البصمة'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _confirmDeleteMapping(StaffBiometricMapping mapping) {
    final deviceName = _devices.where((d) => d.id == mapping.deviceId).firstOrNull?.name ?? 'Unknown Device';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف البصمة'),
        content: Text('هل أنت متأكد من حذف البصمة "${mapping.externalUserId}" من جهاز "$deviceName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final dao = ref.read(attendanceDeviceDaoProvider);
                await dao.deleteMapping(mapping.id);
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('فشل في حذف البصمة'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: Permission.manageBiometricEnrollment,
      child: Scaffold(
        appBar: AppBar(
          title: Text('بصمات الموظف: ${widget.staff.name}'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _mappings.isEmpty
                ? const Center(child: Text('لا توجد بصمات مسجلة لهذا الموظف.'))
                : ListView.builder(
                    itemCount: _mappings.length,
                    itemBuilder: (context, index) {
                      final mapping = _mappings[index];
                      final deviceName = _devices.where((d) => d.id == mapping.deviceId).firstOrNull?.name ?? 'Unknown Device';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.fingerprint),
                          title: Text('ID الجهاز: ${mapping.externalUserId}'),
                          subtitle: Text('جهاز: $deviceName'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _confirmDeleteMapping(mapping),
                          ),
                        ),
                      );
                    },
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddMappingDialog,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
