import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/day_table.dart';

part 'day_dao.g.dart';

@DriftAccessor(tables: [Days])
class DayDao extends DatabaseAccessor<AppDatabase> with _$DayDaoMixin {
  DayDao(super.db);

  Future<Map<String, Object?>?> getTodayDay() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final row = await customSelect(
      'SELECT * FROM days WHERE date >= ? AND date < ? LIMIT 1',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
    ).getSingleOrNull();

    return row?.data;
  }

  /// The single authoritative open day row (oldest first), or null when no
  /// business day is open. `days` is the source of truth for "is the day
  /// open?" — cash sessions only mirror it.
  Future<Map<String, Object?>?> getOpenDay() async {
    final row = await customSelect(
      'SELECT * FROM days WHERE is_open = 1 ORDER BY id ASC LIMIT 1',
    ).getSingleOrNull();
    return row?.data;
  }

  /// Every open day row (oldest first). More than one means a legacy
  /// duplicate that the v70 migration / repair must reconcile — callers must
  /// never silently pick one and hide the rest.
  Future<List<Map<String, Object?>>> getOpenDays() async {
    final rows = await customSelect(
      'SELECT * FROM days WHERE is_open = 1 ORDER BY id ASC',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<int> openDay({required double openingBalance, String? openedBy}) async {
    final isOpen = await isDayOpen();
    if (isOpen) {
      throw Exception('يوجد يوم مفتوح بالفعل');
    }
    final id = await customInsert(
      'INSERT INTO days (date, is_open, opening_balance, created_at, opened_by) VALUES (?, ?, ?, ?, ?)',
      variables: [
        Variable.withDateTime(DateTime.now()),
        Variable.withBool(true),
        Variable.withReal(openingBalance),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(openedBy ?? ''),
      ],
    );
    return id;
  }

  Future<void> closeDay({
    required int dayId,
    required double closingBalance,
    String? notes,
    String? closedBy,
  }) async {
    await customUpdate(
      'UPDATE days SET is_open = 0, closing_balance = ?, notes = ?, closed_at = ?, closed_by = ? WHERE id = ?',
      variables: [
        Variable.withReal(closingBalance),
        Variable.withString(notes ?? ''),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(closedBy ?? ''),
        Variable.withInt(dayId),
      ],
    );
  }

  Future<void> reopenDay({
    required int dayId,
    String? reopenedBy,
  }) async {
    // Single-open guard (same as openDay): reopening is an UPDATE, so it
    // bypasses the INSERT-only trigger trg_prevent_multi_open — the V45
    // partial unique index idx_days_one_open stays as the SQL-level backstop.
    final openDays = await getOpenDays();
    final otherOpen = openDays.where((d) => (d['id'] as int) != dayId);
    if (otherOpen.isNotEmpty) {
      throw Exception('يوجد يوم مفتوح بالفعل — أغلقه أولاً قبل إعادة فتح يوم آخر');
    }
    await customUpdate(
      'UPDATE days SET is_open = 1, reopened_at = ?, reopened_by = ? WHERE id = ?',
      variables: [
        Variable.withDateTime(DateTime.now()),
        Variable.withString(reopenedBy ?? ''),
        Variable.withInt(dayId),
      ],
    );
  }

  Future<bool> isDayOpen() async {
    final query = select(db.days)..where((t) => t.isOpen.equals(true));
    final result = await query.get();
    return result.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> getAllDays() async {
    final rows = await customSelect(
      'SELECT * FROM days ORDER BY date DESC',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<void> deleteDay(int dayId) async {
    await customUpdate(
      'DELETE FROM days WHERE id = ?',
      variables: [Variable.withInt(dayId)],
    );
  }

  Stream<List<Map<String, Object?>>> watchAllDays() {
    return customSelect(
      'SELECT * FROM days ORDER BY date DESC',
    ).watch().map((rows) => rows.map((r) => r.data).toList());
  }
}
