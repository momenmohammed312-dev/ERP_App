import "dart:typed_data";
import "dart:convert";
import "package:crypto/crypto.dart";

/// تحويل آمن لأي نوع إلى double
double? parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// استخراج الرقم من نهاية String (مثل "PUR-1234" → 1234)
int? extractNum(String? s) {
  if (s == null) return null;
  final m = RegExp(r"(\d+)$").firstMatch(s);
  return m != null ? int.tryParse(m.group(1)!) : null;
}

/// الوصول لعمود بـ camelCase أو snake_case
dynamic getCol(Map row, String camel, String snake) {
  if (row.containsKey(camel)) return row[camel];
  if (row.containsKey(snake)) return row[snake];
  return null;
}

/// تحويل آمن إلى String
String safeStr(dynamic v) => v == null ? "" : v.toString();

/// اشتقاق مفتاح AES من passphrase (دائماً 16 أو 32 بايت)
Uint8List deriveAesKey(String passphrase, {int bytes = 32}) {
  final digest = sha256.convert(utf8.encode(passphrase)).bytes;
  return Uint8List.fromList(digest.sublist(0, bytes));
}

/// التحقق من صحة طول مفتاح AES
void ensureKeyLen(Uint8List key) {
  if (![16, 24, 32].contains(key.length)) {
    throw ArgumentError("Key must be 128/192/256 bits. Got ${key.length * 8}");
  }
}

/// تحويل DateTime آمن من SQLite (int/String/DateTime)
/// يرفض تواريخ قبل سنة 2000 (مثل 1970-01-01) لأنها بيانات غير صالحة
DateTime parseDate(dynamic raw, {DateTime? fallback}) {
  final defaultDate = fallback ?? DateTime.now();
  if (raw is int) {
    if (raw == 0) return defaultDate;
    final dt = DateTime.fromMicrosecondsSinceEpoch(raw);
    if (dt.year < 2000) return defaultDate;
    return dt;
  }
  if (raw is double) {
    if (raw == 0) return defaultDate;
    final dt = DateTime.fromMicrosecondsSinceEpoch(raw.toInt());
    if (dt.year < 2000) return defaultDate;
    return dt;
  }
  if (raw is String) {
    if (raw.isEmpty) return defaultDate;
    try {
      final dt = DateTime.parse(raw);
      if (dt.year < 2000) return defaultDate;
      return dt;
    } catch (_) {
      return defaultDate;
    }
  }
  if (raw is DateTime) {
    if (raw.year < 2000) return defaultDate;
    return raw;
  }
  return defaultDate;
}
