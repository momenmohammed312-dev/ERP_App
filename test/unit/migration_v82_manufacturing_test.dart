import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Dedicated migration test for Schema v82 — reconciliation records
/// (consumption_records, stage_yields, external_operation_records,
/// production_completed_at, output disposition) — FEAT-039 Phase 1.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  Future<Set<String>> tableNames(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<Set<String>> indexNames(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<List<String>> columns(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<int> userVersion(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test('v82: fresh DB has v82 tables, v82 columns and v82 indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());

    expect(await userVersion(db), db.schemaVersion);
    expect(db.schemaVersion, greaterThanOrEqualTo(82));

    final tables = await tableNames(db);
    expect(tables, containsAll([
      'consumption_records',
      'stage_yields',
      'external_operation_records',
    ]));

    expect(await columns(db, 'manufacturing_orders'), contains('production_completed_at'));
    expect(await columns(db, 'manufacturing_stage_outputs'), contains('disposition'));

    final indexes = await indexNames(db);
    expect(indexes, containsAll([
      'idx_consumption_records_order',
      'idx_consumption_records_product',
      'idx_stage_yields_order',
      'idx_stage_yields_stage',
      'idx_external_ops_order',
    ]));

    await db.close();
  });

  test('v82: upgrade from simulated v81 re-creates v82 tables/columns/indexes', () async {
    final tempDir = Directory.systemTemp.createTempSync('v82_migration_test_');
    final dbFile = File('${tempDir.path}/sim_v81.db');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1. Build fresh v82 DB, then simulate v81 by dropping v82 artifacts.
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    await db.close();

    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute('DROP TABLE IF EXISTS consumption_records;');
      raw.execute('DROP TABLE IF EXISTS stage_yields;');
      raw.execute('DROP TABLE IF EXISTS external_operation_records;');
      raw.execute('PRAGMA user_version = 81;');
    } finally {
      raw.dispose();
    }

    // 2. Re-open: onUpgrade must re-run _runV82ManufacturingReconciliation.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    try {
      await db2.customSelect('SELECT 1').get();
      expect(await userVersion(db2), db2.schemaVersion);

      final tables = await tableNames(db2);
      expect(tables, containsAll([
        'consumption_records',
        'stage_yields',
        'external_operation_records',
      ]));

      expect(await columns(db2, 'manufacturing_orders'), contains('production_completed_at'));
      expect(await columns(db2, 'manufacturing_stage_outputs'), contains('disposition'));

      final indexes = await indexNames(db2);
      expect(indexes, containsAll([
        'idx_consumption_records_order',
        'idx_consumption_records_product',
        'idx_stage_yields_order',
        'idx_stage_yields_stage',
        'idx_external_ops_order',
      ]));
    } finally {
      await db2.close();
    }
  });
}
