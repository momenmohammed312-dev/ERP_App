import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_source.dart';
import 'package:pos_offline_desktop/services/attendance/zkteco_tcp_attendance_source.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';

class DeviceUserImportPage extends ConsumerStatefulWidget {
  final BiometricDevice device;

  const DeviceUserImportPage({super.key, required this.device});

  @override
  ConsumerState<DeviceUserImportPage> createState() =>
      _DeviceUserImportPageState();
}

class _DeviceUserImportPageState extends ConsumerState<DeviceUserImportPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<DeviceEnrolledUser> _deviceUsers = [];
  List<Staff> _allStaff = [];
  Map<String, StaffBiometricMapping> _existingMappingsByExternalId = {};
  
  // Selected staff mapping for each externalUserId
  final Map<String, String?> _selectedStaffForExternalId = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final db = ref.read(appDatabaseProvider);
    final staffDao = db.staffManagementDao;
    final deviceDao = ref.read(attendanceDeviceDaoProvider);

    try {
      // 1. Load system staff
      _allStaff = await staffDao.getAllStaff();

      // 2. Load existing mappings for this device
      final mappings = await deviceDao.getMappingsForDevice(widget.device.id);
      _existingMappingsByExternalId = {
        for (final m in mappings) m.externalUserId: m,
      };

      // 3. Connect to device and fetch users
      if (widget.device.connectionType == 'tcp_ip' &&
          widget.device.ipAddress != null &&
          widget.device.port != null) {
        final source = ZKTecoTcpAttendanceSource(
          ipAddress: widget.device.ipAddress!,
          port: widget.device.port!,
          authToken: widget.device.authToken,
          timeout: const Duration(seconds: 8),
        );

        final connected = await source.connect();
        if (!connected) {
          throw Exception(
            'فشل الاتصال بجهاز البصمة في ${widget.device.ipAddress}:${widget.device.port}. تأكد من عمل الجهاز واتصاله بالشبكة.',
          );
        }

        try {
          _deviceUsers = await source.fetchEnrolledUsers();
        } finally {
          await source.disconnect();
        }
      } else {
        throw Exception('نوع الاتصال غير مدعوم أو إعدادات IP غير مكتملة');
      }

      // Initialize selected staff mappings
      for (final u in _deviceUsers) {
        if (_existingMappingsByExternalId.containsKey(u.externalUserId)) {
          _selectedStaffForExternalId[u.externalUserId] =
              _existingMappingsByExternalId[u.externalUserId]!.staffId;
        } else {
          // Smart pre-selection by matching Name or Staff ID
          final matchedStaff = _findSmartMatch(u);
          _selectedStaffForExternalId[u.externalUserId] = matchedStaff?.staffId;
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Staff? _findSmartMatch(DeviceEnrolledUser user) {
    // 1. بالـ ID المباشر أو الرقم فقط (حالة شيت "1" و STAFF0001)
    for (final staff in _allStaff) {
      if (staff.staffId.toLowerCase() == user.externalUserId.toLowerCase()) return staff;
      if (staff.staffId.replaceAll(RegExp(r'[^0-9]'), '') == user.externalUserId) return staff;
      // تحقق من الخرائط الحالية: لو الموظف مربوط مسبقاً بنفس externalUserId عبر أي جهاز
      final mappedIds = _existingMappingsByExternalId.values.where((m) => m.staffId == staff.staffId).map((m) => m.externalUserId);
      if (mappedIds.contains(user.externalUserId)) return staff;
    }
    // 2. بالاسم (اسم البصمة على الجهاز مقابل اسم الموظف أو اسم البصمة المحفوظ)
    for (final staff in _allStaff) {
      final devName = user.name?.trim().toLowerCase() ?? '';
      if (devName.isNotEmpty) {
        if (staff.name.trim().toLowerCase() == devName) return staff;
        // ابحث في الخرائط عن deviceUserName مطابق
        final devNames = _existingMappingsByExternalId.values.where((m) => m.staffId == staff.staffId).map((m) => m.deviceUserName?.toLowerCase() ?? '');
        if (devNames.contains(devName)) return staff;
      }
    }
    return null;
  }

  void _autoMatchAll() {
    setState(() {
      for (final u in _deviceUsers) {
        final match = _findSmartMatch(u);
        if (match != null) {
          _selectedStaffForExternalId[u.externalUserId] = match.staffId;
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت المطابقة التلقائية الذكية بالأسماء والأكواد')),
    );
  }

  Future<void> _saveMapping(DeviceEnrolledUser user) async {
    final staffId = _selectedStaffForExternalId[user.externalUserId];
    if (staffId == null || staffId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار موظف للربط'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final dao = ref.read(attendanceDeviceDaoProvider);
    final existing = _existingMappingsByExternalId[user.externalUserId];

    try {
      if (existing != null) {
        await dao.updateMapping(
          existing.copyWith(
            staffId: staffId,
            cardNumber: Value(user.cardNumber),
            deviceUserName: Value(user.name),
            enrollmentStatus: 'enrolled',
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        await dao.addMapping(
          StaffBiometricMappingsCompanion.insert(
            staffId: staffId,
            deviceId: widget.device.id,
            externalUserId: user.externalUserId,
            deviceUserName: Value(user.name),
            cardNumber: Value(user.cardNumber),
            enrollmentStatus: 'enrolled',
            enrolledAt: Value(DateTime.now()),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      // Refresh mappings
      final mappings = await dao.getMappingsForDevice(widget.device.id);
      setState(() {
        _existingMappingsByExternalId = {
          for (final m in mappings) m.externalUserId: m,
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ ربط المستخدم ${user.externalUserId} بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ الربط: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveAllMapped() async {
    int savedCount = 0;
    final dao = ref.read(attendanceDeviceDaoProvider);

    for (final u in _deviceUsers) {
      final staffId = _selectedStaffForExternalId[u.externalUserId];
      if (staffId != null && staffId.isNotEmpty) {
        final existing = _existingMappingsByExternalId[u.externalUserId];
        if (existing != null) {
          await dao.updateMapping(
            existing.copyWith(
              staffId: staffId,
              cardNumber: Value(u.cardNumber),
              deviceUserName: Value(u.name),
              enrollmentStatus: 'enrolled',
              updatedAt: DateTime.now(),
            ),
          );
        } else {
          await dao.addMapping(
            StaffBiometricMappingsCompanion.insert(
              staffId: staffId,
              deviceId: widget.device.id,
              externalUserId: u.externalUserId,
              deviceUserName: Value(u.name),
              cardNumber: Value(u.cardNumber),
              enrollmentStatus: 'enrolled',
              enrolledAt: Value(DateTime.now()),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
        savedCount++;
      }
    }

    final mappings = await dao.getMappingsForDevice(widget.device.id);
    setState(() {
      _existingMappingsByExternalId = {
        for (final m in mappings) m.externalUserId: m,
      };
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ $savedCount مستخدم بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: Permission.manageAttendanceDevices,
      child: Scaffold(
        appBar: AppBar(
          title: Text('استيراد ومطابقة مستخدمي: ${widget.device.name}'),
          actions: [
            if (!_isLoading && _errorMessage == null && _deviceUsers.isNotEmpty) ...[
              TextButton.icon(
                icon: const Icon(Icons.auto_fix_high, color: Colors.white),
                label: const Text('مطابقة ذكية', style: TextStyle(color: Colors.white)),
                onPressed: _autoMatchAll,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('حفظ الكل'),
                onPressed: _saveAllMapped,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'جاري الاتصال بجهاز البصمة في ${widget.device.ipAddress} واستيراد المستخدمين...',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'تعذر استيراد المستخدمين',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.red),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
                onPressed: _loadData,
              ),
            ],
          ),
        ),
      );
    }

    if (_deviceUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'لا يوجد مستخدمون مسجلون في ذاكرة هذا الجهاز حالياً.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
              onPressed: _loadData,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم العثور على ${_deviceUsers.length} مستخدم في الجهاز. اختر الموظف المقابل لكل مستخدم ثم اضغط "حفظ".',
                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _deviceUsers.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final user = _deviceUsers[index];
              final isMapped = _existingMappingsByExternalId.containsKey(user.externalUserId);
              final currentSelectedStaffId = _selectedStaffForExternalId[user.externalUserId];

              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isMapped ? Colors.green.shade300 : Colors.grey.shade300,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isMapped ? Colors.green.shade100 : Colors.grey.shade200,
                        child: Icon(
                          isMapped ? Icons.check_circle : Icons.fingerprint,
                          color: isMapped ? Colors.green : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'رقم المستخدم بالجهاز: ${user.externalUserId}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              'الاسم بالجهاز: ${user.name?.isNotEmpty == true ? user.name : "(بدون اسم)"}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            if (user.cardNumber != null && user.cardNumber!.isNotEmpty)
                              Text(
                                'رقم الكارت: ${user.cardNumber}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<String>(
                          value: currentSelectedStaffId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'الموظف في النظام',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('--- غير مربوط ---', style: TextStyle(color: Colors.grey)),
                            ),
                            ..._allStaff.map(
                              (s) => DropdownMenuItem<String>(
                                value: s.staffId,
                                child: Text('${s.name} (${s.staffId})'),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedStaffForExternalId[user.externalUserId] = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: Icon(
                          isMapped ? Icons.check : Icons.save,
                          color: isMapped ? Colors.green : Colors.blue,
                        ),
                        tooltip: 'حفظ هذا الربط',
                        onPressed: () => _saveMapping(user),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
