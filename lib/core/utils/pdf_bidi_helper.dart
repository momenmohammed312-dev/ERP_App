import 'package:bidi/bidi.dart' as bidi;

/// Shared helper for Arabic text in PDF generation.
///
/// The `pdf` Dart package renders text in logical (memory) order.
/// Arabic/RTL languages need visual order for correct display.
/// This helper uses the Unicode Bidi Algorithm (UAX #9) to reorder text.
class PdfBidiHelper {
  /// Convert a logical Arabic string to visual representation for PDF.
  ///
  /// Non-Arabic strings (pure Latin, numbers) pass through unchanged.
  static String reorder(String logical) {
    if (logical.isEmpty) return logical;
    final result = bidi.logicalToVisual(logical);
    return String.fromCharCodes(result);
  }
}
