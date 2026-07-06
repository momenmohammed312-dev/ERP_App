import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';

class UnmatchedAttendancePage extends ConsumerStatefulWidget {
  const UnmatchedAttendancePage({super.key});

  @override
  ConsumerState<UnmatchedAttendancePage> createState() => _UnmatchedAttendancePageState();
}

class _UnmatchedAttendancePageState extends ConsumerState<UnmatchedAttendancePage> {
  List<AttendanceRawEvent> _unmatchedEvents = [];
  List<Staff> _allStaff = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final dao = ref.read(attendanceDeviceDaoProvider);
    final db = ref.read(appDatabaseProvider);
    final events = await dao.getUnmatchedEvents();
    final staff = await db.staffManagementDao.getActiveStaff();
    
    if (mounted) {
      setState(() {
        _unmatchedEvents = events;
        _allStaff = staff;
        _isLoading = false;
      });
    }
  }

  Future<void> _ignoreEvent(AttendanceRawEvent event) async {
    final dao = ref.read(attendanceDeviceDaoProvider);
    await dao.updateRawEvent(event.copyWith(status: 'ignored', processedAt: Value(DateTime.now())));
    _loadData();
  }

  Future<void> _assignToStaff(AttendanceRawEvent event) async {
    Staff? selectedStaff;

    final result = await showDialog<Staff>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('تعيين الحركة لموظف'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الرقم الخارجي: ${event.externalUserId}'),
              Text('الوقت: ${DateFormat('yyyy-MM-dd HH:mm').format(event.eventTime)}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<Staff>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'اختر الموظف',
                  border: OutlineInputBorder(),
                ),
                items: _allStaff.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text('${s.name} (${s.staffId})'),
                )).toList(),
                onChanged: (v) => setDialogState(() => selectedStaff = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: selectedStaff != null ? () => Navigator.pop(ctx, selectedStaff) : null,
              child: const Text('تعيين'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final dao = ref.read(attendanceDeviceDaoProvider);
        
        // Create mapping if not exists
        final existingMapping = await dao.getMappingByExternalId(
          event.deviceId,
          event.externalUserId,
        );
        
        if (existingMapping == null) {
          await dao.addMapping(StaffBiometricMappingsCompanion.insert(
            staffId: result.staffId,
            deviceId: event.deviceId,
            externalUserId: event.externalUserId,
            enrollmentStatus: 'enrolled',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
        }

        // Mark event as matched
        await dao.updateRawEvent(event.copyWith(
          status: 'matched',
          matchedStaffId: Value(result.staffId),
          processedAt: Value(DateTime.now()),
        ));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تعيين الحركة لـ ${result.name}'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    return PermissionGuard(
      permission: Permission.reviewUnmatchedAttendance,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('حركات الحضور غير المتطابقة'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _unmatchedEvents.isEmpty
                ? const Center(child: Text('لا توجد حركات غير متطابقة.'))
                : ListView.builder(
                    itemCount: _unmatchedEvents.length,
                    itemBuilder: (context, index) {
                      final event = _unmatchedEvents[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.warning, color: Colors.orange),
                          title: Text('External ID: ${event.externalUserId}'),
                          subtitle: Text('الوقت: ${dateFormat.format(event.eventTime)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.person_add, color: Colors.blue),
                                tooltip: 'تعيين لموظف',
                                onPressed: () => _assignToStaff(event),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'تجاهل',
                                onPressed: () => _ignoreEvent(event),
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
