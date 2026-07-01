import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

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
              onPressed: () {
                // TODO: Open add device dialog/page
              },
              tooltip: 'إضافة جهاز',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _devices.isEmpty
                ? const Center(child: Text('لا توجد أجهزة مضافة.'))
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
                              IconButton(
                                icon: const Icon(Icons.sync),
                                onPressed: () => _syncDevice(device),
                                tooltip: 'مزامنة الآن',
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
