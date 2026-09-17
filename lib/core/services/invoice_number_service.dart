import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Global invoice-numbering contract (schema v70+).
///
/// One single source of truth for every invoice number in every flavor:
///
/// * Canonical numbers are exactly 6 zero-padded digits (`000001` …).
/// * They come from the `invoice_number_sequence` table (single row, id = 1),
///   allocated with [nextInvoiceNumber] **inside** the invoice-create
///   transaction — never pre-generated, never passed in from UI.
/// * Legacy rows (`INV<millis>`, `DRAFT_…`, `SALE-…`, …) are left untouched and
///   coexist: the partial unique index only covers canonical values, and fresh
///   numbers always continue after `max(canonical) + 1`.
/// * Drafts (`status = 'draft'`) persist with `invoice_number = NULL` until
///   they are posted through `InvoiceService.createInvoice`, which assigns the
///   canonical number. No `DRAFT_…` / timestamp numbers are ever persisted.
/// * Edit and void never regenerate or recycle the number.
///
/// This generator reads no flavor flag: numbering is flavor-independent.
class InvoiceNumberService {
  /// Matches exactly 6 ASCII digits, e.g. `000001`. Nothing else is canonical.
  static final RegExp _canonicalPattern = RegExp(r'^\d{6}$');

  /// `1` → `000001`. Values above 999999 keep their full width (`1000000`)
  /// so uniqueness is never sacrificed for padding.
  static String format(int n) => n.toString().padLeft(6, '0');

  /// True only for canonical 6-digit numbers.
  static bool isCanonical(String? s) => s != null && _canonicalPattern.hasMatch(s);

  /// Ledger description for the sale row of invoice [n]. New invoices only —
  /// historical descriptions are never rewritten.
  static String saleDescription(String n) => 'فاتورة $n';

  /// Ledger description for the payment row of invoice [n].
  static String paymentDescription(String n) => 'سداد $n';

  /// Ledger description for the supplier-commission row of invoice [n].
  static String commissionDescription(String n) => 'عمولة $n';

  /// Allocates the next canonical invoice number.
  ///
  /// MUST be called INSIDE the invoice-create transaction: the read-take-
  /// increment-update runs in the same write transaction as the invoice row,
  /// and SQLite serializes writers, so concurrent creates can never receive
  /// the same number (no separate lock needed).
  ///
  /// On a missing/stale seed (row id = 1 absent — e.g. a database that
  /// skipped the v70 migration — or behind `max(canonical) + 1` because a
  /// canonical row arrived out-of-band via direct DAO insert/restore),
  /// initializes/heals defensively from `max(canonical) + 1` over invoices,
  /// else `1`. The heal is `max()`, never a rewrite: existing numbers are
  /// untouched, the sequence only ever moves forward.
  Future<String> nextInvoiceNumber(AppDatabase db) async {
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS invoice_number_sequence '
      '(id INTEGER PRIMARY KEY CHECK (id = 1), next_value INTEGER NOT NULL)',
    );

    final rows = await db
        .customSelect(
          'SELECT next_value FROM invoice_number_sequence WHERE id = 1',
        )
        .get();

    if (rows.isEmpty) {
      final first = await _maxCanonicalPlusOne(db);
      await db.customStatement(
        'INSERT INTO invoice_number_sequence (id, next_value) VALUES (1, ?)',
        [first + 1],
      );
      return format(first);
    }

    final raw = rows.first.data['next_value'];
    final current = raw is int ? raw : (raw is num ? raw.toInt() : 0);
    // Self-healing: the sequence only ever moves forward. A corrupt/zero
    // seed OR a seed behind max(canonical)+1 (canonical rows inserted
    // out-of-band, e.g. direct DAO/restore inserts that bypass the service)
    // heals from max(canonical) + 1 instead of re-issuing a live number.
    final floor = await _maxCanonicalPlusOne(db);
    final take = current < floor ? floor : current;
    await db.customStatement(
      'UPDATE invoice_number_sequence SET next_value = ? WHERE id = 1',
      [take + 1],
    );
    return format(take);
  }

  /// Advances the sequence past a preserved canonical number (used by the
  /// import/sync/restore path) so the next generated number cannot collide
  /// with it. No-op for legacy ids. Must be called inside the same txn.
  Future<void> bumpPastCanonical(AppDatabase db, String preserved) async {
    if (!isCanonical(preserved)) return;
    final n = int.parse(preserved);
    await db.customStatement(
      'UPDATE invoice_number_sequence SET next_value = ? '
      'WHERE id = 1 AND next_value <= ?',
      [n + 1, n],
    );
  }

  /// `max(canonical numeric invoice) + 1`, or `1` when no canonical row exists.
  /// Canonical = `GLOB '[0-9][0-9][0-9][0-9][0-9][0-9]'` — legacy timestamp /
  /// `DRAFT_` / prefixed rows never influence the sequence.
  Future<int> _maxCanonicalPlusOne(AppDatabase db) async {
    final row = await db
        .customSelect(
          "SELECT MAX(CAST(invoice_number AS INTEGER)) AS max_n FROM invoices "
          "WHERE invoice_number GLOB '[0-9][0-9][0-9][0-9][0-9][0-9]'",
        )
        .getSingle();
    final v = row.data['max_n'];
    final maxN = v is int ? v : (v is num ? v.toInt() : 0);
    return maxN + 1;
  }
}
