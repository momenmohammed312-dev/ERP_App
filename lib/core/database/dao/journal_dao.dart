import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/journal_entries_table.dart';
import '../tables/journal_lines_table.dart';

part 'journal_dao.g.dart';

@DriftAccessor(tables: [JournalEntries, JournalLines])
class JournalDao extends DatabaseAccessor<AppDatabase> with _$JournalDaoMixin {
  JournalDao(super.db);

  /// Inserts a balanced journal entry atomically.
  /// Enforces: sum(debit) == sum(credit) within 0.001 tolerance.
  /// Idempotency: if postingKey already exists, returns existing id (no duplicate).
  Future<String> insertBalancedEntry({
    required String postingKey,
    required DateTime date,
    required String description,
    required String sourceType,
    required String sourceId,
    required List<JournalLinesCompanion> lines,
    String? createdBy,
  }) async {
    final totalDebit = lines.fold<double>(0.0, (s, l) => s + (l.debit.present ? l.debit.value : 0.0));
    final totalCredit = lines.fold<double>(0.0, (s, l) => s + (l.credit.present ? l.credit.value : 0.0));
    if ((totalDebit - totalCredit).abs() > 0.001) {
      throw Exception('Unbalanced journal entry: debit=$totalDebit credit=$totalCredit (source: $sourceType/$sourceId postingKey:$postingKey)');
    }

    // Idempotency check inside same transaction scope (caller should already be inside transaction,
    // but we also guard here for standalone calls).
    final existing = await (select(journalEntries)..where((e) => e.postingKey.equals(postingKey))).getSingleOrNull();
    if (existing != null) return existing.id;

    final id = const Uuid().v4();
    await into(journalEntries).insert(JournalEntriesCompanion.insert(
      id: id,
      date: date,
      description: description,
      sourceType: sourceType,
      sourceId: sourceId,
      postingKey: postingKey,
      createdBy: Value(createdBy),
    ));

    for (final line in lines) {
      final lineId = line.id.present ? line.id.value : const Uuid().v4();
      await into(journalLines).insert(line.copyWith(
        id: Value(lineId),
        journalEntryId: Value(id),
      ));
    }
    return id;
  }

  Future<JournalEntry?> getByPostingKey(String postingKey) =>
      (select(journalEntries)..where((e) => e.postingKey.equals(postingKey))).getSingleOrNull();

  Future<JournalEntry?> getById(String id) =>
      (select(journalEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<List<JournalEntry>> getEntriesByDateRange(DateTime from, DateTime to) =>
      (select(journalEntries)..where((e) => e.date.isBetweenValues(from, to))..orderBy([(e) => OrderingTerm.asc(e.date)])).get();

  Future<List<JournalLine>> getLinesForEntry(String entryId) =>
      (select(journalLines)..where((l) => l.journalEntryId.equals(entryId))).get();

  Future<double> getAccountBalance(String accountId) async {
    final rows = await (select(journalLines)..where((l) => l.accountId.equals(accountId))).get();
    double debit = 0, credit = 0;
    for (final r in rows) {
      debit += r.debit;
      credit += r.credit;
    }
    // For asset/expense normal debit: balance = debit - credit; for liability/equity/revenue: credit - debit
    // Caller should know account type; we return raw debit-credit and let service interpret.
    // Simpler: return debit - credit (service will flip if needed).
    return debit - credit;
  }

  Future<List<JournalLine>> getLinesForAccount(String accountId) =>
      (select(journalLines)..where((l) => l.accountId.equals(accountId))).get();

  Stream<List<JournalEntry>> watchAllEntries() =>
      (select(journalEntries)..orderBy([(e) => OrderingTerm.desc(e.date)])).watch();

  /// Posts a reversal entry mirroring original lines (debit<->credit) with reversalOfId set.
  Future<String> reverseEntry({required String originalEntryId, String? createdBy}) async {
    final original = await getById(originalEntryId);
    if (original == null) throw Exception('Original journal entry $originalEntryId not found');
    if (original.status == 'reversed') throw Exception('Entry already reversed');

    final originalLines = await getLinesForEntry(originalEntryId);
    final reversalLines = originalLines
        .map((l) => JournalLinesCompanion.insert(
              id: const Uuid().v4(),
              journalEntryId: '', // filled by insertBalancedEntry
              accountId: l.accountId,
              debit: Value(l.credit),
              credit: Value(l.debit),
              memo: Value(l.memo != null ? 'عكس: ${l.memo}' : 'عكس قيد ${original.postingKey}'),
            ))
        .toList();

    final reversalKey = 'reversal:${original.postingKey}:${const Uuid().v4().substring(0, 8)}';
    final reversalId = await insertBalancedEntry(
      postingKey: reversalKey,
      date: DateTime.now(),
      description: 'عكس قيد ${original.description}',
      sourceType: '${original.sourceType}_reversal',
      sourceId: original.sourceId,
      lines: reversalLines,
      createdBy: createdBy,
    );

    // Mark original as reversed
    await (update(journalEntries)..where((e) => e.id.equals(originalEntryId))).write(
      JournalEntriesCompanion(status: const Value('reversed')),
    );

    // Link reversal
    await (update(journalEntries)..where((e) => e.id.equals(reversalId))).write(
      JournalEntriesCompanion(reversalOfId: Value(originalEntryId)),
    );

    return reversalId;
  }
}
