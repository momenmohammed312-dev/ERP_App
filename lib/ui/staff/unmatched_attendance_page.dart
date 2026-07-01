import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

class UnmatchedAttendancePage extends ConsumerStatefulWidget {
  const UnmatchedAttendancePage({super.key});

  @override
  ConsumerState<UnmatchedAttendancePage> createState() => _UnmatchedAttendancePageState();
}

class _UnmatchedAttendancePageState extends ConsumerState<UnmatchedAttendancePage> {
  List<AttendanceRawEvent> _unmatchedEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final dao = ref.read(attendanceDeviceDaoProvider);
    final events = await dao.getUnmatchedEvents();
    
    if (mounted) {
      setState(() {
        _unmatchedEvents = events;
        _isLoading = false;
      });
    }
  }

  Future<void> _ignoreEvent(AttendanceRawEvent event) async {
    final dao = ref.read(attendanceDeviceDaoProvider);
    await dao.updateRawEvent(event.copyWith(status: 'ignored', processedAt: Value(DateTime.now())));
    _loadData();
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
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'تجاهل',
                            onPressed: () => _ignoreEvent(event),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
