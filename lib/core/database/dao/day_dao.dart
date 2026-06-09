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

  Future<Map<String, Object?>?> getOrCreateTodayDay({
    double? openingBalance,
    String? openedBy,
  }) async {
    final isOpen = await isDayOpen();
    if (isOpen) {
      throw Exception('يوجد يوم مفتوح بالفعل');
    }

    final existing = await getTodayDay();
    if (existing != null) return existing;

    await customInsert(
      'INSERT INTO days (date, is_open, opening_balance, created_at, opened_by) VALUES (?, ?, ?, ?, ?)',
      variables: [
        Variable.withDateTime(DateTime.now()),
        Variable.withBool(true),
        Variable.withReal(openingBalance ?? 0.0),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(openedBy ?? ''),
      ],
    );

    final created = await customSelect(
      'SELECT * FROM days WHERE id = last_insert_rowid() LIMIT 1',
    ).getSingle();

    return created.data;
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
