// windows_printer_paper_size.dart
// يقرأ مقاس الورق الحالي (المحدد في درايفر الويندوز) للبرينتر الافتراضي،
// عشان نطبع الملصقات بنفس المقاس اللي متظبط في ويندوز من غير ما نعدل المقاس
// في مكانين. يعمل على Windows بس — على أي نظام تاني بيرجع null.
import 'dart:io';

class WindowsPrinterPaperSize {
  static const String _script = r'''
Add-Type -AssemblyName System.Drawing
$ps = New-Object System.Drawing.Printing.PrinterSettings
"$($ps.PrinterName)|$($ps.DefaultPageSettings.PaperSize.Width)|$($ps.DefaultPageSettings.PaperSize.Height)"
''';

  /// يعرض اسم البرينتر + عرض/ارتفاع الورق بالمللي.
  /// بيلفّأ null لو مش Windows أو فشل القراءة.
  static Future<({String printerName, double widthMm, double heightMm})?>
      detect() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', _script],
      );
      if (result.exitCode != 0) return null;

      final lines = (result.stdout as String).trim().split('\n');
      for (final line in lines) {
        final parts = line.trim().split('|');
        if (parts.length != 3) continue;
        final w = int.tryParse(parts[1]);
        final h = int.tryParse(parts[2]);
        if (w != null && h != null && w > 0 && h > 0) {
          return (
            printerName: parts[0],
            // PaperSize.Width/Height بوحدة 1/100 بوصة → مللي = *0.254
            widthMm: w * 0.254,
            heightMm: h * 0.254,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
