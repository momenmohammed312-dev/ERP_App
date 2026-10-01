import 'dart:convert';
import 'dart:typed_data';

/// نتيجة قراءة مفصلة: الشبكة + تشخيصات (لا إسقاط صامت — أي فقد يُبلَّغ).
class BiffReadResult {
  final List<List<String>> grid;

  /// عدد سجلات الخلايا المقروءة (LABEL/NUMBER/INTEGER/FORMULA).
  final int cellsRead;

  /// عدد أسطر الشبكة الناتجة (بعد حذف الفارغ).
  int get rowsRead => grid.length;

  /// تحذيرات بأي فقد محتمل (تُعرض في المعاينة).
  final List<String> warnings;

  /// عدد أوراق BOF المكتشفة (أكثر من 1 = ملف مدمج).
  final int sheetCount;

  const BiffReadResult({
    required this.grid,
    required this.cellsRead,
    required this.warnings,
    required this.sheetCount,
  });
}

/// قارئ ملفات الإكسل القديمة التي لا تدعمها حزمة `excel`
/// (تدعم OOXML أي .xlsx فقط).
///
/// يغطي صيغتين تصدّرهما برامج أجهزة البصمة (ZKTeco ونحوها):
/// - ‎.xls بصيغة BIFF2 (Excel 2.1): سجل BOF نوعه 0x0809، وخلايا LABEL
///   نوعها 0x0004 (صف/عمود/3 بايت سمات/طول بايت واحد/نص)، وNUMBER نوعها
///   0x0003 وINTEGER نوعها 0x0002، وFORMULA نوعها 0x0006 (نتيجتها المخزنة).
/// - ‎.csv / .txt بفاصل يُكتشف تلقائياً (فاصلة/منقوطة/تاب) مع دعم الحقول
///   المقتبسة.
///
/// الناتج شبكة نصوص `List<List<String>>` تُمرَّر لخدمة الاستيراد.
class LegacyExcelReader {
  /// يقرأ البايتات حسب الامتداد ويرجع شبكة الصفوف (صفوف فارغة تُحذف).
  static List<List<String>> readGrid(Uint8List bytes, String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (ext == 'csv' || ext == 'txt') return readCsv(bytes);
    // أي شيء آخر (xls) يُعامل كـ BIFF2 — صيغة تصدير أجهزة البصمة.
    return readBiff2(bytes);
  }

  /// قراءة مفصلة مع تشخيصات (تُستخدم في المعاينة).
  static BiffReadResult readGridDetailed(Uint8List bytes, String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (ext == 'csv' || ext == 'txt') {
      final grid = readCsv(bytes);
      return BiffReadResult(
        grid: grid,
        cellsRead: grid.fold(0, (sum, r) => sum + r.length),
        warnings: const [],
        sheetCount: 1,
      );
    }
    return readBiff2Detailed(bytes);
  }

  /// يقرأ ملف .xls بصيغة BIFF2 ويرجع الخلايا النصية كشبكة.
  static List<List<String>> readBiff2(Uint8List data) =>
      readBiff2Detailed(data).grid;

  /// تحويل رقم إكسل المسلسل (أيام منذ 1899-12-30) إلى نص تاريخ مفهوم
  /// لمحلل التواريخ (`yyyy-MM-dd HH:mm:ss`).
  /// الحساب بـUTC عمداً لتفادي انزياح التوقيت الصيفي بين الأجهزة.
  static String excelSerialToString(double serial) {
    if (serial < 20000 || serial > 80000) return _formatNumber(serial);
    final base = DateTime.utc(1899, 12, 30);
    final dt = base.add(Duration(
      days: serial.floor(),
      milliseconds: ((serial - serial.floor()) * 86400000).round(),
    ));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  /// يقرأ ملف .xls بصيغة BIFF2 مع تشخيصات كاملة — أي فقد يُسجَّل في
  /// `warnings` بدل الإسقاط الصامت.
  static BiffReadResult readBiff2Detailed(Uint8List data) {
    final cells = <int, Map<int, String>>{};
    final warnings = <String>[];
    final otherTypes = <int, int>{};
    var maxRow = -1;
    var maxCol = -1;
    var offset = 0;
    var sheetCount = 0;
    var cellsRead = 0;
    var overwritten = 0;
    var stoppedAt = -1;
    var shortCells = 0;

    while (offset + 4 <= data.length) {
      final type = data[offset] | (data[offset + 1] << 8);
      final length = data[offset + 2] | (data[offset + 3] << 8);
      if (length < 0 || length > 32767) {
        stoppedAt = offset;
        break;
      }
      if (offset + 4 + length > data.length) {
        stoppedAt = offset;
        break;
      }

      void putCell(int row, int col, String value) {
        final rowMap = cells.putIfAbsent(row, () => {});
        if (rowMap.containsKey(col)) overwritten++;
        rowMap[col] = value;
        cellsRead++;
        if (row > maxRow) maxRow = row;
        if (col > maxCol) maxCol = col;
      }

      if (type == 0x0809) {
        sheetCount++;
      } else if (type == 0x0004 && length >= 8) {
        // LABEL: صف(2) عمود(2) سمات(3) طول(1) نص
        final row = data[offset + 4] | (data[offset + 5] << 8);
        final col = data[offset + 6] | (data[offset + 7] << 8);
        final strLen = data[offset + 11];
        final end = (offset + 12 + strLen).clamp(0, data.length);
        final raw = data.sublist(offset + 12, end);
        putCell(row, col, _decodeBytes(raw));
      } else if (type == 0x0003 && length >= 15) {
        // NUMBER: صف(2) عمود(2) سمات(3) double-le
        final row = data[offset + 4] | (data[offset + 5] << 8);
        final col = data[offset + 6] | (data[offset + 7] << 8);
        final value = ByteData.sublistView(
          data,
          offset + 11,
          offset + 19,
        ).getFloat64(0, Endian.little);
        putCell(row, col, _formatNumber(value));
      } else if (type == 0x0002 && length >= 9) {        // INTEGER: صف(2) عمود(2) سمات(3) uint16-le
        final row = data[offset + 4] | (data[offset + 5] << 8);
        final col = data[offset + 6] | (data[offset + 7] << 8);
        final value = data[offset + 11] | (data[offset + 12] << 8);
        putCell(row, col, '$value');
      } else if (type == 0x0006 && length >= 19) {
        // FORMULA (BIFF2): صف(2) عمود(2) سمات(3) نتيجة مخزنة(8) ...
        // النتيجة المخزنة double (قد تكون تاريخاً مسلسلاً) — النصوص
        // (STRING) تُتجاهل مع تحذير لأنها تحتاج السجل اللاحق.
        final row = data[offset + 4] | (data[offset + 5] << 8);
        final col = data[offset + 6] | (data[offset + 7] << 8);
        final flag = data[offset + 11] | (data[offset + 12] << 8);
        if (flag == 0xFFFF) {
          otherTypes[type] = (otherTypes[type] ?? 0) + 1;
        } else {
          final value = ByteData.sublistView(
            data,
            offset + 11,
            offset + 19,
          ).getFloat64(0, Endian.little);
          putCell(row, col, excelSerialToString(value));
        }
      } else {
        otherTypes[type] = (otherTypes[type] ?? 0) + 1;
        // سجل خلية ناقص الطول (تالف جزئياً) — يُحتسب للتحذير
        // (الـFORMULA القصيرة تُغطيها رسالة المعادلات).
        if (type == 0x0002 || type == 0x0003 || type == 0x0004) {
          shortCells++;
        }
      }

      offset += 4 + length;
    }

    if (stoppedAt >= 0) {
      warnings.add(
        'توقفت القراءة عند بايت $stoppedAt من ${data.length} (سجل غير صالح) — '
        'صفوف بعده قد تكون ناقصة. قارن عدد الصفوف بعدد صفوف الملف في الإكسل.',
      );
    }
    if (sheetCount > 1) {
      warnings.add(
        'الملف يحتوي $sheetCount أوراق مدمجة — دُمجت معاً (القيم المتكررة أُخذت الأخيرة).',
      );
    }
    if (overwritten > 0) {
      warnings.add(
        'عدد $overwritten خلية مكررة (نفس الصف/العمود) — احتُفظ بالقيمة الأخيرة.',
      );
    }
    final formulaSkipped = otherTypes[0x0006] ?? 0;
    if (formulaSkipped > 0) {
      warnings.add(
        'عدد $formulaSkipped خلية معادلة نصية (FORMULA) لا تُقرأ — تحقق منها في الإكسل.',
      );
    }
    if (shortCells > 0) {
      warnings.add(
        'عدد $shortCells خلية ناقصة/تالفة تم تجاوزها — قارن عدد الصفوف بعدد الإكسل.',
      );
    }

    if (maxRow < 0) {
      return BiffReadResult(
        grid: const [],
        cellsRead: 0,
        warnings: warnings,
        sheetCount: sheetCount,
      );
    }
    final grid = <List<String>>[];
    var blankRows = 0;
    for (var r = 0; r <= maxRow; r++) {
      final rowMap = cells[r] ?? const {};
      final row = List<String>.generate(
        maxCol + 1,
        (c) => (rowMap[c] ?? '').trim(),
      );
      // إسقاط الخلايا الفارغة من نهاية الصف
      while (row.isNotEmpty && row.last.isEmpty) {
        row.removeLast();
      }
      if (row.any((c) => c.isNotEmpty)) {
        grid.add(row);
      } else {
        blankRows++;
      }
    }
    if (blankRows > 0) {
      warnings.add('عدد $blankRows صف فارغ تماماً تم تجاوزه.');
    }
    return BiffReadResult(
      grid: grid,
      cellsRead: cellsRead,
      warnings: warnings,
      sheetCount: sheetCount,
    );
  }

  /// يقرأ CSV/TXT مع اكتشاف الفاصل ودعم الاقتباس.
  static List<List<String>> readCsv(Uint8List bytes) {
    final text = _decodeBytes(bytes);
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final sample = lines.where((l) => l.trim().isNotEmpty).take(5).toList();
    var delimiter = ',';
    var best = -1;
    for (final candidate in [',', ';', '\t']) {
      var score = 0;
      for (final line in sample) {
        score += _splitCsvLine(line, candidate).length;
      }
      if (score > best) {
        best = score;
        delimiter = candidate;
      }
    }
    final grid = <List<String>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final row = _splitCsvLine(line, delimiter)
          .map((c) => c.trim())
          .toList();
      while (row.isNotEmpty && row.last.isEmpty) {
        row.removeLast();
      }
      if (row.any((c) => c.isNotEmpty)) grid.add(row);
    }
    return grid;
  }

  /// فك ترميز بايتات الخلية: UTF-8 أولاً (مع BOM)، ثم Latin-1 الذي يحفظ
  /// بايتات Windows-1256 واحداً لواحد (الأسماء العربية قد تظهر مشوهة في
  /// العرض لكنها لا تُستخدم في المطابقة — المطابقة برقم البصمة).
  static String _decodeBytes(List<int> raw) {
    var bytes = raw;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String _formatNumber(double value) {
    if (value == value.truncateToDouble()) return '${value.toInt()}';
    var s = value.toStringAsFixed(6);
    while (s.contains('.') && (s.endsWith('0'))) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  static List<String> _splitCsvLine(String line, String delimiter) {
    final fields = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        fields.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    fields.add(current.toString());
    return fields;
  }
}
