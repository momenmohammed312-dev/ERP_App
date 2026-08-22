import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:drift/drift.dart' show Value;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/attendance/zkteco_tcp_attendance_source.dart';
import 'device_user_import_page.dart';

class DeviceManagementPage extends ConsumerStatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  ConsumerState<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends ConsumerState<DeviceManagementPage> {
  List<BiometricDevice> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final dao = ref.read(attendanceDeviceDaoProvider);
    final devices = await dao.getAllDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncDevice(BiometricDevice device) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('جاري مزامنة جهاز ${device.name}...')),
      );
      final syncService = ref.read(attendanceSyncServiceProvider);
      final user = ref.read(authProvider);
      await syncService.syncDevice(device, triggeredBy: user?.username ?? 'manual');

      final dao = ref.read(attendanceDeviceDaoProvider);
      final updatedDevice = await dao.getDeviceById(device.id);

      await _loadDevices();
      if (mounted) {
        if (updatedDevice?.lastSyncStatus == 'success') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت المزامنة بنجاح')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فشلت المزامنة'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشلت المزامنة'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _testDeviceConnection(BiometricDevice device) async {
    if (device.connectionType != 'tcp_ip' || device.ipAddress == null || device.port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فحص الاتصال متاح فقط للأجهزة المتصلة عبر الشبكة (TCP/IP)')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final stopwatch = Stopwatch()..start();
    try {
      final source = ZKTecoTcpAttendanceSource(
        ipAddress: device.ipAddress!,
        port: device.port!,
        authToken: device.authToken,
        timeout: const Duration(seconds: 5),
      );

      final connected = await source.connect();
      stopwatch.stop();

      if (!mounted) return;
      Navigator.pop(context);

      if (connected) {
        final info = await source.getDeviceInfo();
        await source.disconnect();

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('الاتصال بالجهاز ناجح'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اسم الجهاز: ${info.deviceName ?? device.name}'),
                Text('عنوان IP: ${device.ipAddress}:${device.port}'),
                Text('وقت الاستجابة: ${stopwatch.elapsedMilliseconds} ms'),
                if (info.firmwareVersion != null) Text('إصدار الفيرموير: ${info.firmwareVersion}'),
                if (info.serialNumber != null) Text('الرقم التسلسلي: ${info.serialNumber}'),
                if (info.deviceTime != null) Text('توقيت الجهاز: ${info.deviceTime}'),
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
      } else {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('فشل الاتصال بالجهاز'),
              ],
            ),
            content: Text(
              'تعذر الوصول إلى الجهاز في ${device.ipAddress}:${device.port}.\n'
              'يرجى التأكد من:\n'
              '1. تشغيل الجهاز وتوصيله بالشبكة المحلية.\n'
              '2. صحة الـ IP والمنفذ (4370).\n'
              '3. صحة مفتاح الاتصال (Communication Key) إن وجد.',
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
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('خطأ أثناء فحص الاتصال'),
          content: Text('حدث خطأ: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    }
  }

  void _showAddDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddDeviceDialog(onDeviceAdded: _loadDevices),
    );
  }

  void _showEditDeviceDialog(BiometricDevice device) {
    showDialog(
      context: context,
      builder: (context) => _AddDeviceDialog(onDeviceAdded: _loadDevices, device: device),
    );
  }

  void _confirmDeleteDevice(BiometricDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الجهاز'),
        content: Text(
          'هل أنت متأكد من حذف الجهاز "${device.name}"?\nسيتم حذف جميع الحركات المرتبطة به.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                final dao = ref.read(attendanceDeviceDaoProvider);
                await dao.deleteDevice(device.id);
                _loadDevices();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('تم حذف الجهاز'), backgroundColor: Colors.green),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('خطأ في الحذف: $e'), backgroundColor: Colors.red),
                );
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
      permission: Permission.manageAttendanceDevices,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة أجهزة الحضور'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddDeviceDialog,
              tooltip: 'إضافة جهاز',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _devices.isEmpty
                ? const Center(child: Text('لا توجد أجهزة مضافة. اضغط + لإضافة جهاز.'))
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.device_hub),
                          title: Text(device.name),
                          subtitle: Text('${device.connectionType} - ${device.ipAddress ?? "N/A"}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                device.lastSyncStatus == null
                                    ? 'لم يتم المزامنة'
                                    : device.lastSyncStatus == 'success'
                                        ? 'متصل'
                                        : 'مفصول/خطأ',
                                style: TextStyle(
                                  color: device.lastSyncStatus == null
                                      ? Colors.grey
                                      : device.lastSyncStatus == 'success'
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.wifi_find, color: Colors.teal),
                                onPressed: () => _testDeviceConnection(device),
                                tooltip: 'اختبار الاتصال',
                              ),
                              IconButton(
                                icon: const Icon(Icons.group_add, color: Colors.blue),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DeviceUserImportPage(device: device),
                                    ),
                                  );
                                },
                                tooltip: 'استيراد ومطابقة المستخدمين',
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync),
                                onPressed: () => _syncDevice(device),
                                tooltip: 'مزامنة الآن',
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.orange),
                                onPressed: () => _showEditDeviceDialog(device),
                                tooltip: 'تعديل البيانات',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _confirmDeleteDevice(device),
                                tooltip: 'حذف الجهاز',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

// ===== Dialog إضافة / تعديل جهاز =====

class _AddDeviceDialog extends ConsumerStatefulWidget {
  final VoidCallback onDeviceAdded;
  final BiometricDevice? device;
  const _AddDeviceDialog({required this.onDeviceAdded, this.device});

  @override
  ConsumerState<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends ConsumerState<_AddDeviceDialog> {
  final _nameController = TextEditingController();
  final _deviceCodeController = TextEditingController();
  final _vendorController = TextEditingController();
  final _modelController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '4370');
  final _serialController = TextEditingController();
  final _locationController = TextEditingController();
  final _authTokenController = TextEditingController();
  String _connectionType = 'tcp_ip';
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.device != null;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    if (d != null) {
      // وضع التعديل: تعبئة الحقول بالبيانات المحفوظة للجهاز
      _nameController.text = d.name;
      _deviceCodeController.text = d.deviceCode;
      _connectionType = d.connectionType;
      _vendorController.text = d.vendor ?? '';
      _modelController.text = d.model ?? '';
      _ipController.text = d.ipAddress ?? '';
      _portController.text = d.port?.toString() ?? '4370';
      _serialController.text = d.serialNumber ?? '';
      _locationController.text = d.location ?? '';
      _authTokenController.text = d.authToken ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _deviceCodeController.dispose();
    _vendorController.dispose();
    _modelController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _serialController.dispose();
    _locationController.dispose();
    _authTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'تعديل بيانات الجهاز' : 'إضافة جهاز حضور جديد'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الجهاز *',
                  hintText: 'مثال: بوابة الدخول الرئيسية',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceCodeController,
                decoration: const InputDecoration(
                  labelText: 'كود الجهاز *',
                  hintText: 'مثال: BIO-001',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _connectionType,
                decoration: const InputDecoration(labelText: 'نوع الاتصال *'),
                items: const [
                  DropdownMenuItem(value: 'tcp_ip', child: Text('TCP/IP')),
                  DropdownMenuItem(value: 'usb_import', child: Text('استيراد USB')),
                  DropdownMenuItem(value: 'sdk', child: Text('SDK')),
                  DropdownMenuItem(value: 'file_import', child: Text('استيراد ملف')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _connectionType = v);
                },
              ),
              if (_connectionType == 'tcp_ip') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان IP *',
                    hintText: '192.168.1.100',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_connectionType == 'tcp_ip' && (v == null || v.trim().isEmpty)) {
                      return 'مطلوب للاتصال TCP/IP';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'البورت *',
                    hintText: '4370',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_connectionType == 'tcp_ip' && (v == null || v.trim().isEmpty)) {
                      return 'مطلوب';
                    }
                    if (v != null && v.isNotEmpty && int.tryParse(v) == null) {
                      return 'رقم صحيح مطلوب';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _vendorController,
                decoration: const InputDecoration(
                  labelText: 'الشركة المصنعة',
                  hintText: 'ZKTeco, Hikvision',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelController,
                decoration: const InputDecoration(labelText: 'الموديل'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serialController,
                decoration: const InputDecoration(labelText: 'الرقم التسلسلي'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'الموقع',
                  hintText: 'الفرع الرئيسي، بوابة 1',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _authTokenController,
                decoration: const InputDecoration(labelText: 'Auth Token (اختياري)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final db = ref.read(appDatabaseProvider);
      final dao = db.attendanceDeviceDao;
      final now = DateTime.now();

      // التحقق من عدم تكرار كود الجهاز (مع استثناء الجهاز نفسه في وضع التعديل)
      final existingDevices = await dao.getAllDevices();
      final codeExists = existingDevices.any(
        (d) => d.deviceCode == _deviceCodeController.text.trim() && d.id != widget.device?.id,
      );
      if (codeExists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كود الجهاز موجود بالفعل'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (_isEditing) {
        // تحديث بيانات الجهاز الموجود — copyWith يحافظ على id/createdAt/lastSyncAt تلقائياً
        final updated = widget.device!.copyWith(
          deviceCode: _deviceCodeController.text.trim(),
          name: _nameController.text.trim(),
          connectionType: _connectionType,
          vendor: Value(_vendorController.text.trim().isEmpty ? null : _vendorController.text.trim()),
          model: Value(_modelController.text.trim().isEmpty ? null : _modelController.text.trim()),
          ipAddress: _connectionType == 'tcp_ip' ? Value(_ipController.text.trim()) : const Value(null),
          port: _connectionType == 'tcp_ip' && _portController.text.isNotEmpty
              ? Value(int.tryParse(_portController.text.trim()))
              : const Value(null),
          serialNumber: Value(_serialController.text.trim().isEmpty ? null : _serialController.text.trim()),
          location: Value(_locationController.text.trim().isEmpty ? null : _locationController.text.trim()),
          authToken: Value(_authTokenController.text.trim().isEmpty ? null : _authTokenController.text.trim()),
          updatedAt: now,
        );
        await dao.updateDevice(updated);

        if (!mounted) return;
        Navigator.pop(context);
        widget.onDeviceAdded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث بيانات الجهاز بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      // إضافة جهاز جديد
      await dao.addDevice(BiometricDevicesCompanion.insert(
        deviceCode: _deviceCodeController.text.trim(),
        name: _nameController.text.trim(),
        connectionType: _connectionType,
        vendor: Value(_vendorController.text.trim().isEmpty ? null : _vendorController.text.trim()),
        model: Value(_modelController.text.trim().isEmpty ? null : _modelController.text.trim()),
        ipAddress: _connectionType == 'tcp_ip' ? Value(_ipController.text.trim()) : const Value(null),
        port: _connectionType == 'tcp_ip' && _portController.text.isNotEmpty
            ? Value(int.parse(_portController.text.trim()))
            : const Value(null),
        serialNumber: Value(_serialController.text.trim().isEmpty ? null : _serialController.text.trim()),
        location: Value(_locationController.text.trim().isEmpty ? null : _locationController.text.trim()),
        authToken: Value(_authTokenController.text.trim().isEmpty ? null : _authTokenController.text.trim()),
        createdAt: now,
        updatedAt: now,
      ));

      if (!mounted) return;
      Navigator.pop(context);
      widget.onDeviceAdded();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إضافة الجهاز بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في حفظ الجهاز: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
