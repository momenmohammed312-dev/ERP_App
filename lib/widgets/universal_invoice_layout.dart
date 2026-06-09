import 'package:flutter/material.dart';

/// Universal Invoice Layout Widget
/// MANDATORY: Used for ALL invoice rendering (print, export, preview)
/// NO EXCEPTIONS - Every invoice must use this exact format
class UniversalInvoiceLayout extends StatelessWidget {
  final InvoiceData invoiceData;
  final bool isForPrinting; // Adjust styling for print vs screen

  const UniversalInvoiceLayout({
    super.key,
    required this.invoiceData,
    this.isForPrinting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.all(isForPrinting ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDeveloperTag(),
            const SizedBox(height: 10),
            _buildHeader(),
            const SizedBox(height: 20),
            _buildCustomerInfo(),
            const SizedBox(height: 20),
            _buildInvoiceTable(),
            const SizedBox(height: 10),
            _buildTotalsSection(),
            if (invoiceData.invoice.notes != null &&
                invoiceData.invoice.notes!.isNotEmpty)
              _buildNotes(),
          ],
        ),
      ),
    );
  }

  /// MANDATORY: "Developed by MO2" must appear on ALL invoices
  Widget _buildDeveloperTag() {
    return Center(
      child: Text(
        'Developed by MO2',
        style: TextStyle(
          fontSize: isForPrinting ? 8 : 10,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Invoice Title
        Text(
          'عرض أسعار',
          style: TextStyle(
            fontSize: isForPrinting ? 20 : 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Store Info
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              invoiceData.storeInfo.storeName,
              style: TextStyle(
                fontSize: isForPrinting ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(invoiceData.storeInfo.phone),
            Text(invoiceData.storeInfo.zipCode),
            Text(invoiceData.storeInfo.state),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomerInfo() {
    final dateFormat =
        '${invoiceData.invoice.invoiceDate.day}/${invoiceData.invoice.invoiceDate.month}/${invoiceData.invoice.invoiceDate.year}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side - Invoice details
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (invoiceData.invoice.projectName != null)
                Text('المشروع: ${invoiceData.invoice.projectName}'),
              Text('رقم الفاتورة: ${invoiceData.invoice.invoiceNumber}'),
              Text('التاريخ: $dateFormat'),
            ],
          ),
          // Right side - Customer details
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'العميل: ${invoiceData.invoice.customerName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('الموبايل: ${invoiceData.invoice.customerPhone}'),
              Text('المدينة: ${invoiceData.invoice.customerZipCode}'),
              Text('الولاية: ${invoiceData.invoice.customerState}'),
            ],
          ),
        ],
      ),
    );
  }

  /// MANDATORY: 4-column table format (Description, Quantity, Price, Total)
  Widget _buildInvoiceTable() {
    return Table(
      border: TableBorder.all(color: Colors.grey[400]!, width: 1),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(1.5),
      },
      children: [
        // Header Row
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: [
            _buildTableCell('الوصف', isHeader: true),
            _buildTableCell('الكمية', isHeader: true, align: TextAlign.center),
            _buildTableCell('السعر', isHeader: true),
            _buildTableCell('الإجمالى', isHeader: true),
          ],
        ),
        // Item Rows
        ...invoiceData.items.map(
          (item) => TableRow(
            children: [
              _buildTableCell(item.description),
              _buildTableCell('${item.quantity}', align: TextAlign.center),
              _buildTableCell('${item.unitPrice.toStringAsFixed(2)} ج.م'),
              _buildTableCell(
                '${item.totalPrice.toStringAsFixed(2)} ج.م',
                isBold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTotalsSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          /// MANDATORY: "الصافي" (Net) must always show
          _buildTotalRow('الصافي', invoiceData.subtotal),
          if (invoiceData.invoice.isCreditAccount) ...[
            const Divider(thickness: 2),
            _buildTotalRow(
              'الرصيد الافتتاحي',
              invoiceData.invoice.previousBalance,
              color: Colors.orange[700],
            ),
            const Divider(thickness: 2),
            _buildTotalRow(
              'إجمالي الرصيد المستحق',
              invoiceData.grandTotal,
              isBold: true,
              fontSize: 18,
              color: Colors.green[700],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotes() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(4),
        color: Colors.grey[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ملاحظات:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(invoiceData.invoice.notes!),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    double amount, {
    bool isBold = false,
    double fontSize = 16,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
              color: color,
            ),
          ),

          /// MANDATORY: All amounts must be formatted as "XX.XX ج.م"
          Text(
            '${amount.toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
              color: color,
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
      padding: EdgeInsets.all(isForPrinting ? 6 : 8),
      child: Text(
        text,
        textAlign: align ?? TextAlign.right,
        style: TextStyle(
          fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: isForPrinting ? 10 : 12,
        ),
      ),
    );
  }
}

/// Enhanced Invoice Data Model with all required fields
/// MANDATORY: Used for ALL invoice operations
class InvoiceData {
  final Invoice invoice;
  final List<InvoiceItem> items;
  final StoreInfo storeInfo;

  InvoiceData({
    required this.invoice,
    required this.items,
    required this.storeInfo,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get grandTotal =>
      invoice.isCreditAccount
          ? invoice.previousBalance + (invoice.totalAmount - invoice.paidAmount)
          : invoice.totalAmount;

  /// MANDATORY: Invoice type labels for different document types
  String get invoiceTypeLabel {
    switch (invoice.invoiceType) {
      case 'sale':
        return 'فاتورة بيع';
      case 'purchase':
        return 'فاتورة شراء';
      case 'quote':
        return 'عرض أسعار';
      case 'return':
        return 'مرتجع';
      default:
        return 'فاتورة';
    }
  }
}

/// Enhanced Store Info Model
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

/// Enhanced Invoice Model with all required fields
class Invoice {
  final int id;
  final String invoiceNumber;
  final String invoiceType; // 'sale', 'purchase', 'quote', 'return'
  final String customerName;
  final String customerPhone;
  final String customerZipCode;
  final String customerState;
  final String? projectName;
  final DateTime invoiceDate;
  final DateTime saleDate;
  final double subtotal;
  final bool isCreditAccount;
  final double previousBalance;
  final double totalAmount;
  final double paidAmount;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceType,
    required this.customerName,
    required this.customerPhone,
    required this.customerZipCode,
    required this.customerState,
    this.projectName,
    required this.invoiceDate,
    required this.saleDate,
    required this.subtotal,
    required this.isCreditAccount,
    required this.previousBalance,
    required this.totalAmount,
    this.paidAmount = 0,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Enhanced Invoice Item Model
class InvoiceItem {
  final int id;
  final int invoiceId;
  final String description;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final int sortOrder;

  InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.sortOrder,
  });
}
