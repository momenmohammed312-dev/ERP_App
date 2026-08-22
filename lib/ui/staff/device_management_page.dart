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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('جاري مزامنة جهاز ${device.name}...')));
      final syncService = ref.read(attendanceSyncServiceProvider);
      final user = ref.read(authProvider);
      await syncService.syncDevice(device, triggeredBy: user?.username ?? 'manual');
      
      // Re-fetch device to check actual sync result
      final dao = ref.read(attendanceDeviceDaoProvider);
      final updatedDevice = await dao.getDeviceById(device.id);
      
      await _loadDevices();
      if (mounted) {
        if (updatedDevice?.lastSyncStatus == 'success') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت المزامنة بنجاح')));
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
      Navigator.pop(context); // Dismiss loading dialog

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
      builder: (context) =>
          _AddDeviceDialog(onDeviceAdded: _loadDevices, device: device),
    );
  }

  void _confirmDeleteDevice(BiometricDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الجهاز'),
        content: Text('هل أنت متأكد من حذف الجهاز "${device.name}"؟\nسيتم حذف جميع الحركات المرتبطة به.'),
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
                await dao.deleteDevice(device.id);
                _loadDevices();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف الجهاز'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ في الحذف: $e'), backgroundColor: Colors.red),
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
        Navigator.pop(context);
        widget.onDeviceAdded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة الجهاز بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إضافة الجهاز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
