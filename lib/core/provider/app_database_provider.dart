// ignore_for_file: depend_on_referenced_packages
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart'; // ← Solution: handles Web/Windows/macOS automatically
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_flavor.dart';
import '../database/app_database.dart';
import '../services/business_date_service.dart';
import '../services/invoice_service.dart';
import '../services/shipment_allocation_service.dart';
import '../../services/staff_management_service.dart';
import '../database/dao/attendance_device_dao.dart';
import '../../services/attendance/attendance_sync_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// Singleton provider for AppDatabase
// drift_flutter's driftDatabase() handles platform-conditional imports
// internally — no need to import drift/wasm.dart or drift/native.dart manually
// ════════════════════════════════════════════════════════════════════════════

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(_openConnection());
  ref.onDispose(() => db.close());
  return db;
});

// Helper provider for database access in widgets
final databaseProvider = Provider<AppDatabase>((ref) {
  return ref.watch(appDatabaseProvider);
});

final businessDateServiceProvider = Provider<BusinessDateService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return BusinessDateService(db);
});

final staffManagementServiceProvider = Provider<StaffManagementService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StaffManagementService(db.staffManagementDao, db);
});

final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return InvoiceService(db);
});

final shipmentAllocationServiceProvider = Provider<ShipmentAllocationService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ShipmentAllocationService(
    db.vegetableShipmentDao,
    db.emptyBarnikaTrackingDao,
  );
});

final attendanceDeviceDaoProvider = Provider<AttendanceDeviceDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.attendanceDeviceDao;
});

final attendanceSyncServiceProvider = Provider<AttendanceSyncService>((ref) {
  final deviceDao = ref.watch(attendanceDeviceDaoProvider);
  final db = ref.watch(appDatabaseProvider);
  return AttendanceSyncService(deviceDao, db.staffManagementDao);
});

QueryExecutor _openConnection() {
  // driftDatabase() automatically selects the right backend:
  // • Windows/macOS/Linux → NativeDatabase (dart:io)
  // • Web → WasmDatabase (drift/wasm.dart) — compiled separately
  // No more "dart:html not available on this platform" errors!
  return driftDatabase(
    name: AppFlavor.databaseName,
    native: const DriftNativeOptions(shareAcrossIsolates: true),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('/sqlite3.wasm'),
      driftWorker: Uri.parse('/drift_worker.dart.js'),
    ),
  );
}

// ملاحظات مهمة
// لا تنشئ AppDatabase() في أي مكان آخر (ابحث عن كل new AppDatabase() واستبدلها بقراءة المزود)
// لا تستخدم ProviderContainer() محليًا لإنشاء مزود جديد — استخدم ref.read(appDatabaseProvider) أو ref.watch(...) داخل Widgets/Mixins الخاصة بـ Riverpod

// عند استخدام المزود بشكل صحيح داخل الواجهات
// إذا الصفحة Stateful وتستخدم Riverpod، اجعلها ConsumerStatefulWidget ثم في initState استخدم ref.read(...) من ConsumerState

// مثال صحيح للاستخدام المزود
class ExampleReportsUsage extends ConsumerStatefulWidget {
  const ExampleReportsUsage({super.key});

  @override
  ConsumerState<ExampleReportsUsage> createState() =>
      _ExampleReportsUsageState();
}

class _ExampleReportsUsageState extends ConsumerState<ExampleReportsUsage> {
  @override
  void initState() {
    super.initState();
    // قراءة قاعدة البيانات من المزود (لا ينشئ نسخة جديدة)
    final db = ref.read(appDatabaseProvider);
    _loadReportsData(db);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مثال التقارير')),
      body: const Center(child: Text('Reports Page Example')),
    );
  }

  Future<void> _loadReportsData(AppDatabase db) async {
    try {
      // استخدام المزود لقراءة البيانات - استدعاء دالة موجودة
      final invoices = await db.select(db.invoices).get();
      debugPrint('Loaded ${invoices.length} invoices');
    } catch (e, st) {
      // تعامل مع الخطأ بدل استخدام ! على قيمة قد تكون null
      debugPrint('Error loading reports data: $e\n$st');
    }
  }
}
