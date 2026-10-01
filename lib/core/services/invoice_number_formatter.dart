/// Single source for every invoice display number (Bug 3).
///
/// Customer sales invoices derive their display number directly from the
/// `Invoices.id` autoincrement column: unique, restart-safe and
/// concurrency-safe with no extra table. Gaps are expected and accepted
/// (drafts, voided and hard-deleted rows consume ids) — the client
/// confirmed ID-derived display with gaps over a separate counter.
///
/// Supplier purchase invoices use TEXT ids, so they get their own
/// zero-padded sequence with a `PUR-` prefix (never the customer values).
///
/// `1` → `000001`. Wider than 6 digits keeps full width (never truncate).
String formatInvoiceNumber(int id) => id.toString().padLeft(6, '0');

/// `123` → `PUR-000123`.
String formatPurchaseNumber(int id) => 'PUR-${id.toString().padLeft(6, '0')}';

/// True only for canonical 6-digit customer numbers.
bool isCanonicalInvoiceNumber(String? s) =>
    s != null && RegExp(r'^\d{6}$').hasMatch(s);

/// Parses the numeric tail of a `PUR-000123`-style supplier number.
int? parsePurchaseNumber(String? s) {
  if (s == null) return null;
  final m = RegExp(r'PUR-(\d+)').firstMatch(s);
  return m == null ? null : int.tryParse(m.group(1) ?? '');
}

/// Display helper (display-only audit): stored value verbatim when present,
/// else id-derived `000001` format, else null so the caller keeps its own
/// placeholder. Never rewrites stored data; never touches receiptNumber.
String? displayInvoiceNumber(Object? storedNumber, Object? id) {
  final s = storedNumber?.toString();
  if (s != null && s.isNotEmpty) return s;
  final n = id is int ? id : int.tryParse(id?.toString() ?? '');
  return n == null ? null : formatInvoiceNumber(n);
}
