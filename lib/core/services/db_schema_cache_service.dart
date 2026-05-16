import 'package:drift/drift.dart';

/// Caches PRAGMA table_info results to avoid repeated schema queries per screen.
class DbSchemaCacheService {
  static final Map<String, List<String>> _cache = {};

  static Future<List<String>> getColumns(
    GeneratedDatabase db,
    String tableName,
  ) async {
    if (_cache.containsKey(tableName)) return _cache[tableName]!;

    final rows = await db.customSelect('PRAGMA table_info($tableName)').get();
    final columns = rows
        .map((r) => r.readNullable<String>('name') ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    _cache[tableName] = columns;
    return columns;
  }

  static void clearCache() => _cache.clear();
}
