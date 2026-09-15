import 'dart:io';
import 'package:excel/excel.dart';
void main() {
  for (final path in [r'E:\Temp\opencode\attendance_import_template.xlsx', r'G:\flutter\Downloads\attendance_import_اضافي_اذن_بس.xlsx', r'G:\flutter\Downloads\attendance_import_clean.xlsx', r'G:\flutter\Downloads\attendance_import_filled (1).xlsx']) {
    print('--- TEST $path');
    final bytes = File(path).readAsBytesSync();
    try {
      final excel = Excel.decodeBytes(bytes);
      print('tables: ${excel.tables.keys.toList()}');
      for (final e in excel.tables.entries) {
        print('sheet ${e.key} rows ${e.value.rows.length} maxCols ${e.value.maxColumns}');
        for (int i=0;i<2 && i< e.value.rows.length;i++) {
          print(e.value.rows[i].map((c)=> c?.value?.toString()??'null').toList());
        }
      }
    } catch (e,s) {
      print('ERROR $e');
      print(s);
    }
  }
}
