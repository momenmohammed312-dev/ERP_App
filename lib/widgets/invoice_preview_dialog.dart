import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;

/// Invoice Preview Dialog Widget
/// Shows PDF preview with print/share options
class InvoicePreviewDialog extends StatelessWidget {
  final Invoice invoice;
  final List<InvoiceItem> items;
  final String customerName;
  final String? customerId;

  const InvoicePreviewDialog({
    super.key,
    required this.invoice,
    required this.items,
    this.customerName = 'عميل',
    this.customerId,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header with Close Button
            AppBar(
              title: Text(
                'عرض الفاتورة ${displayInvoiceNumber(invoice.invoiceNumber, invoice.id) ?? ''}',
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                // Export PDF Button
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: 'تصدير PDF',
                  onPressed: () async {
                    try {
                      // Create InvoiceData for UnifiedPrintService
                      final invoiceItems = items
                          .map(
                            (item) => ups.InvoiceItem(
                              id: item.id,
                              invoiceId: item.invoiceId,
                              description: 'منتج #${item.productId}',
                              unit: 'قطعة',
                              quantity: item.quantity,
                              unitPrice: item.price,
                              totalPrice: item.quantity * item.price,
                            ),
                          )
                          .toList();

                      final storeInfo = ups.StoreInfo(
                        storeName: 'المحل التجاري',
                        phone: '01234567890',
                        zipCode: '12345',
                        state: 'القاهرة',
                      );

                      // Get customer's actual previous balance
                      double previousBalance = 0.0;
                      if (customerId != null && customerId != 'cash_customer') {
                        // Note: This would need database access - for now using 0.0
                        // In a real implementation, you'd pass the database instance
                        previousBalance = 0.0;
                      }

                      final invoiceModel = ups.Invoice(
                        id: invoice.id,
                        invoiceNumber:
                            invoice.invoiceNumber ?? formatInvoiceNumber(invoice.id),
                        customerName: customerName,
                        customerPhone: 'N/A',
                        customerZipCode: '',
                        customerState: '',
                        invoiceDate: invoice.date,
                        subtotal: items.fold(
                          0.0,
                          (sum, item) => sum + (item.quantity * item.price),
                        ),
                        isCreditAccount: invoice.paymentMethod == 'credit',
                        previousBalance: previousBalance,
                        totalAmount: items.fold(
                          0.0,
                          (sum, item) => sum + (item.quantity * item.price),
                        ),
                      );

                      final invoiceData = ups.InvoiceData(
                        invoice: invoiceModel,
                        items: invoiceItems,
                        storeInfo: storeInfo,
                      );

                      final pdfFile =
                          await ups.UnifiedPrintService.exportToPDFFile(
                            documentType: ups.DocumentType.salesInvoice,
                            data: invoiceData,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم تصدير الفاتورة بنجاح'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('خطأ في التصدير: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            // The PDF Viewer
            Expanded(
              child: PdfPreview(
                build: (format) async {
                  // Create InvoiceData for UnifiedPrintService
                  final invoiceItems = items
                      .map(
                        (item) => ups.InvoiceItem(
                          id: item.id,
                          invoiceId: item.invoiceId,
                          description: 'منتج #${item.productId}',
                          unit: 'قطعة',
                          quantity: item.quantity,
                          unitPrice: item.price,
                          totalPrice: item.quantity * item.price,
                        ),
                      )
                      .toList();

                  final storeInfo = ups.StoreInfo(
                    storeName: 'المحل التجاري',
                    phone: '01234567890',
                    zipCode: '12345',
                    state: 'القاهرة',
                  );

                  // Get customer's actual previous balance
                  double previousBalance = 0.0;
                  if (customerId != null && customerId != 'cash_customer') {
                    // Note: This would need database access - for now using 0.0
                    // In a real implementation, you'd pass the database instance
                    previousBalance = 0.0;
                  }

                  final invoiceModel = ups.Invoice(
                    id: invoice.id,
                    invoiceNumber: invoice.invoiceNumber ?? formatInvoiceNumber(invoice.id),
                    customerName: customerName,
                    customerPhone: 'N/A',
                    customerZipCode: '',
                    customerState: '',
                    invoiceDate: invoice.date,
                    subtotal: items.fold(
                      0.0,
                      (sum, item) => sum + (item.quantity * item.price),
                    ),
                    isCreditAccount: invoice.paymentMethod == 'credit',
                    previousBalance: previousBalance,
                    totalAmount: items.fold(
                      0.0,
                      (sum, item) => sum + (item.quantity * item.price),
                    ),
                  );

                  final invoiceData = ups.InvoiceData(
                    invoice: invoiceModel,
                    items: invoiceItems,
                    storeInfo: storeInfo,
                  );

                  final pdf =
                      await ups.UnifiedPrintService.generateUnifiedDocument(
                        documentType: ups.DocumentType.salesInvoice,
                        data: invoiceData,
                      );
                  return pdf.save();
                },
                allowPrinting: true,
                allowSharing: true,
                initialPageFormat: PdfPageFormat.a4,
                pdfFileName:
                    'invoice_${invoice.invoiceNumber ?? invoice.id}.pdf',
                dynamicLayout:
                    false, // Disable dynamic layout to ensure exact match
                // Custom actions
                actions: [
                  PdfPreviewAction(
                    icon: const Icon(Icons.share),
                    onPressed: (context, save, layout) async {
                      await save(layout);
                    },
                  ),
                ],
              ),
            ),
            // Bottom Action Buttons
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        // Create InvoiceData for UnifiedPrintService
                        final invoiceItems = items
                            .map(
                              (item) => ups.InvoiceItem(
                                id: item.id,
                                invoiceId: item.invoiceId,
                                description: 'منتج #${item.productId}',
                                unit: 'قطعة',
                                quantity: item.quantity,
                                unitPrice: item.price,
                                totalPrice: item.quantity * item.price,
                              ),
                            )
                            .toList();

                        final storeInfo = ups.StoreInfo(
                          storeName: 'المحل التجاري',
                          phone: '01234567890',
                          zipCode: '12345',
                          state: 'القاهرة',
                        );

                        // Get customer's actual previous balance
                        double previousBalance = 0.0;
                        if (customerId != null &&
                            customerId != 'cash_customer') {
                          // Note: This would need database access - for now using 0.0
                          // In a real implementation, you'd pass the database instance
                          previousBalance = 0.0;
                        }

                        final invoiceModel = ups.Invoice(
                          id: invoice.id,
                          invoiceNumber:
                              invoice.invoiceNumber ?? formatInvoiceNumber(invoice.id),
                          customerName: customerName,
                          customerPhone: 'N/A',
                          customerZipCode: '',
                          customerState: '',
                          invoiceDate: invoice.date,
                          subtotal: items.fold(
                            0.0,
                            (sum, item) => sum + (item.quantity * item.price),
                          ),
                          isCreditAccount: invoice.paymentMethod == 'credit',
                          previousBalance: previousBalance,
                          totalAmount: items.fold(
                            0.0,
                            (sum, item) => sum + (item.quantity * item.price),
                          ),
                        );

                        final invoiceData = ups.InvoiceData(
                          invoice: invoiceModel,
                          items: invoiceItems,
                          storeInfo: storeInfo,
                        );

                        final pdfFile =
                            await ups.UnifiedPrintService.exportToPDFFile(
                              documentType: ups.DocumentType.salesInvoice,
                              data: invoiceData,
                            );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم تصدير الفاتورة: ${pdfFile.path}',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ في التصدير: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('تصدير PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        // Show loading indicator
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('جاري تحميل الفاتورة للطباعة...'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }

                        // Create InvoiceData for UnifiedPrintService
                        final invoiceItems = items
                            .map(
                              (item) => ups.InvoiceItem(
                                id: item.id,
                                invoiceId: item.invoiceId,
                                description: 'منتج #${item.productId}',
                                unit: 'قطعة',
                                quantity: item.quantity,
                                unitPrice: item.price,
                                totalPrice: item.quantity * item.price,
                              ),
                            )
                            .toList();

                        final storeInfo = ups.StoreInfo(
                          storeName: 'المحل التجاري',
                          phone: '01234567890',
                          zipCode: '12345',
                          state: 'القاهرة',
                        );

                        // Get customer's actual previous balance
                        double previousBalance = 0.0;
                        if (customerId != null &&
                            customerId != 'cash_customer') {
                          // Note: This would need database access - for now using 0.0
                          // In a real implementation, you'd pass the database instance
                          previousBalance = 0.0;
                        }

                        final invoiceModel = ups.Invoice(
                          id: invoice.id,
                          invoiceNumber:
                              invoice.invoiceNumber ?? formatInvoiceNumber(invoice.id),
                          customerName: customerName,
                          customerPhone: 'N/A',
                          customerZipCode: '',
                          customerState: '',
                          invoiceDate: invoice.date,
                          subtotal: items.fold(
                            0.0,
                            (sum, item) => sum + (item.quantity * item.price),
                          ),
                          isCreditAccount: invoice.paymentMethod == 'credit',
                          previousBalance: previousBalance,
                          totalAmount: items.fold(
                            0.0,
                            (sum, item) => sum + (item.quantity * item.price),
                          ),
                        );

                        final invoiceData = ups.InvoiceData(
                          invoice: invoiceModel,
                          items: invoiceItems,
                          storeInfo: storeInfo,
                        );

                        // Print using new SOP 4.0 format
                        await ups.UnifiedPrintService.printToThermalPrinter(
                          documentType: ups.DocumentType.salesInvoice,
                          data: invoiceData,
                        );

                        // Show success message
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم فتح نافذة الطباعة'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ في الطباعة: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to show invoice preview
void showInvoicePreview(
  BuildContext context,
  Invoice invoice,
  List<InvoiceItem> items, {
  String customerName = 'عميل',
  String? customerId,
}) {
  showDialog(
    context: context,
    builder: (context) => InvoicePreviewDialog(
      invoice: invoice,
      items: items,
      customerName: customerName,
      customerId: customerId,
    ),
  );
}
