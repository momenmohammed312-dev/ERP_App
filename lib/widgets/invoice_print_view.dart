import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Simple Store Info Model
class StoreInfo {
  final String storeName;
  final String phone;
  final String zipCode;
  final String state;
  final String? taxNumber;
  final String? logoPath;

  StoreInfo({
    required this.storeName,
    required this.phone,
    required this.zipCode,
    required this.state,
    this.taxNumber,
    this.logoPath,
  });
}

/// Invoice Print View Widget
/// Matches the exact format from the provided image
class InvoicePrintView extends StatelessWidget {
  final InvoiceData invoiceData;

  const InvoicePrintView({super.key, required this.invoiceData});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildCustomerInfo(),
            const SizedBox(height: 20),
            _buildInvoiceTable(),
            const SizedBox(height: 10),
            _buildTotalsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'Developed by MO2',
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'عرض أسعار',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('إسم المحل التجاري: ${invoiceData.storeInfo.storeName}'),
                Text('العنوان: ${invoiceData.storeInfo.state}'),
                Text(
                  'المدينة, الرمز البريدي: ${invoiceData.storeInfo.zipCode}',
                ),
                Text('الدولة: ${invoiceData.storeInfo.phone}'),
                if (invoiceData.storeInfo.taxNumber != null &&
                    invoiceData.storeInfo.taxNumber!.isNotEmpty)
                  Text(
                    'الرقم الضريبي: ${invoiceData.storeInfo.taxNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomerInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المشروع: '),
            Text(
              'رقم الفاتورة: ${invoiceData.invoice.invoiceNumber ?? invoiceData.invoice.id}',
            ),
            Text('التاريخ: ${_formatDate(invoiceData.invoice.date)}'),
            Text('تاريخ البيع: ${_formatDate(invoiceData.invoice.date)}'),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('المشتري'),
            Text('إسم العميل: ${invoiceData.invoice.customerName ?? ""}'),
            Text('العنوان: ${invoiceData.invoice.customerAddress ?? ""}'),
            Text('المدينة, الرمز البريدي: '),
            Text('الدولة: ${invoiceData.invoice.customerContact ?? ""}'),
          ],
        ),
      ],
    );
  }

  Widget _buildInvoiceTable() {
    return Table(
      border: TableBorder.all(color: Colors.grey),
      columnWidths: const {
        0: FlexColumnWidth(3), // Item Name
        1: FlexColumnWidth(1), // Unit
        2: FlexColumnWidth(1), // Qty
        3: FlexColumnWidth(1.5), // Price
        4: FlexColumnWidth(1.5), // Total
      },
      children: [
        // Header
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: [
            _buildTableCell(
              'اسم الصنف',
              isHeader: true,
              align: TextAlign.right,
            ),
            _buildTableCell('الوحدة', isHeader: true, align: TextAlign.center),
            _buildTableCell('الكمية', isHeader: true, align: TextAlign.center),
            _buildTableCell('السعر', isHeader: true, align: TextAlign.right),
            _buildTableCell('الإجمالي', isHeader: true, align: TextAlign.right),
          ],
        ),
        // Items
        ...invoiceData.items.map(
          (item) => TableRow(
            children: [
              _buildTableCell(
                'منتج #${item.productId}',
                align: TextAlign.right,
              ),
              _buildTableCell('قطعة', align: TextAlign.center), // Default unit
              _buildTableCell('${item.quantity}', align: TextAlign.center),
              _buildTableCell(
                '${item.price.toStringAsFixed(2)} ج.م',
                align: TextAlign.right,
              ),
              _buildTableCell(
                '${(item.quantity * item.price).toStringAsFixed(2)} ج.م',
                isBold: true,
                align: TextAlign.right,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTotalsSection() {
    final subtotal = invoiceData.subtotal;
    final isCredit = invoiceData.invoice.paymentMethod == 'credit';

    return Column(
      children: [
        _buildTotalRow('الصافى', subtotal),
        if (isCredit) ...[
          const Divider(),
          _buildTotalRow(
            'الرصيد الافتتاحي',
            0.0,
          ), // Would need to fetch from customer
          _buildTotalRow('الإجمالي', subtotal, isBold: true),
        ],
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
          Text(
            '${amount.toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    TextAlign? align,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: align ?? TextAlign.right,
        style: TextStyle(
          fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

/// Invoice Data Model
class InvoiceData {
  final Invoice invoice;
  final List<InvoiceItem> items;
  final StoreInfo storeInfo;

  InvoiceData({
    required this.invoice,
    required this.items,
    required this.storeInfo,
  });

  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + (item.quantity * item.price));

  double get grandTotal => invoice.paymentMethod == 'credit'
      ? subtotal // Would add previous balance in real implementation
      : subtotal;
}
