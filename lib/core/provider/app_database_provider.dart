import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift/wasm.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';

// Singleton provider for AppDatabase
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(_openConnection());
  ref.onDispose(() => db.close());
  return db;
});

// Helper provider for database access in widgets that don't have direct provider access
final databaseProvider = Provider<AppDatabase>((ref) {
  return ref.watch(appDatabaseProvider);
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    if (kIsWeb) {
      final result = await WasmDatabase.open(
        databaseName: 'pos_offline_desktop_database',
        sqlite3Uri: Uri.parse('/sqlite3.wasm'),
        driftWorkerUri: Uri.parse('/drift_worker.dart.js'),
      );
      return result.resolvedExecutor;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbDir = Directory(
        p.join(dbFolder.path, 'pos_offline_desktop_database'),
      );

      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      final file = File(
        p.join(dbDir.path, 'pos_offline_desktop_database.sqlite'),
      );

      return NativeDatabase(file);
    }
  });
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
