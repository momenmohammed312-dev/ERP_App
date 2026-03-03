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
DateTime parseDate(dynamic raw, {DateTime? fallback}) {
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is String) return DateTime.parse(raw);
  if (raw is DateTime) return raw;
  return fallback ?? DateTime.now();
}
