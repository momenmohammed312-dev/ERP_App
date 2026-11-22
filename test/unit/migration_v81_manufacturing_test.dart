import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Dedicated migration test for Schema v81 — manufacturing_stages,
/// manufacturing_stage_outputs, v81 columns, and v81 indexes.
///
/// v80 historical coverage lives in `migration_v80_unified_test.dart`
/// (version-agnostic: expects `schemaVersion`, not a hardcoded 80).
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

  test('v81: fresh DB has manufacturing_stages, manufacturing_stage_outputs, v81 columns, v81 indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());

    expect(await userVersion(db), db.schemaVersion);

    final tables = await tableNames(db);
    expect(tables, contains('manufacturing_stages'));
    expect(tables, contains('manufacturing_stage_outputs'));

    expect(
        await columns(db, 'manufacturing_orders'),
        containsAll([
          'current_stage_name',
          'target_margin_percent',
        ]));
    expect(
        await columns(db, 'manufacturing_scrap'),
        containsAll([
          'stage_id',
          'variant_id',
          'variant_name',
          'is_sellable',
          'estimated_sell_price',
          'scrap_product_id',
        ]));

    final indexes = await indexNames(db);
    expect(indexes, containsAll([
      'idx_stages_order',
      'idx_stage_outputs_stage',
      'idx_stage_outputs_order',
    ]));

    await db.close();
  });

  test('v81: upgrade from simulated v80 re-creates stages tables, columns and indexes', () async {
    final tempDir = Directory.systemTemp.createTempSync('v81_migration_test_');
    final dbFile = File('${tempDir.path}/sim_v80.db');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1. Build a fresh v82 DB (v81 tables exist since the upgrade chain runs
    //    onUpgrade when we stamp 80), then simulate v80 by dropping v81
    //    artifacts.
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    await db.close();

    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute('DROP TABLE IF EXISTS manufacturing_stage_outputs;');
      raw.execute('DROP TABLE IF EXISTS manufacturing_stages;');
      raw.execute('PRAGMA user_version = 80;');
    } finally {
      raw.dispose();
    }

    // 2. Re-open: onUpgrade must re-run the v81 migration (and the v82 one,
    //    since schemaVersion is now 82 — the v81 tables are recreated first).
    final db2 = AppDatabase(NativeDatabase(dbFile));
    try {
      await db2.customSelect('SELECT 1').get();
      expect(await userVersion(db2), db2.schemaVersion);

      final tables = await tableNames(db2);
      expect(tables, contains('manufacturing_stages'));
      expect(tables, contains('manufacturing_stage_outputs'));

      expect(
          await columns(db2, 'manufacturing_orders'),
          containsAll([
            'current_stage_name',
            'target_margin_percent',
          ]));
      expect(
          await columns(db2, 'manufacturing_scrap'),
          containsAll([
            'stage_id',
            'variant_id',
            'variant_name',
            'is_sellable',
            'estimated_sell_price',
            'scrap_product_id',
          ]));

      final indexes = await indexNames(db2);
      expect(indexes, containsAll([
        'idx_stages_order',
        'idx_stage_outputs_stage',
        'idx_stage_outputs_order',
      ]));
    } finally {
      await db2.close();
    }
  });
}
