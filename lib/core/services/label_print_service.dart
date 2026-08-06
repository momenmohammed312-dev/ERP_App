import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class LabelPrintService {
  static Future<void> printProductLabels({
    required List<Product> products,
    required Map<int, int> copiesPerProduct,
    String? companyName,
    bool showPrice = true,
    Map<int, String>? barcodeData,
    double widthMm = 50,
    double heightMm = 30,
  }) async {
    final pdf = pw.Document();

    final labelWidth = PdfPageFormat.mm * widthMm;
    final labelHeight = PdfPageFormat.mm * heightMm;

    final barcodes = <String>[];
    for (final product in products) {
      final copies = copiesPerProduct[product.id] ?? 1;
      final barcode = barcodeData?[product.id]?.isNotEmpty == true
          ? barcodeData![product.id]!
          : product.barcode ?? product.id.toString();
      for (int i = 0; i < copies; i++) {
        barcodes.add(barcode);
      }
    }

    const int labelsPerPage = 1;
    for (int i = 0; i < barcodes.length; i += labelsPerPage) {
      final pageBarcodes = barcodes.skip(i).take(labelsPerPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(labelWidth, labelHeight),
          margin: const pw.EdgeInsets.all(2),
          build: (pw.Context context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (companyName != null && companyName.isNotEmpty)
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: pageBarcodes.first,
                  width: labelWidth - 10,
                  height: labelHeight - 20,
                  drawText: true,
                  textStyle: const pw.TextStyle(fontSize: 6),
                ),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'labels_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
