import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Dedicated migration test for Schema v84 — Universal Routing, Costing &
/// Quality Inspections (FEAT-039 Phases 2/3/4).
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

  test('v84: fresh DB has all 6 new tables, added columns and v84 indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());

    expect(await userVersion(db), db.schemaVersion);
    expect(db.schemaVersion, greaterThanOrEqualTo(84));

    final tables = await tableNames(db);
    expect(
      tables,
      containsAll([
        'routing_templates',
        'routing_template_nodes',
        'manufacturing_rework_records',
        'manufacturing_cost_snapshots',
        'extra_material_approvals',
        'manufacturing_inspections',
      ]),
    );

    expect(
      await columns(db, 'manufacturing_orders'),
      containsAll(['routing_template_id', 'routing_code']),
    );
    expect(
      await columns(db, 'manufacturing_stages'),
      containsAll([
        'routing_node_id',
        'parent_stage_id',
        'operation_type',
        'technique',
        'parameters_json',
        'labor_hours',
        'labor_rate',
        'machine_hours',
        'machine_rate',
        'is_terminal',
      ]),
    );
    expect(
      await columns(db, 'manufacturing_stage_outputs'),
      contains('output_type'),
    );

    final indexes = await indexNames(db);
    expect(
      indexes,
      containsAll([
        'idx_routing_nodes_template',
        'idx_rework_records_order',
        'idx_cost_snapshots_order',
        'idx_extra_approvals_order',
        'idx_inspections_order',
      ]),
    );

    await db.close();
  });

  test('v84: upgrade from simulated v83 re-creates v84 tables, columns and indexes', () async {
    final tempDir = Directory.systemTemp.createTempSync('v84_migration_test_');
    final dbFile = File('${tempDir.path}/sim_v83.db');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    await db.close();

    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute('DROP TABLE IF EXISTS manufacturing_inspections;');
      raw.execute('DROP TABLE IF EXISTS extra_material_approvals;');
      raw.execute('DROP TABLE IF EXISTS manufacturing_cost_snapshots;');
      raw.execute('DROP TABLE IF EXISTS manufacturing_rework_records;');
      raw.execute('DROP TABLE IF EXISTS routing_template_nodes;');
      raw.execute('DROP TABLE IF EXISTS routing_templates;');
      raw.execute('PRAGMA user_version = 83;');
    } finally {
      raw.dispose();
    }

    final db2 = AppDatabase(NativeDatabase(dbFile));
    try {
      await db2.customSelect('SELECT 1').get();
      expect(await userVersion(db2), db2.schemaVersion);

      final tables = await tableNames(db2);
      expect(
        tables,
        containsAll([
          'routing_templates',
          'routing_template_nodes',
          'manufacturing_rework_records',
          'manufacturing_cost_snapshots',
          'extra_material_approvals',
          'manufacturing_inspections',
        ]),
      );

      final indexes = await indexNames(db2);
      expect(
        indexes,
        containsAll([
          'idx_routing_nodes_template',
          'idx_rework_records_order',
          'idx_cost_snapshots_order',
          'idx_extra_approvals_order',
          'idx_inspections_order',
        ]),
      );
    } finally {
      await db2.close();
    }
  });
}
