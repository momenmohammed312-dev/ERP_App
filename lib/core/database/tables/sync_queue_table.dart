import 'package:drift/drift.dart';

/// Outbox-style queue for multi-device sync.
/// Local writes are queued here first, then a background SyncService pushes
/// them to Supabase. Rows stay until they are successfully synced.
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  // NOTE: Drift reserves `tableName` on Table itself, so the column is `tableRef`.
  TextColumn get tableRef => text()(); // 'products' | 'customers' | 'invoices' | 'invoice_items' | 'stock_movements'
  TextColumn get recordSyncId => text()(); // the syncId of the affected record
  TextColumn get operation => text()(); // 'insert' | 'update' | 'stock_delta'
  TextColumn get payloadJson => text()(); // JSON-encoded snapshot to send
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  // Device/location marker set at enqueue-time, used for per-device filtering.
  TextColumn get deviceName => text().nullable()();
}
